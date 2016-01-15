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

displayGame = (game) ->
    TEAM_RED           = 1
    TEAM_BLUE          = 2
    
    WORD_RED           = 1
    WORD_BLUE          = 2
    WORD_GREY          = 3
    WORD_BLACK         = 4

    players = []
    for p in game.players
        players[p.id] = p

    scorestr = ""
    bluestr = "Game Over. Blue team wins!"
    if game.isCoop
        scorestr = " Co-op score: " + game.coopScore.toString() + " points."
        bluestr = "Game Over. Co-op game lost!"

    if game.winningTeam == TEAM_RED
        $("#gameover")
            .addClass("redteam")
            .text("Game Over. Red team wins!" + scorestr)
    else
        $("#gameover")
            .addClass("blueteam")
            .text(bluestr)


    $("#players").empty().addClass("wordlist")
    for w in game.words
        li = $("<li>")
            .addClass("list-group-item")
            .addClass("wordlist")
            .text(w.word)

        if w.guessed
            li.addClass("guessed")
        
        if w.kind == WORD_RED
            li.addClass("redteam")
        else if w.kind == WORD_BLUE
            li.addClass("blueteam")
        else if w.kind == WORD_GREY
            li.addClass("noteam")
        else if w.kind == WORD_BLACK
            li.addClass("blackteam")


        $("#players").append(li)
