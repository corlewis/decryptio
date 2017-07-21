#
# Server side game functions
#

Q = require('q')

Array::sum = () ->
    @reduce (x, y) -> x + y

VERSION = 3


send_game_list = () ->
    Game.find {}, (err, games) ->
        data =
            version : VERSION
        gamelist = []
        for g in games
            game = 
                id : g.id
                name : g.name()
                num_players : g.players.length
                state : g.state
            if game.state != GAME_PREGAME && game.state != GAME_FINISHED
                gamelist.push game
        data.gamelist = gamelist
        
        io.sockets.in('lobby').emit('gamelist', data)


send_game_info = (game, to = undefined, tagged = 'gameinfo') ->
    data =
        state           : game.state
        options         : game.gameOptions
        id              : game.id
        currentTeam     : game.currentTeam
        guessesLeft     : game.guessesLeft
        timeLimit       : game.timeLimit
        timeLeft        : game.time_left()
        clues           : game.clues
        isCoop          : game.isCoop
        reconnect_user  : game.reconnect_user
        reconnect_vote  : game.reconnect_vote
        version         : VERSION

    #Overwrite player data (to hide secret info)
    #Split out socket ids while we're at it, no need to send them
    players = []
    socks = []
    for p, i in game.players
        if to == undefined || p.id.equals(to)
            socks.push
                socket  : io.sockets.sockets[p.socket]
                player  : i
        players.push
            id          : p.id
            name        : p.name
            order       : p.order
            spy         : p.spy
            team        : p.team

    data.players = players

    #Hide unfinished votes
    words = []
    words_secret = []
    for w in game.words
        dw = {word: w.word, guessed: w.guessed, kind: undefined}
        words.push dw
        dw.kind = w.kind
        words_secret.push dw

    #Add in secret info specific to player as we go
    for s in socks
        i = s.player
        data.players[i].info = game.players[i].info
        data.me = data.players[i]
        if i.spy
            data.words = words_secret
        else
            data.words = words
        if s.socket
            timeinfo = 
                timeleft : data.timeLeft

            s.socket.emit('timeleft', timeinfo)
            s.socket.emit(tagged, data)
        data.words = []
        data.players[i].info = []


#
# Socket handling
#

io.on 'connection', (socket) ->
    cookies = socket.handshake.headers.cookie
    player_id = cookies['player_id']
    if not player_id
        socket.emit('bad_login')
    else
        Player.findById player_id, (err, player) ->
            if err || not player
                socket.emit('bad_login')
                return

            player.socket = socket.id
            player.save()
            socket.player = player
            if not player.currentGame
                socket.join('lobby')
                send_game_list()
                return
            
            #Reconnect to game
            Game.findById player.currentGame, (err, game) ->
                if err || not game
                    socket.join('lobby')
                    send_game_list()
                    return
                for p in game.players
                    if p.id.equals(player_id)
                        if p.left || game.state == GAME_FINISHED
                            p.left = true
                            socket.emit('previous_game', game._id)
                            socket.join('lobby')
                            send_game_list()
                        else
                            p.socket = socket.id
                            game.save (err, game) ->
                                send_game_info(game, player_id)
                        return

                #Not in your current game
                socket.join('lobby')
                send_game_list()

    newuser = (name) ->
        player = new Player()
        player.name = name
        player.socket = socket.id
        player.save()
        socket.player = player
        socket.emit('player_id', player._id)
        socket.join('lobby')
        send_game_list()


    socket.on 'finishstale', (data) ->
        Game.find {}, (err, games) ->
            for g in games
                has_active = false
                promises = []
    
                for p in g.players
                    if io.sockets.sockets[p.socket]
                        has_active
    
                if not (has_active) && g.state != GAME_FINISHED
                    g.state = GAME_FINISHED
                    g.save()
            


    socket.on 'login', (data) ->
        player = socket.player
        if player
            #Player is changing their name
            player.name = data.name
            player.save()
            send_game_list()
            return
        Player.find {'name' : data.name}, (err, ps) ->
            if err || not ps
                #No player exists with that name so make a new one
                newuser data.name
                return

            games = []
            promises = []
            players = []
            for p in ps
                if not p.currentGame
                    continue
                promises.push(Game.findById(p.currentGame).exec())
                players.push(p)

            Q.all(promises).then (results) ->
                games = []
                for game, i in results
                    if not game || game.state <= GAME_PREGAME || game.state >= GAME_FINISHED
                        continue
                    data =
                        id      : game._id
                        name    : game.name()
                        player  : players[i]._id
                    games.push(data)

                if games.length != 0
                    socket.emit('reconnectlist', games)
                else
                    newuser data['name']

    socket.on 'noreconnect', (data) ->
        newuser data.name

    socket.on 'reconnectuser', (data) ->
        Player.findById data.player_id, (err, player) ->
            return if err || not player

            if not player.currentGame.equals(data.game_id)
                socket.join('lobby')
                send_game_list()
                return

            Game.findById player.currentGame, (err, game) ->
                if err || not game
                    socket.join('lobby')
                    send_game_list()
                    return

                #Call a reconnection vote
                #TODO: Tell user to wait if vote ongoing
                game.reconnect_user = player.name
                game.reconnect_sock = socket.id
                game.reconnect_vote = (0 for p in game.players)
                game.save()
                send_game_info(game)
                socket.player = player

    socket.on 'reconnect_vote', (rvote) ->
        player = socket.player
        return if not player
        Game.findById player.currentGame, (err, game) ->
            return if err || not game
            order = -1
            for p in game.players
                if p.id.equals(player._id)
                    order = p.order
                    team = p.team
            return if order == -1
            return if team == TEAM_NONE
        
            if rvote
                game.reconnect_vote.set(order, 1)
                vs = (v for v in game.reconnect_vote)
                vs = vs.sum()
                realplayers = -1
                for p in game.players
                    if p.team != TEAM_NONE
                        realplayers += 1
      
                if vs > (realplayers / 2)
                    sock = io.sockets.sockets[game.reconnect_sock]
                    #Save player's socket data
                    if sock && sock.player
                        player = sock.player
                        player.socket = sock.id
                        player.save()
                        sock.emit('player_id', player._id)

                        for p in game.players
                            if p.id.equals(player._id)
                                p.socket = sock.id
                                break

                    game.reconnect_user = undefined
                    game.reconnect_sock = undefined
                    game.reconnect_vote = (0 for p in game.players)

                    game.save()
                    send_game_info(game)
                else
                    game.save()
                    send_game_info(game)

            else
                #One denial is enough
                sock = io.sockets.sockets[game.reconnect_sock]
                game.reconnect_user = undefined
                game.reconnect_sock = undefined
                game.reconnect_vote = (0 for p in game.players)

                game.save()
                send_game_info(game)

                sock.emit('reconnectdenied')

    socket.on 'newgame', (game) ->
        player = socket.player
        return if not player
        if not player.name || player.name == ""
            socket.emit 'bad_login'
            return
        game = new Game()
        game.add_player player
        game.save (err, game) ->
            socket.leave('lobby')
            player.currentGame = game._id
            player.save()
            send_game_list()
            send_game_info(game)

    socket.on 'joingame', (data) ->
        game_id = data.game_id
        player = socket.player
        return if not player

        if not player.name || player.name == ""
            socket.emit 'bad_login'
            return

        if player.currentGame
            player.leave_game (err, game) ->
                if game then send_game_info(game)
                send_game_list()
        Game.findById game_id, (err, game) ->
            return if not game

            if game.state == GAME_PREGAME || game.state == GAME_FINISHED
                send_game_list()
                return
            new_player = true
            for gp in game.players
                if gp.id.equals(player_id) && gp.name == player.name 
                    gp.id = player_id
                    gp.socket = socket.id
                    gp.left = false
                    new_player = false
            added = false
            reconnected = false
            if new_player
                added = game.add_player player
                if not added
                    ex_gp = undefined
                    for gp in game.players
                        if gp.name == player.name
                            ex_gp = gp

                    data =
                        id      : game._id
                        name    : game.name()
                        player  : ex_gp.id
                    socket.emit('reconnectlist', [data])
                    reconnected = true
                    
            #TODO check if player was actually added
            if not reconnected
                game.save (err, game) ->
                    socket.leave('lobby')
                    player.currentGame = game._id
                    player.save()
                    socket.player = player
                    send_game_list()
                    send_game_info(game)

    socket.on 'reconnecttogame', () ->
        player = socket.player
        return if not player || not player_id
        Game.findById player.currentGame, (err, game) ->
            return if not game
            socket.leave('lobby')
            for p in game.players
                if p.id.equals(player_id)
                    p.socket = socket.id
                    p.left = false
            game.save (err, game) ->
                send_game_info(game, player_id)

    socket.on 'ready', () ->
        player = socket.player
        return if not player
        Game.findById player.currentGame, (err, game) ->
            return if err || not game
            if game.players[0].socket == socket.id
                if game.players.length >= 2
                    game.state = GAME_PREGAME

            game.save()
            send_game_info(game)

    socket.on 'kick', (player_id) ->
        player = socket.player
        return if not player
        Game.findById player.currentGame, (err, game) ->
            return if err || not game
            if game.players[0].socket == socket.id
                Player.findById player_id, (err, target) ->
                    return if err || not target
                    target.leave_game (err, game) ->
                        if game then send_game_info(game)
                        s = io.sockets.sockets[target.socket]
                        if s
                            s.emit('kicked')
                            s.join('lobby')
                        send_game_list()

    socket.on 'timeleft', () ->
        player = socket.player
        return if not player
 
        Game.findById player.currentGame, (err, game) ->
            return if err || not game

            timeinfo = 
                timeleft : game.time_left()

            socket.emit('timeleft', timeinfo)

    socket.on 'force_end', () ->
        player = socket.player
        return if not player
   

        Game.findById player.currentGame, (err, game) ->
            return if err || not game

            time_left = game.time_left()

            if time_left > 0 || game.state != GAME_CLUE
                return
            else
                game.clues.push
                    word : "<Turn Timeout>"
                    numWords : 100
                    team : game.currentTeam

                game.guessesLeft = 100
                game.state = GAME_VOTE
                game.save()
                send_game_info(game)
                  

   
    socket.on 'teaminfo', (data) ->
        player = socket.player
        return if not player

        Game.findById player.currentGame, (err, game) ->
            return if err || not game

            for p in game.players
                p.team = data[p.id].team
                p.spy = data[p.id].spy

            game.save()
            send_game_info(game, undefined, 'teaminfo')


    socket.on 'startgame', (data) ->
        player = socket.player
        return if not player
        Game.findById player.currentGame, (err, game) ->
            return if err || not game
            order = data.order
            teams = data.teams
            is_coop = data.is_coop 
            game.gameOptions.num_assassins = data.options.num_assassins
            game.gameOptions.time_limit = data.options.time_limit
            game.gameOptions.start_time_limit = data.options.start_time_limit

            #Sanity check
            return if Object.keys(order).length != game.players.length
            game.start_game(order, teams, is_coop)
            game.save()
            send_game_info(game)

    socket.on 'pass_turn', (data) ->
        player = socket.player
        return if not player
        Game.findById player.currentGame, (err, game) ->
            return if err || not game
            game.next_turn()
            game.save()
            send_game_info(game)

    socket.on 'give_clue', (data) ->
        player = socket.player
        return if not player
        Game.findById player.currentGame, (err, game) ->
            return if err || not game

            if game.state != GAME_CLUE
                return

            game.clues.push
                word : data.word
                numWords : data.numWords
                team : game.currentTeam
                guesses : []

            game.guessesLeft = data.numWords
            game.guessesLeft += 1

            if game.guessesLeft == 1
                game.guessesLeft = 100

            game.state = GAME_VOTE

            game.save()
            send_game_info(game)

    socket.on 'make_guess', (data) ->
        player = socket.player
        return if not player
        Game.findById player.currentGame, (err, game) ->
            return if err || not game

            if game.state != GAME_VOTE
                return

            currClue = game.clues[game.clues.length - 1]
            for w in game.words
                if w.word == data
                    if w.guessed
                        return
                    w.guessed = true
                    kind = w.kind
                    currClue.guesses.push
                        word   : data
                        player : player.name
                        kind   : kind

            game.guessesLeft -= 1
            switch_teams = false

            if kind == WORD_RED && game.currentTeam != TEAM_RED
                switch_teams = true
            else if kind == WORD_BLUE && game.currentTeam != TEAM_BLUE
                switch_teams = true
            else if game.isCoop && kind == WORD_BLUE && game.currentTeam == TEAM_BLUE
                switch_teams = true
            else if kind == WORD_GREY || game.guessesLeft < 1
                switch_teams = true

            if switch_teams
                game.next_turn()

            game.check_for_game_end()
            game.save()
            send_game_info(game)

    socket.on 'leavegame', () ->
        socket.join('lobby')
        player = socket.player
        return if not player
        player.leave_game (err, game) ->
            if game then send_game_info(game)
            send_game_list()
  
    socket.on 'disconnect', () ->
        #Do we need to do something here?
        return
