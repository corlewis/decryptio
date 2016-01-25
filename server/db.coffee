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
        numWords    : String
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

globalWords_raw = [
   "STRING", "POISON", "PYRAMID", "SCUBA DIVER",
   "UNDERTAKER", "AZTEC", "ORANGE", "SMUGGLER", "PUPIL",
   "WITCH", "VACUUM", "SOLDIER", "PANTS", "PIPE", "IVORY",
   "SNOW", "BARK", "EAGLE", "BEIJING", "TORCH", "TAG",
   "NUT", "FLUTE", "LINK", "TIME", "LEPRECHAUN", "KID",
   "POLICE", "ROCK", "SCALE", "HOLE", "POST", "LIGHT",
   "TRIANGLE", "BELL", "WATCH", "ARM", "ROSE", "MODEL",
   "THEATER", "MOUSE", "HORSESHOE", "ORGAN", "KNIFE",
   "CELL", "STADIUM", "FOOT", "LIMOUSINE", "CONTRACT",
   "PLATE", "LINE", "MARCH", "AUSTRALIA", "DRAGON",
   "COVER", "CHURCH", "HONEY", "WAR", "TOKYO", "CHANGE",
   "BERMUDA", "LEAD", "LEMON", "CAP", "BELT", "RAY", "BEAT",
   "FALL", "LONDON", "WIND", "NURSE", "PASS", "KNIGHT", "SLIP",
   "SHOP", "FIGHTER", "BOW", "MERCURY", "BALL", "MATCH", "OLIVE",
   "POINT", "COTTON", "DATE", "FRANCE", "NET", "CROSS", "DIAMOND",
   "TIE", "COURT", "CARD", "HOOD", "DUCK", "BAND", "ROBIN", "POOL",
   "STAR", "BRIDGE", "FIRE", "RING", "HEART", "HORN", "SPRING", "TABLE",
   "WHALE", "SEAL", "MOON", "BLOCK", "DRILL", "FISH", "TUBE", "GRACE",
   "IRON", "DOCTOR", "ROULETTE", "DEGREE", "WAKE", "NEEDLE", "TABLET",
   "PIE", "GREEN", "AGENT", "DROP", "SNOWMAN", "CAPITAL", "CANADA",
   "TRACK", "BANK", "FOREST", "STRIKE", "CONCERT", "BOMB", "CLIFF",
   "COPPER", "SOUL", "CHOCOLATE", "SKYSCRAPER", "CASINO", "JET", "SHAKESPEARE",
   "WAVE", "SHADOW", "GLOVE", "LITTER", "COMIC", "MILLIONAIRE", "TELESCOPE",
   "AMAZON", "SHOT", "PLANE", "NIGHT", "PLATYPUS", "WASHER", "TRAIN", "LAP",
   "BOX", "IRON", "TUBE", "FIRE", "MERCURY", "INDIA", "BRIDGE", "DEGREE", "STAR",
   "DOCTOR", "MOON", "BLOCK", "GREEN", "HORN", "SEAL", "CYCLE", "LUCK",
   "CAT", "ROME", "STICK", "GAME", "FIELD", "LIFE", "MOUNT", "MATCH",
   "POINT", "BAND", "ROULETTE", "ROUND", "ROBIN", "BOW", "POOL", "BALL",
   "NET", "SHOP", "PASS", "CARD", "CROSS", "HOOK", "DECK", "PIRATE", "BUTTON",
   "BUGLE", "PARK", "YARD", "BEACH", "HIMALAYAS", "MOUTH", "BAT",
   "CONDUCTOR", "POUND", "NINJA", "TAG", "BOLT", "GIANT", "PAPER", "CZECH",
   "GREECE", "FACE", "SLUG", "GROUND", "WORM", "CHEST", "FIGURE", "COMPOUND",
   "CHARGE", "ICE", "GROUND", "FILM", "SQUARE", "HORSE", "TAP", "NAIL", "DOG",
   "MASS", "SPACE", "SOCK", "SUB", "PAPER", "BERLIN", "OLYMPUS", "ALPS",
   "CHINA", "CROWN", "BUFFALO", "BACK", "PART", "WAR", "HONEY", "JAM",
   "CHURCH", "COVER", "LEAD", "BERMUDA", "CHANGE", "TOKYO", "EGYPT",
   "BEAT", "RAY", "BELT", "CAP", "LEMON", "NURSE", "WIND", "LION",
   "LONDON", "FALL", "BOOT", "DICE", "EYE", "BOARD", "SWITCH" 
]

Array::unique = ->
  output = {}
  output[@[key]] = @[key] for key in [0...@length]
  value for key, value of output

globalWords = globalWords_raw.unique()

shuffle = (a) ->
      for i in [a.length-1..1]
          j = Math.floor Math.random() * (i + 1)
          [a[i], a[j]] = [a[j], a[i]]
      return a

gameSchema.methods.setup_words = () ->
    words = shuffle(globalWords)
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

gameSchema.methods.start_game = (order, teams, is_coop) ->
    this.state = GAME_CLUE
    this.currentTeam = TEAM_RED
    this.guessesLeft = 0
    this.winningTeam = 0
    for p in this.players
        p.spy = teams[p.id].spy
        p.team = teams[p.id].team
        p.order = order[p.id]
    
    #Sort by order
    this.players.sort((a, b) -> a.order - b.order)
    this.isCoop = is_coop
    this.setup_words()

Game = mongoose.model('Game', gameSchema)

