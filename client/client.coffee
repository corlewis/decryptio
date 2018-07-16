Array::sum = () ->
    @reduce (x, y) -> x + y

VERSION = 1
timer_handle = undefined
can_end_turn = false

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

team_to_str = (team) ->
    if team == TEAM_RED
        teamstr = "Red"
    else if team == TEAM_BLUE
        teamstr = "Blue"

jQuery ->
    
    shuffle = (a) ->
        for i in [a.length-1..1]
            j = Math.floor Math.random() * (i + 1)
            [a[i], a[j]] = [a[j], a[i]]
        return a

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

    socket.on 'player_id', (player_id) ->
        $.cookie('player_id', player_id, {expires: 365})
        $("#login").hide()

    socket.on 'previous_game', () ->
        $("#btn_reconnect").show()

    socket.on 'bad_login', () ->
        $("#signin").show()
        $("#lobby").hide()
        $("#game").hide()
        $("#reconnectlist").hide()
        #$.removeCookie('player_id')
        
    socket.on 'reconnectlist', (games) ->
        $("#login").show()
        $("#lobby").hide()
        $("#game").hide()
        $("#disconnected").hide()
        $("#reconnectlist").empty()
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
        return if $("#reconnectlist").is(":visible")

        $("#lobby").show()
        $("#newgamelist").empty()
        $("#newgameheader").hide()
        $("#oldgamelobby").hide()
        $("#oldgamelist").empty()
        for g in data.gamelist
            do (g) ->
                join_btn = $('<a>')
                    .addClass("list-group-item")
                    .text(g.name)
                    .append($('<span>').addClass("pull-right").text(g.num_players))
                    .click () ->
                        socket.emit 'joingame', { game_id : g.id }
                if g.state == GAME_LOBBY
                    $("#newgamelist").append(join_btn)
                else
                    $("#newgameheader").show()
                    $("#oldgamelobby").show()
                    $("#oldgamelist").append(join_btn)

    socket.on 'kicked', () ->
        $("#pregame").hide()
        $("#game").hide()

    socket.on 'timeleft', (data) ->
        timeleft = data.timeleft
        neg = ""
        if timeleft < 0
            minutes = Math.ceil (timeleft / 60)
            seconds = timeleft - minutes * 60
            neg = "-"
            minutes *= -1
            seconds *= -1
        else
            minutes = Math.floor (timeleft / 60)
            seconds = timeleft - minutes * 60

        if seconds < 10
            seconds = "0" + seconds

        $("#timeleft").text("Time left: " + neg + minutes + ":" + seconds)
        if can_end_turn && timeleft < 0
            $("#btn_force_end").show()

    socket.on 'teaminfo', (game) ->
       if game.state != GAME_PREGAME
           return
   
       players = $("#gameinfo li")
       
       for p, i in game.players
            if game.me.id == p.id && i == 0
                return
            
            $(players[i]).removeClass("blueteam").removeClass("redteam")
            if p.team == TEAM_RED
                $(players[i]).addClass("redteam")
            else if p.team == TEAM_BLUE
                $(players[i]).addClass("blueteam")


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
        $("#btn_randomize_spies").hide()
        $("#btn_randomize_teams").hide()
        $("#btn_force_end").hide()

        $("#lobby").hide()
        $("#timeleft").hide()

        if game.state == GAME_LOBBY

            if timer_handle
               clearInterval(timer_handle) 
               timer_handle = undefined

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
            update = ->
                $("#gameinfo li").each () ->
                    $(this).removeClass("redteam")
                        .removeClass("blueteam")
                        .find("input").attr("spy", "")

            set_team = (li,team) ->
                if team == TEAM_RED
                    li.removeClass("blueteam").addClass("redteam")
                else if team == TEAM_BLUE
                    li.removeClass("redteam").addClass("blueteam")
                li.find("input").attr("team",team)

            emit_teams = () ->
                teams = {}
                players = $("#gameinfo li").each () ->
                    input = $(this).find("input")
                    player_id = input.attr("value")
                    team = parseInt(input.attr("team"),10)

                    teams[player_id] = 
                        team : team

                socket.emit('teaminfo', teams)
                        

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


                if ishost then do (li, player_id) ->
                    red_btn = $("<button>")
                        .addClass("pull-right")
                        .addClass("btn")
                        .addClass("btn-danger")
                        .addClass("btn-xs")
                        .text("Red")
                        .on 'click', (e) ->
                            set_team(li, TEAM_RED)
                            emit_teams()

                    blue_btn = $("<button>")
                        .addClass("pull-right")
                        .addClass("btn")
                        .addClass("btn-danger")
                        .addClass("btn-xs")
                        .text("Blue")
                        .on 'click', (e) ->
                            set_team(li, TEAM_BLUE)
                            emit_teams()

                    li.append(red_btn)
                    li.append(blue_btn)
                
                $("#gameinfo").append li
            if ishost
                select = '<option value=0>No Limit</option>'
                for i in [1..10]
                    secs = i * 30
                    select += '<option value=' + secs + '>' + secs + ' Seconds </option>'
 
                $("#opt_encrypt_timelimit").html(select)
                $('#opt_encrypt_timelimit option[value="0"]').attr("selected", "selected");

                $("#opt_decrypt_timelimit").html(select)
                $('#opt_decrypt_timelimit option[value="0"]').attr("selected", "selected");
     
                select = ''
                for i in [1..8]
                    select += '<option value=' + i + '>' + i + '</option>'
                $("#opt_num_words").html(select)
                $('#opt_num_words option[value="4"]').attr("selected", "selected");

                $("#opt_code_length").html(select)
                $('#opt_code_length option[value="3"]').attr("selected", "selected");

                select = '<option value=' + DEFAULT_WORDS + '>Default Words</option>'
                select += '<option value=' + DUET_WORDS + '>Duet Words</option>'
                select += '<option value=' + ALL_WORDS + '>All Words</option>'

                $("#opt_word_set").html(select)
                $('#opt_word_set option[value=' + ALL_WORDS + ']').attr("selected", "selected");
                players = $("#gameinfo li")
                
                $("#btn_randomize_teams").show()
                    .on 'click', (e) ->
                        $.each shuffle(players), (i, p) ->
                            jitter = Math.floor(Math.random() * 2)
                            middle = (players.length - jitter) / 2
                            if i < middle
                                set_team($(this), TEAM_RED)
                            else if i >= middle
                                set_team($(this), TEAM_BLUE)
                        emit_teams()
    
                $("#btn_start_game").show()
                $("#gameoptions").show()

            else
                $("#waitforhost").show()

            window.have_game_info = true

        else
            $("#pregame").hide()
            $("#game").show()
             
            for p in game.players
                if p.id == game.me.id
                    me = p

            m = game.messages[game.messages.length - 1]
            if game.state == GAME_ENCRYPT
                can_end_turn = game.timeLimit > 0 && m[me.team].message.finished &&
                         not m[other_team me.team].message.finished
            else if game.state == GAME_DECRYPT_RED
                can_end_turn = game.timeLimit > 0 && m[TEAM_RED]["guess"+me.team].finished &&
                         not m[TEAM_RED]["guess"+other_team me.team].finished
            else if game.state == GAME_DECRYPT_BLUE
                can_end_turn = game.timeLimit > 0 && m[TEAM_BLUE]["guess"+me.team].finished &&
                         not m[TEAM_BLUE]["guess"+other_team me.team].finished
 
            if not timer_handle && game.timeLimit > 0
               timer_handle = setInterval ->
                   socket.emit 'timeleft'
                 , 500
            if not (game.timeLimit > 0) && timer_handle
                clearInterval(timer_handle)
                timer_handle = undefined

            #Draw the scores
            $("#red_results").empty()
                             .html("&#x2714: " + game.score[TEAM_RED].intercepts + "/2 " +
                                   "&#x2718: " + game.score[TEAM_RED].miscommunications + "/2")
            $("#blue_results").empty()
                             .html("&#x2714: " + game.score[TEAM_BLUE].intercepts + "/2 " +
                                   "&#x2718: " + game.score[TEAM_RED].miscommunications + "/2")

            #Draw the list of keywords
            $("#keywords").empty().addClass("wordlist")
            for w, i in game.keywords
                li = $("<li>")
                    .addClass("list-group-item")
                    .addClass("wordlist")
                    .text((i+1) + ": " + w)

                $("#keywords").append(li)

            $("#clues").empty()

            #Draw the list of messages
            # for m, index in game.messages.reverse()
            #     guesses = $("<ul>")
            #         .attr("id", "guesses" + index)
            #         .addClass("list-group")
            #     for g in c.guesses
            #         li = $("<li>")
            #             .addClass("list-group-item guessed")
            #             .text(g.word)
            #             .append($('<span>').text(g.player)
            #                                .addClass("pull-right " + team_to_class(c.team)))
            #         li.addClass(kind_to_class(g.kind))

            #         guesses.append(li)

            #     li = $("<li>")
            #         .attr("id", index)
            #         .addClass("list-group-item")
            #         .text(c.word)
            #         .prepend($('<span>').addClass("caret-right").html("&#9658"))
            #         .prepend($('<span>').addClass("caret-down").html("&#9660").css({"display": "none"}))
            #         .append($('<span>').addClass("pull-right").text(c.numWords))
            #         .append(guesses)
            #     li.addClass(team_to_class(c.team))
            #     li.on 'click', (e) ->
            #         $("#guesses" + $(e.currentTarget).attr("id")).toggle()
            #         $('.caret-right', $(e.currentTarget)).toggle()
            #         $('.caret-down', $(e.currentTarget)).toggle()

            #     $("#clues").append(li)
            #     $("#guesses" + index).hide()

            #Make quest proposal button visible to leader
            $("#teaminfo").show()
            $("#team_form").show()

            teamstr = team_to_str me.team

            if me.spy
                $("#team_form").hide()
                $("#form-give-clue").show()
            else
                $("#form-give-clue").hide()

            if game.timeLimit > 0
                $("#timeleft").show()
            else 
                $("#timeleft").hide()

            if (game.state == GAME_DECRYPT_RED || game.state == GAME_DECRYPT_BLUE)
                state_team = game.state - GAME_DECRYPT_RED
                state_teamstr = team_to_str state_team
                if not me.spy
                    select = ''
                    for i in [1..game.options.num_words]
                        select += '<option value=' + i + '>' + i + '</option>'
                    $("#guess_code1").html(select)
                    $('#guess_code1 option[value="0"]').attr("selected", "selected");
                    $("#guess_code2").html(select)
                    $('#guess_code2 option[value="0"]').attr("selected", "selected");
                    $("#guess_code3").html(select)
                    $('#guess_code3 option[value="0"]').attr("selected", "selected");

                    if m[state_team]["guess"+me.team].finished
                        $("#btn_select_guess").hide()
                        $("#guess_code").hide()
                        $("#teaminfo").html("You are on team " + teamstr +
                                               ". Waiting for the other team to guess the " +
                                               state_teamstr + " code.")
                    else
                        $("#btn_select_guess").show()
                        $("#guess_code").show()
                        $("#teaminfo").html("You are on team " + teamstr + ". Try to guess the " +
                                                state_teamstr + " code.")
                else
                    $("#btn_give_clue").hide()
                    $("#clue_entry").hide()
                    if not m[state_team]["guess"+me.team].finished &&
                       not m[state_team]["guess"+other_team me.team].finished
                        $("#spyinfo").html("You are the " + teamstr +
                                               " spy. Waiting for teams to guess the " +
                                               state_teamstr + " code.")
                    else if not m[state_team]["guess"+me.team].finished
                        $("#spyinfo").html("You are the " + teamstr +
                                               " spy. Waiting for your team to guess the " +
                                               state_teamstr + " code.")
                    else if not m[state_team]["guess"+other_team me.team].finished
                        $("#spyinfo").html("You are the " + teamstr +
                                               " spy. Waiting for their team to guess the " +
                                               state_teamstr + " code.")

            if (game.state == GAME_ENCRYPT)
                if me.spy
                    $("#btn_give_clue").show()
                    $("#clue_entry").show()
                    if not m[me.team].message.finished
                        $("#spyinfo").html("You are the " + teamstr + " leader. Enter your clues.\n The code you are encrypting is " + game.current_code)
                    else if not m[other_team me.team].message.finished
                        $("#btn_give_clue").hide()
                        $("#clue_entry").hide()
                        $("#spyinfo").html("You are the " + teamstr +
                                           " leader. Waiting for the other spy.")
                else
                    $("#btn_select_guess").hide()
                    $("guess_code").hide()
                    $("guess_code1").hide()
                    $("guess_code2").hide()
                    $("guess_code3").hide()
                    $("#teaminfo").html("You are on team " + teamstr + ". Waiting for the clues.")

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
        players = $("#gameinfo li")
        sorted = {}
        teams = {}
        red_team = 0
        blue_team = 0
        for p, i in players
            input = $("#" + p.id + " input")[0]
            player_id = $(input).attr("value")
            team = parseInt($(input).attr("team"),10)
            entry =
                team : team
            if team == TEAM_RED
                red_team += 1
            else if team == TEAM_BLUE
                blue_team +=1
            teams[player_id] = entry
#            sorted[player_id] = i
#FIXME        is_coop = (red_spies == 1) && red_team == players.length
        is_coop = false
        options = {}
        options['num_words'] = $("#opt_num_words").val()
        options['code_length'] = $("#opt_code_length").val()
        options['encrypt_time_limit'] = $("#opt_encrypt_timelimit").val()
        options['decrypt_time_limit'] = $("#opt_decrypt_timelimit").val()
        options['word_set'] = $("#opt_word_set").val()
        console.log('options', options)

        if (red_team > 1 && blue_team > 1 && (red_team + blue_team == players.length))
            socket.emit('startgame', {options: options, teams : teams, is_coop: is_coop})
        else
            return
    $("#form-give-clue").on 'submit', (e) ->
        e.preventDefault()
        words = []
        for i in [1..3]#game.options.code_length]
            word = $("#clue_entry" + i).val()
            words.push word
            console.log(word)
        console.log(words)
        console.log(words.slice())

        clue =
            clues : words.slice()

        if words.length = 3 && words.every((x) -> x.length > 0)
            $("#clue_entry").hide()
            socket.emit('give_clue', clue)
        else
            $("#spyinfo").html("You must give valid clues!")

    $("#form-select-guess").on 'submit', (e) ->
        e.preventDefault()
        code = []
        for i in [1..3]#game.options.code_length]
            word = $("#guess_code" + i).val()
            code.push word
            console.log(word)
        console.log(code)

        guess =
            code : code.slice()

        if code.length = 3 && code.every((x) -> x > 0)
            $("#guess_code").hide()
            socket.emit('make_guess', guess)
        else
            $("#leaderinfo").html("You must make a guess!")

    $("#btn_force_end").on 'click', (e) ->
        $("#btn_force_end").hide()
        socket.emit 'force_end'

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

kind_to_class = (kind) ->
        if kind == WORD_RED
            "redteam"
        else if kind == WORD_BLUE
            "blueteam"
        else if kind == WORD_GREY
            "noteam"

team_to_class = (team) ->
        kind_to_class(team)
