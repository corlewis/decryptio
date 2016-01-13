#
# Server side game functions
#

Q = require('q')

Array::sum = () ->
    @reduce (x, y) -> x + y

VERSION = 1

send_game_list = () ->
    Game.find {}, (err, games) ->
        data =
            version : VERSION
        gamelist = []
        for g in games
            if (g.state == GAME_LOBBY) then gamelist.push
                id : g.id
                name : g.name()
                num_players : g.players.length
        data.gamelist = gamelist
        io.sockets.in('lobby').emit('gamelist', data)

send_game_info = (game, to = undefined) ->
    data =
        state           : game.state
        options         : game.gameOptions
        id              : game.id
        currentTeam     : game.currentTeam
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
            s.socket.emit('gameinfo', data)
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

    socket.on 'login', (data) ->
        player = socket.player
        if player
            #Player is changing their name
            player.name = data.name
            player.save()
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
                    if not game || game.status <= GAME_PREGAME || game.status >= GAME_FINISHED
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
        return not player
        Game.findById player.currentGame, (err, game) ->
            return if err || not game

            order = -1
            for p in game.players
                if p.id.equals(player._id)
                    order = p.order
            return if order == -1

            if rvote
                game.reconnect_vote.set(order, 1)
                vs = (v for v in game.reconnect_vote)
                vs = vs.sum()

                if vs > (game.players.length / 2)
                    sock = io.sockets.sockets[game.reconnect_sock]
                    #Save player's socket data
                    sock.get 'player', (err, player) ->
                        if player && not err
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
        if player.currentGame
            player.leave_game (err, game) ->
                if game then send_game_info(game)
                send_game_list()

        Game.findById game_id, (err, game) ->
            return if not game
            game.add_player player
            #TODO check if player was actually added
            game.save (err, game) ->
                socket.leave('lobby')
                player.currentGame = game._id
                player.save()
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
                if game.players.length >= 4
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
                        s.emit('kicked')
                        s.join('lobby')
                        send_game_list()

    socket.on 'startgame', (data) ->
        player = socket.player
        return if not player
        Game.findById player.currentGame, (err, game) ->
            return if err || not game
            order = data.order
            red_id = data.red_id
            blue_id = data.blue_id
            
            #Sanity check
            return if Object.keys(order).length != game.players.length

            game.start_game(order, red_id, blue_id)
            game.save()
            send_game_info(game)

    socket.on 'make_guess', (data) ->
        player = socket.player
        return if not player
        Game.findById player.currentGame, (err, game) ->
            return if err || not game

            if game.state == GAME_VOTE || game.state == GAME_CLUE
                for w in game.words
                    if w.word == data
                        w.guessed = true
            if game.currentTeam == TEAM_BLUE
                game.currentTeam = TEAM_RED
            else if game.currentTeam == TEAM_RED
                game.currentTeam = TEAM_BLUE
            game.save()
            send_game_info(game)

    socket.on 'vote', (data) ->
        player = socket.player
        return if not player
        Game.findById player.currentGame, (err, game) ->
            return if err || not game
            currVote = game.votes[game.votes.length - 1]

            #Check to prevent double voting
            for p in currVote.votes
                voted = true if player._id.equals(p.id)
            return if voted

            currVote.votes.push
                id      : player._id
                vote    : data

            #Check for vote end
            if currVote.votes.length == game.players.length
                vs = ((if v.vote then 1 else 0) for v in currVote.votes)
                vs = vs.sum()
                vote_passed = vs > (game.players.length - vs)
                vote_count = 0

                if game.state == GAME_VOTE
                    new_mission = false
                    if vote_passed
                        game.state = GAME_QUEST
                    else
                        game.state = GAME_PROPOSE

                        #Check for too many failed votes
                        for v in game.votes
                            if v.mission == game.currentMission
                                vote_count += 1

                        if vote_count == 5
                            if game.gameOptions.ptrc
                                game.state = GAME_PTRC_PROPOSE
                            else
                                new_mission = true
                                currMission = game.missions[game.currentMission]
                                currMission.status = 1
                                game.check_for_game_end()

                    game.set_next_leader(vote_passed || new_mission)
                else
                    #In state GAME_PTRC_VOTE
                    if vote_passed
                        currVote.accepted = currVote.accepted.concat(currVote.team)
                    else
                        currVote.rejected = currVote.rejected.concat(currVote.team)

                    #Check for full team
                    currMission = game.missions[game.currentMission]
                    votedOn = currVote.accepted.concat(currVote.rejected)
                    numNotVotedOn = game.players.length - votedOn.length
                    if currVote.accepted.length == currMission.numReq ||
                       currVote.accepted.length + numNotVotedOn == currMission.numReq
                        notVotedOn = []
                        if currVote.accepted.length != currMission.numReq
                            for p in game.players
                                hasBeenVotedOn = false
                                for vo in votedOn
                                    if p.id.equals(vo)
                                        hasBeenVotedOn = true

                                if not hasBeenVotedOn
                                    notVotedOn.push p.id

                        game.votes.push
                            mission  : currVote.mission
                            team     : currVote.accepted.concat(notVotedOn)
                            accepted : currVote.accepted
                            rejected : currVote.rejected
                            votes    : currVote.votes
                        game.state = GAME_QUEST
                        game.currentLeader = game.finalLeader
                        game.set_next_leader(true)
                    else
                        game.state = GAME_PTRC_PROPOSE
                        game.set_next_leader(false)

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
