db_url = "mongodb://127.0.0.1/decryptio"
mongoose = require('mongoose')
bcrypt = require('bcrypt')

db = mongoose.connect(db_url)

#
# Database schema definition
#

GAME_LOBBY         = 0
GAME_PREGAME       = 1
GAME_ENCRYPT       = 2
GAME_DECRYPT_RED   = 3
GAME_DECRYPT_BLUE  = 4
GAME_FINISHED      = 9

TEAM_RED           = 0
TEAM_BLUE          = 1
TEAM_NONE          = 2
TEAMS              = [TEAM_RED, TEAM_BLUE]

DEFAULT_WORDS      = 0
DUET_WORDS         = 1
ALL_WORDS          = 2

other_team = (team) ->
    if team == TEAM_RED
        return TEAM_BLUE
    else if team == TEAM_BLUE
        return TEAM_RED
    else
        console.log('No other team:', team)
        return TEAM_NONE

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

# Many fields are indexed by hardcoded team id's. This is a disgusting
# hack after I gave up on Mongo storing the more complicated structures
# I originally used.
# As an example of how to use them, 'this["codes"+0]' is equivalent to
# 'this.codes0' (and I originally would have had 'this.codes[0]').
# Similarly, 'this.score[0]' is equivalent to 'this.score.0'
messageSchema = new mongoose.Schema
    spy : String
    message : {clues: [String], finished: Boolean}
    guess0 : {code: [Number], finished: Boolean}
    guess1 : {code: [Number], finished: Boolean}

gameSchema = new mongoose.Schema
    state       : {type: Number, default: GAME_LOBBY}
    gameOptions : {
        num_words  : {type: Number, default: 4}
        code_length  : {type: Number, default: 3}
        encrypt_time_limit : {type: Number, default: 0}
        decrypt_time_limit : {type: Number, default: 0}
        word_set       : {type: Number, default: ALL_WORDS}
    }
    players      : [
        id       : {type: ObjectId, ref: 'Player'}
        name     : String
        socket   : String
        order    : Number
        team     : Number
        left     : {type: Boolean, default: false}
    ]
    codes0 : [[Number]]
    codes1 : [[Number]]
    messages0 : [messageSchema]
    messages1 : [messageSchema]
    score : {
        0 :
            intercepts        : {type: Number, default: 0}
            miscommunications : {type: Number, default: 0}
        1 :
            intercepts        : {type: Number, default: 0}
            miscommunications : {type: Number, default: 0}
    }

    round           : {type: Number, default: 0}
    roundStart      : Date
    timeLimit       : Number
    currentSpy      : {0: ObjectId, 1: ObjectId}
    teamLength      : {0: Number, 1: Number}
    keywords        : {0: [String], 1: [String]}
    winningTeam     : {type: Number, default: TEAM_NONE}
    isCoop          : {type: Boolean, default: false}
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
        team : TEAM_NONE
   
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

    num_words = this.gameOptions.num_words
    for i in TEAMS
        this.keywords[i] = []
        for j in [0..num_words - 1]
            this.keywords[i].push words[i * num_words + j]

gameSchema.methods.set_next_spies = () ->
    next = [-1, -1]
    for p in this.players
        if p.id.equals(this.currentSpy[p.team])
            next[p.team] = (p.order + 1) % this.teamLength[p.team]

    for p in this.players
        if p.order == next[p.team]
            this.currentSpy[p.team] = p.id

gameSchema.methods.create_next_message = () ->
    for i in TEAMS
        code = shuffle([1..this.gameOptions.num_words])[..this.gameOptions.code_length - 1]
        this["messages"+i].push
            spy      : this.get_player(this.currentSpy[i]).name
            message  : {clues: [], finished: false}
            guess0   : {code: [], finished: false}
            guess1   : {code: [], finished: false}
        this["codes"+i].push code
    this.round++

gameSchema.methods.check_for_game_end = () ->
    red_int = this.score[TEAM_RED].intercepts
    red_miss = this.score[TEAM_RED].miscommunications
    blue_int = this.score[TEAM_BLUE].intercepts
    blue_miss = this.score[TEAM_BLUE].miscommunications
    red_win = red_int >= 2 || blue_miss >= 2
    blue_win = blue_int >= 2 || red_miss >= 2

    if this.round >= 8 || (red_win && blue_win)
        this.winningTeam =
            if red_int - red_miss > blue_int - blue_miss
                TEAM_RED
            else if red_int - red_miss < blue_int - blue_miss
                TEAM_BLUE
            else
                TEAM_NONE
    else if red_win
        this.winningTeam = TEAM_RED
    else if blue_win
        this.winningTeam = TEAM_BLUE

    if this.round >= 8 || red_win || blue_win
        this.state = GAME_FINISHED
        return true
    else
        return false

gameSchema.methods.time_left = ->
    round_time = Math.floor ((Date.now() - this.roundStart) / 1000)
    time_left = this.timeLimit - round_time
    return time_left

gameSchema.methods.reset_timer = (time_limit) ->
    this.timeLimit = time_limit
    this.roundStart = Date.now()

gameSchema.methods.start_game = (teams, is_coop) ->
    this.state = GAME_ENCRYPT
    this.round = 0
    order = [0,0]
    spy = [-1, -1]

    for p in this.players
        p.team = teams[p.id].team
        p.order = order[p.team]
        order[p.team] += 1
        if teams[p.id].spy
            spy[p.team] = p.order
    for i in TEAMS
        this.teamLength[i] = order[i]
    
    #Sort by order
    this.players.sort((a, b) -> a.team - b.team or a.order - b.order)

    for i in TEAMS
        if spy[i] == -1
            spy[i] = Math.floor Math.random() * this.teamLength[i]
    for p in this.players
        if p.order == spy[p.team]
           this.currentSpy[p.team] = p.id
           
    this.isCoop = is_coop
    this.setup_words()
    this.create_next_message()
    fake_code = Array(this.gameOptions.code_length).fill(-1)
    for i in TEAMS
        this.make_guess(i, fake_code, other_team i)
    this.timeLimit = 0

gameSchema.methods.make_guess = (state_team, code, p_team) ->
    round = this.round - 1
    m = this["messages"+state_team][round]
    m["guess"+p_team].code = deep_copy(code)
    m["guess"+p_team].finished = true

    if m["guess"+other_team p_team].finished
        code = this["codes"+state_team][round]
        if not arraysEqual(m["guess"+state_team].code, code)
            this.score[state_team].miscommunications += 1
        if arraysEqual(m["guess"+other_team state_team].code, code)
            this.score[other_team state_team].intercepts += 1
        return true
    else
        this.reset_timer(this.gameOptions.decrypt_time_limit)
        return false

Game = mongoose.model('Game', gameSchema)

deep_copy = (o) ->
    output = if Array.isArray(o) then [] else {}
    for key, v of o
        output[key] = if typeof v == "object" && v != null then deep_copy(v) else v
    return output

returnInt = (n) -> parseInt(n, 10)

isArray = Array.isArray || (subject) ->
    toString.call(subject) is '[object Array]'

arraysEqual = (a, b) ->
    unless isArray(a) and isArray b
        throw new Error '`arraysAreEqual` called with non-array'

    return false if a.length isnt b.length

    for valueInA, index in a
        return false if b[index] isnt valueInA

    true
