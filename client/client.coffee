Array::sum = () ->
    @reduce (x, y) -> x + y

VERSION = 3
timer_handle = undefined
can_end_turn = false
force_end_state = GAME_LOBBY
time_limit = 0
code_length = 3
num_words = 4

GAME_LOBBY         = 0
GAME_PREGAME       = 1
GAME_ENCRYPT       = 2
GAME_DECRYPT_RED   = 3
GAME_DECRYPT_BLUE  = 4
GAME_PRE_FINISHED  = 8
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

        if time_limit > 0
            $("#timeleft").text("Time left: " + neg + minutes + ":" + seconds)
        if can_end_turn && timeleft < 0
            $("#force_end").show()

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
        $("#force_end").hide()
        $("#force_end_confirm").hide()

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

            set_spy = (li,is_spy) ->
               if is_spy
                   li.addClass("spy")
                   li.find("input").attr("spy","true")
               else
                   li.removeClass("spy")
                   li.find("input").attr("spy","false")

            emit_teams = () ->
                teams = {}
                players = $("#gameinfo li").each () ->
                    input = $(this).find("input")
                    player_id = input.attr("value")
                    team = parseInt(input.attr("team"),10)
                    spy = input.attr("spy") == "true"

                    teams[player_id] = 
                        team : team
                        spy : spy

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
                    li.on 'click', (e) ->
                         if not (li.is(e.target))
                             return
                         if player_id.attr("spy") == "true"
                             set_spy(li, false)
                         else
                             spies = 0
                             $("#gameinfo li").each () ->
                                 if $(this).find("input").attr("spy") == "true"
                                     spies += 1
                             if spies < 2
                                 set_spy(li, true)
                         emit_teams()

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
                $('#opt_encrypt_timelimit option[value="60"]').attr("selected", "selected");

                $("#opt_decrypt_timelimit").html(select)
                $('#opt_decrypt_timelimit option[value="60"]').attr("selected", "selected");
     
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
            force_end_state = game.state
            time_limit = game.timeLimit
            code_length = game.options.code_length
            num_words = game.options.num_words
            can_end_turn = game.timeLimit > 0 && me.team != TEAM_NONE
            if game.state == GAME_ENCRYPT
                can_end_turn = can_end_turn && m[me.team].message.finished &&
                         not m[other_team me.team].message.finished
            else if game.state == GAME_DECRYPT_RED
                can_end_turn = can_end_turn && m[TEAM_RED]["guess"+me.team].finished &&
                         not m[TEAM_RED]["guess"+other_team me.team].finished
            else if game.state == GAME_DECRYPT_BLUE
                can_end_turn = can_end_turn && m[TEAM_BLUE]["guess"+me.team].finished &&
                         not m[TEAM_BLUE]["guess"+other_team me.team].finished
            else if game.state == GAME_PRE_FINISHED
                can_end_turn = can_end_turn && game.tiedFinish[me.team]
 
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
                                   "&#x2718: " + game.score[TEAM_BLUE].miscommunications + "/2")

            if game.state == GAME_ENCRYPT
                cur_team = if me.team == TEAM_NONE then TEAM_RED else me.team
            else if game.state == GAME_PRE_FINISHED
                cur_team = if me.team == TEAM_NONE then TEAM_RED else other_team me.team
            else
                cur_team = game.state - GAME_DECRYPT_RED
            for i in TEAMS
                if i == cur_team
                    id_sfx = "_cur"
                else
                    id_sfx = "_other"
                #Draw the list of messages
                $("#clues" + id_sfx).empty()
                first = true
                for list_m, round_index in game.messages.slice().reverse()
                    round = game.messages.length - round_index
                    both_codes = game.codes[round - 1]
                    if list_m[i].message.finished && list_m[other_team i].message.finished
                        clues = $("<ul>")
                            .addClass("list-group clues")
                        for clue, clue_index in list_m[i].message.clues
                            li = $("<li>")
                                .addClass("list-group-item clearfix")
                                .append($('<span>')
                                    .css('width', '70%').css('float', 'left')
                                    .text(clue))
                            if list_m[i].guess0.finished && list_m[i].guess1.finished
                                li.append($('<span>').addClass("pull-right")
                                      .append($('<span>')
                                          .addClass(team_to_class(TEAM_RED))
                                          .append(guess_to_str(list_m[i].guess0.code[clue_index])))
                                      .append($('<span>').addClass("noteam")
                                          .append("&nbsp;|&nbsp;"))
                                      .append($('<span>')
                                          .addClass(team_to_class(TEAM_BLUE))
                                          .append(guess_to_str(list_m[i].guess1.code[clue_index])))
                                      .append($('<span>').addClass("noteam")
                                          .append("&nbsp;|&nbsp;"))
                                      .append($('<span>').addClass("noteam")
                                          .text(both_codes[i][clue_index])))
                            clues.append(li)

                        li = $("<li>")
                            .addClass("list-group-item " + team_to_class(i))
                            .text("Round " + round + ": " + list_m[i].spy)
                            .prepend($('<span>').addClass("caret-right").html("&#9658"))
                            .prepend($('<span>').addClass("caret-down").html("&#9660").css({"display": "none"}))
                            .append(clues.hide())
                        if first
                            li.attr("id", "clues0" + id_sfx)
                            first = false
                        li.on 'click', (e) -> toggle_list('clues', $(e.currentTarget))
                        $("#clues" + id_sfx).append(li)

                #Draw given clues for each keyword
                if not $("#used_clues" + id_sfx).hasClass("has-options" + game.state)
                    $("#used_clues" + id_sfx).empty()
                    words = $("<ul>")
                        .attr("id", "used_clues_list" + id_sfx)
                        .addClass("list-group words")
                    for keyword in [1..game.options.num_words]
                        word_clues = $("<ul>").addClass("list-group wordlist")
                        for code, round in game.codes
                            for keyword2, code_index in code[i]
                                clue = game.messages[round][i].message.clues[code_index]
                                if keyword == keyword2 && clue != "<Turn Timeout>"
                                    li = $("<li>")
                                        .addClass("list-group-item wordlist")
                                        .text(clue)
                                    word_clues.append(li)

                        li = $("<li>")
                            .addClass("list-group-item")
                            .attr('id', 'used_clues_cur' + keyword)
                            .text("Keyword " + keyword + ": ")
                        if i == me.team
                            li.append($('<span>').text(game.keywords[keyword - 1]))
                        li.append(word_clues)
                        words.append(li)

                    li = $("<li>")
                        .addClass("list-group-item " + team_to_class(i))
                        .text(team_to_str(i) + " team's clues")
                        .append(words)
                    $("#used_clues" + id_sfx).append(li)

            if me.team == TEAM_NONE
                teamstr = "You are spectating."
            else
                teamstr = "You are on team " + (team_to_str me.team) + "."
            spystr = "You are the " + (team_to_str me.team) + " spy."
            $("#form-select-guess").hide()
            $("#form-give-clue").hide()
            $("#form-guess-words").hide()
            $("#current_clues").hide()
            if game.timeLimit > 0
                $("#timeleft").show()
            else 
                $("#timeleft").hide()
            toggle_list('clues', "#clues0_cur")
            toggle_list('clues', "#clues0_other")

            if (game.state == GAME_DECRYPT_RED || game.state == GAME_DECRYPT_BLUE)
                toggle_list('clues', "#clues0_cur")
                $("#used_clues_cur").removeClass("has-options" + GAME_ENCRYPT)
                state_team = game.state - GAME_DECRYPT_RED
                state_teamstr = team_to_str state_team
                state_teamstr_span = $('<span>')
                    .addClass(team_to_class(state_team)).text(state_teamstr + " code")
                #Draw the current clues
                $("#current_clues").show()
                if not $("#current_clues").hasClass("drawn" + state_team)
                    $("#current_clues").empty()
                    for clue, clue_index in m[state_team].message.clues
                        li = $("<li>")
                            .attr('id', 'curruent_clue' + (clue_index + 1))
                            .addClass("list-group-item clearfix " + team_to_class(state_team))
                            .append($('<span>').addClass("cluelist").text(clue))
                            $("#current_clues").append(li)
                    if not (me.spy && me.team == state_team)
                        select = ''
                        for i in [1..game.options.num_words]
                            select += '<option value=' + i + '>' + i + '</option>'
                        for i in [1..code_length]
                            li = ($('<select>').attr('id', 'guess_code' + i)
                                .addClass("pull-right guess_code").html(select))
                            $("#curruent_clue" + i).append(li)
                    $("#current_clues").addClass("drawn" + state_team)

                if not (me.spy && me.team == state_team)
                    if me.team == TEAM_NONE
                        $(".guess_code", "#current_clues").hide()
                        $("#form-select-guess").hide()
                        $("#gamemessage").html(teamstr + " The ")
                                        .append(state_teamstr_span)
                                        .append(" is being guessed.")
                    else if m[state_team]["guess"+me.team].finished
                        $(".guess_code", "#current_clues").hide()
                        $("#form-select-guess").hide()
                        $("#gamemessage").html(teamstr +
                                               " Waiting for the other team to guess the ")
                                        .append(state_teamstr_span).append(".")
                    else
                        $("#form-select-guess").show()
                        $("#gamemessage").html(teamstr + " Try to guess the ")
                                        .append(state_teamstr_span).append(".")
                else
                    if not m[state_team]["guess"+me.team].finished &&
                       not m[state_team]["guess"+other_team me.team].finished
                        teams_message = "both teams"
                    else if not m[state_team]["guess"+me.team].finished
                        teams_message = "your team"
                    else if not m[state_team]["guess"+other_team me.team].finished
                        teams_message = "their team"
                    $("#gamemessage").html(spystr +
                                           " Waiting for " + teams_message + " to guess the ")
                                     .append(state_teamstr_span).append(".")

            if (game.state == GAME_ENCRYPT)
                $("#current_clues").removeClass("drawn0 drawn1")
                if me.spy
                    if not m[me.team].message.finished
                        $("#form-give-clue").show()
                        if not $("#used_clues_cur").hasClass("has-options" + game.state)
                            $(".clue-entry", "#used_clues_cur").empty()
                            for code, code_idx in game.current_code
                                li = ($('<input>').attr('id', 'clue_entry' + (code_idx + 1))
                                    .attr('type', 'text').addClass("form-control clue-entry")
                                    .attr('maxlength', 60)
                                    .attr('placeholder', 'Clue ' + (code_idx + 1))
                                    .html(select))
                                $("#used_clues_cur" + code).append(li)
                            $("#used_clues_cur").addClass("has-options" + game.state)
                        $("#clue_entry1").focus()
                        $("#clue_entry1").prop('autofocus')
                        $("#gamemessage").html(spystr + " Enter your clues.\n The code you are encrypting is " + game.current_code)
                    else if not m[other_team me.team].message.finished
                        $("#gamemessage").html(spystr + " Waiting for the other spy.")
                else
                    $("#gamemessage").html(teamstr + " Waiting for the clues.")

            if game.state == GAME_PRE_FINISHED
                $("#gamemessage").html(teamstr + "<br />")
                if game.winningTeam == TEAM_NONE
                    $("#gamemessage").append("Teams are tied! The team that can best guess their opponents keywords wins!")
                else
                    if game.winningTeam == TEAM_RED
                        winstr = $('<span>').addClass("redteam")
                            .append("Game Over. Red team wins!")
                    else
                        winstr = $('<span>').addClass("blueteam")
                           .text("Game Over. Blue team wins!")
                    $("#gamemessage").append(winstr)
                        .append("<br />Both teams can now guess the opponents keywords.")
                if me.team != TEAM_NONE && not game.tiedFinish[me.team]
                    $("#form-guess-words").show()
                    if not $("#used_clues_cur").hasClass("has-options" + game.state)
                        $(".clue-entry", "#used_clues_cur").empty()
                        for i in [1..num_words]
                            li = ($('<input>').attr('id', 'words_entry' + i)
                                .attr('type', 'text').addClass("form-control clue-entry")
                                .attr('maxlength', 60)
                                .attr('placeholder', 'Keyword ' + i)
                                .html(select))
                            $("#used_clues_cur" + i).append(li)
                        $("#used_clues_cur").addClass("has-options" + game.state)
                    $("#words_entry1").focus()
                    $("#words_entry1").prop('autofocus')
                else
                    $(".clue-entry", "#used_clues_cur").hide()

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
            spy = $(input).attr("spy") == "true"
            team = parseInt($(input).attr("team"),10)
            entry =
                spy : spy
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
        for i in [1..code_length]
            word = $("#clue_entry" + i).val()
            words.push word

        clue =
            clues : words.slice()

        if words.length == code_length && words.every((x) -> x.length > 0) &&
           words.every((x) -> is_ascii(x))
            $("#form-give-clue").hide()
            $("#warning").empty()
            $(".clue-entry", "#used_clues_cur").hide()
            socket.emit('give_clue', clue)
        else
            $("#warning").html("You must give valid clues!")

    $("#form-select-guess").on 'submit', (e) ->
        e.preventDefault()
        code = []
        for i in [1..code_length]
            word = $("#guess_code" + i).val()
            code.push word

        guess =
            code : code.slice()

        if code.length = code_length && code.every((x) -> x > 0)
            $("#form-select-guess").hide()
            $("#warning").empty()
            socket.emit('make_guess', guess)
        else
            $("#warning").html("You must make a guess!")

    $("#btn_guess_words").on 'click', (e) ->
        e.preventDefault()
        words = []
        for i in [1..num_words]
            word = $("#words_entry" + i).val()
            words.push word

        if words.length == num_words && words.some((x) -> x.length > 0) &&
           words.every((x) -> x.length == 0 || is_ascii(x))
            socket.emit('guess_words', words.slice())
        else
            $("#warning").html("You must guess at least one valid word!")

    $("#btn_guess_words_skip").on 'click', (e) ->
        words = Array(num_words).fill("")
        socket.emit('guess_words', words.slice())

    $("#btn_force_end").on 'click', (e) ->
        $("#force_end_confirm").show()

    $("#btn_force_end_confirm").on 'click', (e) ->
        $("#force_end_confirm").hide()
        $("#force_end").hide()
        if force_end_state == GAME_ENCRYPT
            socket.emit 'force_end_encrypt'
        else if force_end_state in [GAME_DECRYPT_RED, GAME_DECRYPT_BLUE]
            socket.emit 'force_end_decrypt'

    $("#btn_force_end_cancel").on 'click', (e) ->
        $("#force_end_confirm").hide()

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

toggle_list = (class_str, target) ->
        $('.' + class_str, target).toggle()
        $('.caret-right', target).toggle()
        $('.caret-down', target).toggle()

kind_to_class = (kind) ->
        if kind == TEAM_RED
            "redteam"
        else if kind == TEAM_BLUE
            "blueteam"
        else if kind == TEAM_NONE
            "noteam"

team_to_class = (team) ->
        kind_to_class(team)

guess_to_str = (guess) ->
        if guess == -1
            "&nbsp;"
        else guess

is_ascii = (s) ->
        return /^[ -~]+$/.test(s)
