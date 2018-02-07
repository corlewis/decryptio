db_url = "mongodb://127.0.0.1/codewords"
mongoose = require('mongoose')
bcrypt = require('bcrypt')

db = mongoose.connect(db_url)

#
# Database schema definition
#

GAME_LOBBY         = 0
GAME_PREGAME       = 1
GAME_CLUE          = 2
GAME_VOTE          = 3
GAME_FINISHED      = 9

TEAM_RED           = 1
TEAM_BLUE          = 2
TEAM_NONE          = 3

WORD_RED           = 1
WORD_BLUE          = 2
WORD_GREY          = 3
WORD_BLACK         = 4

DEFAULT_WORDS      = 0
DUET_WORDS         = 1
ALL_WORDS          = 2

ObjectId = mongoose.Schema.Types.ObjectId


wordSchema = new mongoose.Schema
    text        : String

Word = mongoose.model('Word', wordSchema)

playerSchema = new mongoose.Schema
    name        : String
    password    : String
    socket      : String
    currentGame : ObjectId

#playerSchema.methods.set_password = (password, cb) ->
#    bcrypt.hash password, 8, (err, hash) ->
#        this.password = hash
#        cb()
#
#playerSchema.methods.check_password = (password, cb) ->
#    bcrypt.compare password, this.password, (err, res) ->
#        cb(err, res)

playerSchema.methods.leave_game = (cb) ->
    player = this

    Game.findById this.currentGame, (err, game) ->
        if err || not game
            cb(err, game)
            return

        for p in game.players
            if p.id.equals(player._id)
                if game.state == GAME_LOBBY || game.state == GAME_PREGAME
                    index = game.players.indexOf(p)
                    game.players.splice(index, 1)
                else
                    p.left = true
                    p.socket = undefined
                break

        if game.players.length == 0
            game.remove()

        game.save (err, game) ->
            cb(err, game)

Player = mongoose.model('Player', playerSchema)

gameSchema = new mongoose.Schema
    state       : {type: Number, default: GAME_LOBBY}
    gameOptions : {
        num_assassins  : {type: Number, default: 1}
        time_limit     : {type: Number, default: 0}
        start_time_limit : {type: Number, default: 0}
        word_set       : {type: Number, default: 0}
    }
    players      : [
        id       : {type: ObjectId, ref: 'Player'}
        name     : String
        socket   : String
        order    : Number
        spy      : Boolean
        team     : Number
        left     : {type: Boolean, default: false}
        info     : [
            otherPlayer : String
            information : String
        ]
    ]
    clues           : [
        team        : Number
        word        : String
        numWords    : Number
        guesses     : [
            word   : String
            player : String
            kind   : Number
        ]
    ]
    words           : [
        word        : String
        kind        : Number
        guessed     : Boolean
    ]
        
    votes        : [
        word     : String
        accepted : [ObjectId]
        rejected : [ObjectId]
        votes    : [
            id      : ObjectId
            vote    : Boolean
        ]
    ]
    currentTeam     : Number
    guessesLeft     : Number
    roundStart      : Date
    timeLimit       : Number
    winningTeam     : Number
    isCoop          : Boolean
    reconnect_vote  : [Number]
    reconnect_user  : String
    reconnect_sock  : String
    created         : {type: Date, default: Date.now}

gameSchema.methods.name = () ->
    names = @players.map (p) -> p.name
    return names.join(', ')

gameSchema.methods.add_player = (p) ->
    for gp in this.players
        if gp.name == p.name
            return false

    this.players.push
        id  : p._id
        name : p.name
        socket : p.socket
        spy : undefined
        team : TEAM_NONE
        info : []
   
    return true

gameSchema.methods.get_player = (id) ->
    for p in this.players
        if p.id.equals(id)
            return p
    return null

shuffle = (a) ->
      for i in [a.length-1..1]
          j = Math.floor Math.random() * (i + 1)
          [a[i], a[j]] = [a[j], a[i]]
      return a

gameSchema.methods.setup_words = () ->
    if this.gameOptions.word_set == DEFAULT_WORDS
        words = shuffle(globalWords)
    else if this.gameOptions.word_set == DUET_WORDS
        words = shuffle(duetWords)
    else
        words = shuffle(globalWords.concat duetWords)
    start_assassins = 25 - this.gameOptions.num_assassins

    for i in [0..8]
        this.words.push
            word : words[i]
            kind : WORD_RED
            guessed : false
    for i in [9..16]
        this.words.push
            word : words[i]
            kind : WORD_BLUE
            guessed : false
    if 17 < start_assassins
        for i in [17...start_assassins]
            this.words.push
                word : words[i]
                kind : WORD_GREY
                guessed : false
    if start_assassins < 25
        for i in [start_assassins..24]
            this.words.push
                word : words[i]
                kind : WORD_BLACK
                guessed : false
    dosort = (a,b) ->
        if a.word < b.word
            return -1
        else if a.word > b.word
            return 1
        else return 0
    this.words.sort(dosort)

gameSchema.methods.other_team = () ->
    if this.currentTeam == TEAM_RED
        return TEAM_BLUE
    else if this.currentTeam == TEAM_BLUE
        return TEAM_RED
    else
        console.log('No other team:', team)
        return TEAM_NONE


gameSchema.methods.next_turn = () ->
    this.currentTeam = this.other_team()
    this.timeLimit = this.gameOptions.time_limit
    this.roundStart = Date.now()
    this.state = GAME_CLUE
    if this.currentTeam == TEAM_BLUE && this.isCoop
        this.state = GAME_VOTE


gameSchema.methods.check_for_game_end = () ->
    red = ((if w.kind == WORD_RED and w.guessed then 1 else 0) for w in this.words)
    red = red.sum()
    blue = ((if w.kind == WORD_BLUE and w.guessed then 1 else 0) for w in this.words) 
    blue = blue.sum()
    black = ((if w.kind == WORD_BLACK and w.guessed then 1 else 0) for w in this.words)
    black = black.sum()

    if red == 9
        this.winningTeam = TEAM_RED
    else if blue == 8
        this.winningTeam = TEAM_BLUE
    else if black == 1
        if this.currentTeam == TEAM_RED
            this.winningTeam = TEAM_BLUE
        else if this.currentTeam == TEAM_BLUE
            this.winningTeam = TEAM_RED

    if not (this.winningTeam == 0)
        this.state = GAME_FINISHED

    return

gameSchema.methods.time_left = ->
    round_time = Math.floor ((Date.now() - this.roundStart) / 1000)
    time_left = this.timeLimit - round_time
    return time_left

gameSchema.methods.start_game = (order, teams, is_coop) ->
    this.state = GAME_CLUE
    this.currentTeam = TEAM_RED
    this.guessesLeft = 0
    this.winningTeam = 0
    this.roundStart = Date.now()
    this.timeLimit = this.gameOptions.start_time_limit

    for p in this.players
        p.spy = teams[p.id].spy
        p.team = teams[p.id].team
        p.order = order[p.id]
    
    #Sort by order
    this.players.sort((a, b) -> a.order - b.order)
    this.isCoop = is_coop
    this.setup_words()

Game = mongoose.model('Game', gameSchema)

