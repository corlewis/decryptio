formatDate = (d) ->
    d = new Date(d)
    d_names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    ampm = if (d.getHours() < 13) then "am" else "pm"
    h = d.getHours() % 12
    h = if h == 0 then 12 else h
    s = d_names[d.getDay()] + " " +
        d.getDate() + "/" +
        (d.getMonth() + 1) + "/" +
        d.getFullYear() + " " +
        h + ":" + d.getMinutes() + ampm

jQuery ->
    switch window.location.pathname
        when "/games"
            gamesReq = $.ajax
                url : '/api?type=games'

            gamesReq.done (res, status, jqXHR) ->
                if not res then return

                for r in res
                    li = $("<a>")
                        .addClass("list-group-item")
                        .prop("href", "/game?id=" + r.id)
                        .html($("<b>").text(formatDate(r.date)))
                        .append($("<br>"))
                        .append(r.name)
                    $("#gamelist").append(li)

        when "/game"
            gameReq = $.ajax
                url : '/api' + window.location.search + '&type=game'

            gameReq.done (res, status, jqXHR) ->
                if not res then alert "abort abort!"
                displayGame(res)

TEAM_RED           = 0
TEAM_BLUE          = 1
TEAM_NONE          = 2
TEAMS              = [TEAM_RED, TEAM_BLUE]

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

displayGame = (game) ->

    players = []
    for p in game.players
        players[p.id] = p

    scorestr = ""
    bluestr = "Game Over. Blue team wins!"
    if game.isCoop
        bluestr = "Game Over. Co-op game lost!"

    if game.winningTeam == TEAM_RED
        $("#gameover")
            .addClass("redteam")
            .text("Game Over. Red team wins!")
    else if game.winningTeam == TEAM_BLUE
        $("#gameover")
            .addClass("blueteam")
            .text(bluestr)
    else
        $("#gameover")
            .text("Teams are tied! The team that can best guess their opponents keywords wins!")

    #Draw the scores
    $("#red_results").empty()
                     .html("&#x2714: " + game.score[TEAM_RED].intercepts + "/2 " +
                           "&#x2718: " + game.score[TEAM_RED].miscommunications + "/2")
    $("#blue_results").empty()
                     .html("&#x2714: " + game.score[TEAM_BLUE].intercepts + "/2 " +
                           "&#x2718: " + game.score[TEAM_BLUE].miscommunications + "/2")

    messages = zip(game.messages0, game.messages1)
    codes = zip(game.codes0, game.codes1)
    for i in TEAMS
        if i == TEAM_RED
            id_sfx = "_cur"
        else
            id_sfx = "_other"
        #Draw the list of messages
        $("#clues" + id_sfx).empty()
        first = true
        for list_m, round_index in messages
            round = round_index + 1
            both_codes = codes[round_index]
            if list_m[i].message.finished && list_m[other_team i].message.finished
                clues = $("<ul>")
                    .addClass("list-group clues")
                for clue, clue_index in list_m[i].message.clues
                    li = $("<li>")
                        .addClass("list-group-item clearfix")
                        .append($('<span>')
                            .css('width', '70%').css('float', 'left')
                            .text(clue_index + 1 + ": " + clue))
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
        $("#used_clues" + id_sfx).empty()
        words = $("<ul>")
            .attr("id", "used_clues_list" + id_sfx)
            .addClass("list-group words")
        for keyword in [1..game.gameOptions.num_words]
            word_clues = $("<ul>").addClass("list-group wordlist")
            for code, round in codes
                for keyword2, code_index in code[i]
                    clue = messages[round][i].message.clues[code_index]
                    if keyword == keyword2 && clue != "<Turn Timeout>"
                        li = $("<li>")
                            .addClass("list-group-item wordlist")
                            .text(clue)
                        word_clues.append(li)

            li = $("<li>")
                .addClass("list-group-item")
                .text("Keyword " + keyword + ":")
                .append(word_clues)
            words.append(li)

        li = $("<li>")
            .addClass("list-group-item " + team_to_class(i))
            .text(team_to_str(i) + " team's clues")
            .prepend($('<span>').addClass("caret-right").html("&#9658"))
            .prepend($('<span>').addClass("caret-down").html("&#9660").css({"display": "none"}))
            .append(words.hide())
        li.on 'click', (e) -> toggle_list('words', $(e.currentTarget))
        $("#used_clues" + id_sfx).append(li)

#    toggle_list('clues', "#clues0_cur")
#    toggle_list('clues', "#clues0_other")
    toggle_list('words', "#used_clues_cur")
    toggle_list('words', "#used_clues_other")

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

zip = () ->
  lengthArray = (arr.length for arr in arguments)
  length = Math.min(lengthArray...)
  for i in [0...length]
    arr[i] for arr in arguments
