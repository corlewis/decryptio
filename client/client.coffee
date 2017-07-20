Array::sum = () ->
    @reduce (x, y) -> x + y

VERSION = 3
timer_handle = undefined
can_end_turn = false

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

        $("#timeleft").text("Time left for clue: " + neg + minutes + ":" + seconds)
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

            $(players[i]).removeClass("spy")
            if p.spy
                $(players[i]).addClass("spy")

       

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
                select = ''
                for i in [0..8]
                    select += '<option value=' + i + '>' + i + '</option>'
                $("#opt_assassins").html(select)
                $('#opt_assassins option[value="1"]').attr("selected", "selected");

                select = '<option value=0>No Limit</option>'
                for i in [1..10]
                    secs = i * 30
                    select += '<option value=' + secs + '>' + secs + ' Seconds </option>'
 
                $("#opt_timelimit").html(select)
                $('#opt_timelimit option[value="0"]').attr("selected", "selected");

                $("#opt_starttimelimit").html(select)
                $('#opt_starttimelimit option[value="0"]').attr("selected", "selected");
     
                players = $("#gameinfo li")
                
                $("#btn_randomize_teams").show()
                    .on 'click', (e) ->
                        spies = []
                        nonspies = []
                        players.each (i, p) ->
                            if $(this).find("input").attr("spy") == "true"
                                spies.push(p)
                            else
                                nonspies.push(p)
                    
                        if spies.length < 2
                            nonspies = $.merge(spies, nonspies)
                        else
                            sspies = shuffle(spies)
                            set_team($(sspies[0]), TEAM_RED)
                            set_team($(sspies[1]), TEAM_BLUE)
                                  
                        $.each shuffle(nonspies), (i, p) ->
                            jitter = Math.floor(Math.random() * 2)
                            middle = (nonspies.length - jitter) / 2
                            if i < middle
                                set_team($(this), TEAM_RED)
                            else if i >= middle
                                set_team($(this), TEAM_BLUE)
                        emit_teams()

                $("#btn_randomize_spies").show()
                    .on 'click', (e) ->
                        red_spy = false
                        blue_spy = false
                        neither = []

                        players.each (i, p) ->
                            set_spy($(this), false)

                        shuffle(players).each (i, p) ->
                            team = parseInt($(this).find("input").attr("team"),10)
                            if team == TEAM_RED && not (red_spy)
                                set_spy($(this), true)
                                red_spy = true
                            else if team == TEAM_BLUE && not (blue_spy)
                                set_spy($(this), true)
                                blue_spy = true
                            else
                                neither.push(p)

                        if not (red_spy)
                            set_spy($(neither[0]), true)
                            neither.splice(0,1)

                        if not (blue_spy)
                            set_spy($(neither[0]), true)

                        emit_teams()
    
                $("#btn_start_game").show()
                $("#gameoptions").show()

            else
                $("#waitforhost").show()

            window.have_game_info = true

        else
            $("#pregame").hide()
            $("#game").show()

            #Draw the list of players
             
            for p in game.players
                if p.id == game.me.id
                    me = p
            can_end_turn = game.currentTeam != me.team && me.spy && game.state == GAME_CLUE && game.timeLimit > 0
 
            if not timer_handle && game.timeLimit > 0
               timer_handle = setInterval ->
                   socket.emit 'timeleft'
                 , 500
            if not (game.timeLimit > 0) && timer_handle
                clearInterval(timer_handle)
                timer_handle = undefined

 
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
                if game.state == GAME_VOTE && (game.currentTeam == me.team && not (me.spy) && not (w.guessed)) || (game.isCoop && game.currentTeam == TEAM_BLUE && me.spy && w.kind == WORD_BLUE && not(w.guessed))

                    li.on 'click', (e) ->
                        select_for_guess($(e.target))
                    input = $("<input>").attr
                        type    : 'hidden'
                        word    : w.word
                        value   : 0
                    li.append(input)

                $("#players").append(li)

            $("#clues").empty()

            gclues = game.clues

            for c in gclues.reverse()
                if c.numWords > 10
                    c.numWords = "Infinite"

                li = $("<li>")
                    .addClass("list-group-item")
                    .text(c.word)
                    .append($('<span>').addClass("pull-right").text(c.numWords))
                if c.team == TEAM_RED
                    li.addClass("redteam")
                else if c.team == TEAM_BLUE
                    li.addClass("blueteam")

                $("#clues").append(li)

            #Make quest proposal button visible to leader
            $("#teaminfo").show()
            $("#team_form").show()

            if me.team == TEAM_RED
                   teamstr = "Red"
            else if me.team == TEAM_BLUE
                   teamstr = "Blue"

            if me.spy
                $("#team_form").hide()
                $("#spy_form").show()
                $("#btn_pass_turn").hide()
                $("#form-give-clue").show()
            else
                $("#form-give-clue").hide()

            if game.state == GAME_CLUE && game.timeLimit > 0
                $("#timeleft").show()
            else 
                $("#timeleft").hide()

            if (game.state == GAME_VOTE && game.currentTeam == me.team) 
                if not (me.spy)
                    $("#btn_select_guess").show()
                    $("#btn_pass_turn").show()
                    if game.guessesLeft > 10
                        guessstr = "You have no guess limit."
                     else
                        guessstr = game.guessesLeft + " guesses left."

                    $("#teaminfo").html("You are on team " + teamstr + ". Guess a word. " + guessstr)
                else
                    $("#btn_give_clue").hide()
                    $("#clue_entry").hide()
                    $("#clue_numwords").hide()
                    $("#spyinfo").html("You are the " + teamstr + " leader. Waiting for team to guess.")

            if (game.currentTeam != me.team)
                if me.spy
                    $("#btn_give_clue").hide()
                    $("#clue_entry").hide()
                    $("#clue_numwords").hide()
                    if can_end_turn && game.timeLeft < 0 && game.timeLimit > 0
                        $("#btn_force_end").show()
                    $("#spyinfo").html("You are the " + teamstr + " leader. It is not your turn.")
                else 
                    $("#btn_select_guess").hide()
                    $("#btn_pass_turn").hide()
                    if me.team == TEAM_NONE
                        $("#teaminfo").html("You are spectating.")
                    else
                        $("#teaminfo").html("You are on team " + teamstr + ". It is not your turn")
           
            if (game.state == GAME_VOTE && game.currentTeam == TEAM_BLUE && game.isCoop && me.spy)
                    $("#team_form").show()
                    $("#btn_select_guess").show()
                    $("#btn_pass_turn").hide()
                    $("#teaminfo").html("Red team turn is over. Pick a blue card to hide.")
                    $("#spyinfo").html("")

            if (game.state == GAME_CLUE && game.currentTeam == me.team)
                if me.spy
                    $("#btn_give_clue").show()
                    $("#clue_entry").show()
                    $("#clue_numwords").show()

                    remaining = 0
                    for w in game.words
                        if (w.kind == WORD_RED && me.team == TEAM_RED) || (w.kind == WORD_BLUE && me.team == TEAM_BLUE)
                            if not w.guessed
                                remaining += 1
 
                    select = '<option val=-1></option>'
                    for i in [0..remaining]
                        select += '<option value=' + i + '>' + i + '</option>'
                    select += '<option value=100>Infinite</option>'

                    $("#clue_numwords").html(select)
                    $('#clue_numwords option[value="-1"]').attr("selected", "selected");
                    $("#clue_entry").val("")
                    $("#spyinfo").html("You are the " + teamstr + " leader. Enter a clue.")
                else
                    $("#btn_select_guess").hide()
                    $("#btn_pass_turn").hide()
                    $("#teaminfo").html("You are on team " + teamstr + ". Waiting for a clue.")

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

    $("#btn_pass_turn").on 'click', () ->
        socket.emit 'pass_turn'
    
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
        blue_team = 0
        red_team = 0
        blue_spies = 0
        red_spies = 0
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
                if spy
                    red_spies += 1
            else if team == TEAM_BLUE
                blue_team +=1
                if spy
                    blue_spies += 1
            teams[player_id] = entry
            sorted[player_id] = i
        is_coop = (red_spies == 1) && red_team == players.length
        options = {}
        options['num_assassins'] = $("#opt_assassins").val()
        options['time_limit'] = $("#opt_timelimit").val()
        options['start_time_limit'] = $("#opt_starttimelimit").val()
        console.log('options', options)

        if (red_spies == 1 && blue_spies == 1 && red_team > 1 && blue_team > 1 && (red_team + blue_team == players.length)) || is_coop
            socket.emit('startgame', {order: sorted, options: options, teams : teams, is_coop: is_coop})
        else
            return
    $("#form-give-clue").on 'submit', (e) ->
        e.preventDefault()
        word = $("#clue_entry").val()
        numWords = $("#clue_numwords").val()
        console.log('numWords', numWords)

        clue =
            word : word
            numWords : numWords

        if word.length > 0 && numWords.length > 0
            $("#clue_entry").hide()
            $("#clue_numwords").hide()
            socket.emit('give_clue', clue)
        else
            $("#spyinfo").html("You must give a valid clue!")

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
            sel.removeClass('active')
            socket.emit('make_guess', guess)
        else
            $("#leaderinfo").html("You must make a guess!")

    $("#btn_force_end").on 'click', (e) ->
        $("#btn_force_end").hide()
        socket.emit 'force_end'

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
