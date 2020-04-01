#
# Server side game functions
#

Q = require('q')

Array::sum = () ->
    @reduce (x, y) -> x + y

zip = () ->
  lengthArray = (arr.length for arr in arguments)
  length = Math.min(lengthArray...)
  for i in [0...length]
    arr[i] for arr in arguments

VERSION = 5


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
        score           : game.score
        round           : game.round
        timeLimit       : game.timeLimit
        currentSpy      : [ObjectId]
        winningTeam     : game.winningTeam
        timeLeft        : game.time_left()
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
            spy         : p.team != TEAM_NONE && p.id.equals(game.currentSpy[p.team])
            team        : p.team

    data.players = players

    data.tiedFinish = []
    for i in TEAMS
        data.tiedFinish.push (game.tiedFinish[i].length > 0)

    #Hide unfinished messages
    messages = []
    for [m_red, m_blue] in zip(game.messages0, game.messages1)
        dm = {0: JSON.parse(JSON.stringify(m_red)), 1: JSON.parse(JSON.stringify(m_blue))}
        if not dm[TEAM_RED].message.finished || not dm[TEAM_BLUE].message.finished
            for i in TEAMS
                dm[i].message.clues = []
        finished_guessing = true
        for i in TEAMS
            for j in TEAMS
                finished_guessing = finished_guessing && dm[i]["guess"+j].finished
        if not finished_guessing
            for i in TEAMS
                for j in TEAMS
                    dm[i]["guess"+j].code = []
        messages.push dm
    data.messages = messages

    #Hide current codes
    codes = zip(game.codes0, game.codes1)
    round = game.round - 1
    for i in TEAMS
        m = game["messages"+i][round]
        if round >= 0 && not game.both_finished_guessing()
            codes[round][i] = []
    data.codes = codes

    #Add in secret info specific to player as we go
    for s in socks
        i = s.player
        data.me = data.players[i]

        team = data.players[i].team
        round = game.round - 1
        if team in TEAMS && round >= 0
            if data.me.spy
                data.current_code = game["codes"+team][round]
            else
                data.current_code = []
            data.keywords = game.keywords[team]
        if s.socket
            timeinfo =
                timeleft : data.timeLeft

            s.socket.emit('timeleft', timeinfo)
            s.socket.emit(tagged, data)
        data.code = []
        data.keywords = []


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
      
                if vs >= (realplayers / 2)
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
                if game.players.length >= 3
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


    socket.on 'teaminfo', (data) ->
        player = socket.player
        return if not player

        Game.findById player.currentGame, (err, game) ->
            return if err || not game

            for p in game.players
                p.team = data[p.id].team

            game.save()
            send_game_info(game, undefined, 'teaminfo')


    socket.on 'startgame', (data) ->
        player = socket.player
        return if not player
        Game.findById player.currentGame, (err, game) ->
            return if err || not game

            teams = data.teams
            is_coop = data.is_coop 
            game.gameOptions.num_words = data.options.num_words
            if data.options.code_length > data.options.num_words
                game.gameOptions.code_length = data.options.num_words
            else
                game.gameOptions.code_length = data.options.code_length
            game.gameOptions.encrypt_time_limit = data.options.encrypt_time_limit
            game.gameOptions.decrypt_time_limit = data.options.decrypt_time_limit
            game.gameOptions.word_set = data.options.word_set

            game.start_game(teams, is_coop)
            game.save((err) =>
                if err then console.log(err))
            send_game_info(game)

    socket.on 'give_clue', (data) ->
        player = socket.player
        return if not player
        Game.findById player.currentGame, (err, game) ->
            return if err || not game

            p = game.get_player(player._id)
            team = p.team
            round = game.round - 1
            m = game["messages"+team][round]
            other_m = game["messages"+other_team team][round]
            if game.state != GAME_ENCRYPT || not p.id.equals(game.currentSpy[team]) ||
                                             m.message.finished
                return
            for clue in data.clues
                m.message.clues.push clue
            m.message.finished = true

            if other_m.message.finished
                game.state = GAME_DECRYPT
                game.timeLimit = 0
            else
                game.reset_timer(game.gameOptions.encrypt_time_limit)

            game.save((err) =>
                if err then console.log(err))
            send_game_info(game)


    socket.on 'force_end_encrypt', () ->
        player = socket.player
        return if not player

        Game.findById player.currentGame, (err, game) ->
            return if err || not game

            time_left = game.time_left()
            p = game.get_player(player._id)
            team = p.team
            round = game.round - 1
            m = game["messages"+team][round]
            other_m = game["messages"+other_team team][round]
            if time_left > 0 || game.state != GAME_ENCRYPT || not m.message.finished ||
                                other_m.message.finished
                return

            other_m.message.clues = Array(game.gameOptions.code_length).fill("<Turn Timeout>")
            other_m.message.finished = true

            game.state = GAME_DECRYPT
            game.timeLimit = 0
            game.save()
            send_game_info(game)

    socket.on 'make_guess', (data) ->
        player = socket.player
        return if not player
        Game.findById player.currentGame, (err, game) ->
            return if err || not game

            p = game.get_player(player._id)
            round = game.round - 1
            cur_guess = -1
            for i in TEAMS by -1
                if not game["messages"+i][round]["guess"+p.team].finished
                    cur_guess = i
            if cur_guess == -1
                return
            code = data.code.map(returnInt)

            if game.state == GAME_DECRYPT && not p.id.equals(game.currentSpy[cur_guess]) &&
                    not game["messages"+cur_guess][round]["guess"+p.team].finished
                game.make_guess(cur_guess, code, p.team)
                if game.finished_guessing(p.team)
                    game.reset_timer(game.gameOptions.decrypt_time_limit)
                    if game.finished_guessing(other_team p.team)
                        game.finish_decryption()
                        if game.check_for_game_end()
                            game.state = GAME_PRE_FINISHED
                            game.timeLimit = 0
                        else
                            game.state = GAME_ENCRYPT
                            game.timeLimit = 0
                            game.set_next_spies()
                            game.create_next_message()
            else
                return

            game.save((err) =>
                if err then console.log(err))
            send_game_info(game)

    socket.on 'force_end_decrypt', () ->
        player = socket.player
        return if not player

        Game.findById player.currentGame, (err, game) ->
            return if err || not game

            if game.time_left() > 0 || game.isCoop
                return

            p = game.get_player(player._id)
            round = game.round - 1
            red_m = game["messages"+TEAM_RED][round]
            blue_m = game["messages"+TEAM_BLUE][round]
            fake_code = Array(game.gameOptions.code_length).fill(-1)

            if game.state == GAME_DECRYPT && game.finished_guessing(p.team)
                if not red_m["guess"+other_team p.team].finished
                    game.make_guess(TEAM_RED, fake_code, other_team p.team)
                if not blue_m["guess"+other_team p.team].finished
                    game.make_guess(TEAM_BLUE, fake_code, other_team p.team)
                game.finish_decryption()
                if game.check_for_game_end()
                    game.state = GAME_PRE_FINISHED
                    game.timeLimit = 0
                else
                    game.state = GAME_ENCRYPT
                    game.timeLimit = 0
                    game.set_next_spies()
                    game.create_next_message()
            else
                return

            game.save()
            send_game_info(game)


    socket.on 'guess_words', (data) ->
        player = socket.player
        return if not player
        Game.findById player.currentGame, (err, game) ->
            return if err || not game

            p = game.get_player(player._id)
            team = p.team
            if game.state != GAME_PRE_FINISHED || game.tiedFinish[team].length > 0 ||
               data.length != game.gameOptions.num_words
                return

            for word in data
                game.tiedFinish[team].push word

            if game.tiedFinish[other_team team].length > 0
                game.state = GAME_FINISHED
            else
                game.reset_timer(game.gameOptions.encrypt_time_limit)

            game.save((err) =>
                if err then console.log(err))
            send_game_info(game)


    socket.on 'force_end_guess_words', () ->
        player = socket.player
        return if not player
        Game.findById player.currentGame, (err, game) ->
            return if err || not game

            time_left = game.time_left()
            p = game.get_player(player._id)
            team = p.team
            if time_left > 0 || game.state != GAME_PRE_FINISHED ||
               game.tiedFinish[team].length == 0 ||
               game.tiedFinish[other_team team].length > 0
                return

            for [0...game.gameOptions.num_words]
                game.tiedFinish[other_team team].push ""

            game.state = GAME_FINISHED
            game.save((err) =>
                if err then console.log(err))
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
