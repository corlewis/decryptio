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

TEAM_RED           = 1
TEAM_BLUE          = 2

WORD_RED           = 1
WORD_BLUE          = 2
WORD_GREY          = 3
WORD_BLACK         = 4

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
        
        li.addClass(kind_to_class(w.kind))

        $("#players").append(li)

    $("#clues").empty()

    for c, index in game.clues
        guesses = $("<ul>")
            .attr("id", "guesses" + index)
            .addClass("list-group")
        for g in c.guesses
            li = $("<li>")
                .addClass("list-group-item guessed")
                .text(g.word)
                .append($('<span>').text(g.player)
                                   .addClass("pull-right " + team_to_class(c.team)))
            li.addClass(kind_to_class(g.kind))

            guesses.append(li)

        if c.numWords > 10
            c.numWords = "Infinite"

        li = $("<li>")
            .attr("id", index)
            .addClass("list-group-item")
            .text(c.word)
            .append($('<span>').addClass("pull-right").text(c.numWords))
            .append(guesses)
        li.addClass(team_to_class(c.team))
        li.on 'click', (e) ->
            $("#guesses" + $(e.target).attr("id")).toggle()

        $("#clues").append(li)
        $("#guesses" + index).hide()

kind_to_class = (kind) ->
        if kind == WORD_RED
            "redteam"
        else if kind == WORD_BLUE
            "blueteam"
        else if kind == WORD_GREY
            "noteam"
        else if kind == WORD_BLACK
            "blackteam"

team_to_class = (team) ->
        kind_to_class(team)