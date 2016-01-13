Array::sum = () ->
    @reduce (x, y) -> x + y

VERSION = 1

jQuery ->
    #Socket.io stuff
    query = ""
    if $.cookie('player_id')
        query = "?player_id=" + $.cookie('player_id')

    socket = io.connect('http://' + IP + ":" + PORT + query, {'transports': ['websocket', 'htmlfile', 'xhr-polling', 'jsonp-polling']})

    socket.on 'connect', (data) ->
        $("#disconnected").hide()
        $("#stale_version").hide()

        if not $.cookie('player_id')
            $("#signin").show()

    socket.on 'disconnect', () ->
        $("#signin").hide()
        $("#lobby").hide()
        $("#pregame").hide()
        $("#game").hide()
        $("#stale_version").hide()
        $("#disconnected").show()

    GAME_LOBBY         = 0
    GAME_PREGAME       = 1
    GAME_CLUE          = 2
    GAME_VOTE          = 3
    GAME_FINISHED      = 9
    
    TEAM_RED           = 0
    TEAM_BLUE          = 1
    
    WORD_RED           = 0
    WORD_BLUE          = 1
    WORD_GREY          = 2
    WORD_BLACK         = 3

    socket.on 'player_id', (player_id) ->
        $.cookie('player_id', player_id, {expires: 365})
        $("#login").hide()

    socket.on 'previous_game', () ->
        $("#btn_reconnect").show()

    socket.on 'bad_login', () ->
        $("#signin").show()
        #$.removeCookie('player_id')
        
    socket.on 'reconnectlist', (games) ->
        $("#login").show()
        for g in games
            do (g) ->
                join_btn = $('<a>')
                    .addClass("list-group-item")
                    .text(g.name)
                    .append($('<span>').addClass("pull-right").text(g.num_players))
                    .click () ->
                        socket.emit 'reconnectuser', { game_id : g.id, player_id : g.player }
                        $("#reconnectlist").hide()
                        $("#reconnectmessage").text("Waiting for approval to reconnect")
                        $("#reconnectmessage").show()

                $("#reconnectlist").append(join_btn)
            $("#reconnectmessage").text("")
            $("#reconnectmessage").hide()
            $("#reconnectlist").show()

    socket.on 'reconnectdenied', () ->
        $("#reconnectmessage").text("You were rejected")


    socket.on 'gamelist', (data) ->
        if data.version != VERSION
            $("#signin").hide()
            $("#lobby").hide()
            $("#pregame").hide()
            $("#game").hide()
            $("#disconnected").hide()
            $("#stale_version").show()
            return
        $("#stale_version").hide()

        return if $("#pregame").is(":visible")
        return if $("#game").is(":visible")

        $("#lobby").show()
        $("#gamelist").empty()
        for g in data.gamelist
            do (g) ->
                join_btn = $('<a>')
                    .addClass("list-group-item")
                    .text(g.name)
                    .append($('<span>').addClass("pull-right").text(g.num_players))
                    .click () ->
                        socket.emit 'joingame', { game_id : g.id }

                $("#gamelist").append(join_btn)

    socket.on 'kicked', () ->
        $("#pregame").hide()
        $("#game").hide()

    socket.on 'gameinfo', (game) ->
        if game.version != VERSION
            $("#signin").hide()
            $("#lobby").hide()
            $("#pregame").hide()
            $("#game").hide()
            $("#disconnected").hide()
            $("#stale_version").show()
            return
        $("#stale_version").hide()

        $("#lobby").hide()

        if game.state == GAME_LOBBY
            $("#pregame").show()
            $("#gameinfo").empty()
            $("#btn_start_game").hide()
            $("#gameoptions").hide()
            $("#hiddeninfo").hide()

            ishost = false
            for p, i in game.players
                
                li = $('<li>')
                    .addClass("list-group-item")
                    .text(p.name)

                if ishost then do (p) ->
                    kick_btn = $("<button>")
                        .addClass("pull-right")
                        .addClass("btn")
                        .addClass("btn-danger")
                        .addClass("btn-xs")
                        .text("Kick")
                        .on 'click', (e) ->
                            socket.emit('kick', p.id)

                    li.append(kick_btn)

                if game.me.id == p.id && i == 0
                    ishost = true

                $("#gameinfo").append li

            if ishost
                $("#btn_ready").show()
            else
                $("#btn_ready").hide()

            window.have_game_info = false

        else if game.state == GAME_FINISHED
            socket.emit 'leavegame'
            window.location = '/game?id=' + game.id
        
        else if game.state == GAME_PREGAME
            $("#pregame").show()
            $("#btn_ready").hide()
            $("#btn_leavelobby").hide()
            $("#btn_start_game").hide()
            $("#gameoptions").hide()

            if window.have_game_info == true
                return

            $("#gameinfo").empty()

            ishost = false
            red_spy = undefined
            blue_spy = undefined
            update = ->
                $("#gameinfo li").each () ->
                    $(this).removeClass("redteam")
                        .removeClass("blueteam")
                        .find("input").attr("spy", "")
                $("#player" + red_spy)
                    .addClass("redteam")
                    .find("input").attr("spy", "red")
                $("#player" + blue_spy)
                    .addClass("blueteam")
                    .find("input").attr("spy", "blue")

            for p, i in game.players
                if game.me.id == p.id && i == 0
                    ishost = true

                player_id = $("<input>")
                    .attr("type", "hidden")
                    .attr("value", p.id)
                
                li = $('<li>')
                    .addClass("list-group-item")
                    .text(p.name)
                    .attr("id", "player" + i)
                    .append(player_id)


                if ishost then do (i) ->
                    red_btn = $("<button>")
                        .addClass("pull-right")
                        .addClass("btn")
                        .addClass("btn-danger")
                        .addClass("btn-xs")
                        .text("Red")
                        .on 'click', (e) ->
                            if i == blue_spy
                                blue_spy = undefined
                            red_spy = i
                            update()

                    blue_btn = $("<button>")
                        .addClass("pull-right")
                        .addClass("btn")
                        .addClass("btn-danger")
                        .addClass("btn-xs")
                        .text("Blue")
                        .on 'click', (e) ->
                            if i == red_spy
                                red_spy = undefined
                            blue_spy = i
                            update()

                    li.append(red_btn)
                    li.append(blue_btn)
                
                $("#gameinfo").append li
                if ishost
                    $("#btn_start_game").show()
                    $("#gameoptions").show()
                    $("#gameinfo").sortable
                        items : "li:not(:first)"

            if not ishost
                $("#waitforhost").show()

            window.have_game_info = true

        else
            $("#pregame").hide()
            $("#game").show()

            #Draw the list of players
             
            for p in game.players
                if p.id == game.me.id
                    me = p
            
            $("#players").empty().addClass("wordlist")
            for w in game.words
                li = $("<li>")
                    .addClass("list-group-item")
                    .addClass("wordlist")
                    .text(w.word)

                if w.guessed
                    li.addClass("guessed")

                if me.spy || w.guessed
                    if w.kind == WORD_RED
                        li.addClass("redteam")
                    else if w.kind == WORD_BLUE
                        li.addClass("blueteam")
                    else if w.kind == WORD_GREY
                        li.addClass("noteam")
                    else if w.kind == WORD_BLACK
                        li.addClass("blackteam")

                #Make players selectable for the leader (to propose quest)
                if game.currentTeam == me.team && me.spy

                    li.on 'click', (e) ->
                        select_for_guess($(e.target))
                    input = $("<input>").attr
                        type    : 'hidden'
                        word    : w.word
                        value   : 0
                    li.append(input)

                $("#players").append(li)

            #Make quest proposal button visible to leader
            if (game.state == GAME_VOTE || game.state == GAME_CLUE) &&
               game.currentTeam == me.team && me.spy
                $("#btn_select_guess").show()
                $("#leaderinfo").show()
                if me.team == TEAM_RED
                    teamstr = "Red"
                else if me.team == TEAM_BLUE
                    teamstr = "Blue"
                $("#leaderinfo").html("You are the " + teamstr + " leader, select a word from the list then press this button.")
            else
                $("#btn_select_guess").hide()
                $("#leaderinfo").hide()

            #If someone is trying to reconnect show vote
            if game.reconnect_user && game.reconnect_user != ""
                if game.reconnect_vote[me.order] == 0
                    $("#user_reconnecting_name").text(game.reconnect_user)
                    $("#user_reconnecting").show()
            else
                $("#user_reconnecting").hide()
                $("#user_reconnecting .btn").each () ->
                    $(this).removeClass("active")

    #Regular jquery stuff
    
    $("#form-signin").on 'submit', (e) ->
        if $("#playername").val().length > 0
            socket.emit('login', {name: $("#playername").val()})
            $("#signin").hide()
        e.preventDefault()

    $("#btn_newgame").on 'click', () ->
        socket.emit 'newgame'

    $("#btn_changename").on 'click', () ->
        $("#signin").show()

    $("#btn_reconnect").on 'click', () ->
        socket.emit 'reconnecttogame'

    $("#btn_ready").on 'click', () ->
        socket.emit('ready')

    $("#btn_start_game").on 'click', () ->
        players = $("#gameinfo").sortable("toArray")
        players.unshift($("#gameinfo li").attr("id"))
        sorted = {}

        for p, i in players
            input = $("#" + p + " input")[0]
            player_id = $(input).attr("value")
            spy = $(input).attr("spy")
            if spy == "red"
                red_id = player_id
            else if spy == "blue"
                blue_id = player_id
            sorted[player_id] = i + 1

        options = {}
        if red_id && blue_id 
            socket.emit('startgame', {order: sorted, options: options, red_id: red_id, blue_id: blue_id})
        else
            return


    $("#form-select-guess").on 'submit', (e) ->
        e.preventDefault()
        guess = undefined
        sel = undefined
        $("#players li").each () ->
            input = $($(this).children(":input")[0])
            if input.val() == '1'
                guess = input.attr('word')
                sel = $(this)

        if guess
            $("#btn_select_guess").hide()
            sel.removeClass('active')
            socket.emit('make_guess', guess)
        else
            $("#leaderinfo").html("You must make a guess!")

    $("#btn_submitvote").on 'click', (e) ->
        radio = $("input[name=vote]:checked").val()
        return if radio != "approve" && radio != "reject"
        vote = (radio == "approve")
        $("input[name=vote]:checked").prop('checked', false)
        $("#vote .btn").each () ->
            $(this).removeClass("active")
        $("#vote").hide()
        socket.emit('vote', vote)

    $("#btn_quit").on 'click', (e) ->
        $("#game").hide()
        $("#btn_reconnect").show()
        socket.emit 'leavegame'

    $("#btn_leavelobby").on 'click', (e) ->
        $("#pregame").hide()
        socket.emit 'leavegame'

    $("#btn_submitreconnectvote").on 'click', (e) ->
        radio = $("input[name=reconnectvote]:checked").val()
        return if radio != "allow" && radio != "deny"
        rvote = (radio == "allow")
        $("input[name=reconnectvote]:checked").prop('checked', false)
        $("#user_reconnecting .btn").each () ->
            $(this).removeClass("active")
        $("#user_reconnecting").hide()
        socket.emit('reconnect_vote', rvote)

    $("#btn_noreconnect").on 'click', (e) ->
        socket.emit('noreconnect', {name: $("#playername").val()})
        $("#login").hide()


select_for_guess = (li) ->

        $("#players li").each () ->
            input = $($(this).children(":input")[0])
            $(this).removeClass("active")
            input.attr(value: 0)

        input = $(li.children(":input")[0])
        li.addClass("active")
        input.attr(value: 1)
