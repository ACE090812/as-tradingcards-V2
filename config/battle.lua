--[[ ---------------------------------------------------------------------------
    BATTLE  (player vs player, 30 card decks, life points)

    How a match works
      * Each player brings a deck box (30 cards). Cards are shuffled; you hold a hand of 5.
      * Every turn both players secretly pick a card from their hand. One is the ATTACKER
        and one the DEFENDER (it swaps every turn).
      * Damage = (attacker ATT - defender DEF) x damageScale, only if positive.
        All of it goes to the defender's life ("overflow" - no cap).
      * Card position gives a small bonus (strikers hit harder, defenders block better).
      * Parallels / foils / inserts add stat boosts (same idea as Top Trumps).
      * First to 0 life loses. After matchSeconds the player with more life wins.
      * Stats only: no spells, traps or card abilities.
--------------------------------------------------------------------------- ]]
Config.Battle = {
    enabled = true,

    life = 4000,
    deckSize = 30,                 -- a deck box must hold exactly this many cards
    maxCopies = 2,                 -- of the same card
    maxLegend = 1,                 -- legend type cards in one deck
    legendType = 'legend',
    handSize = 5,

    damageScale = 10,              -- life lost per point of (ATT - DEF)
    turnSeconds = 20,              -- pick time; then a card is picked for you
    revealSeconds = 4.5,           -- pause to show the clash
    matchSeconds = 10 * 60,        -- match cap: higher life wins (equal = draw)
    maxStat = 120,                 -- cap after boosts and position bonus

    -- position bonuses (card.pos). Anything not listed gets no bonus.
    positions = {
        FWD = { att = 5, def = 0 }, ST = { att = 5, def = 0 }, CF = { att = 5, def = 0 }, RW = { att = 4, def = 0 }, LW = { att = 4, def = 0 },
        MID = { att = 2, def = 2 }, CM = { att = 2, def = 2 }, AM = { att = 3, def = 1 }, RM = { att = 2, def = 2 }, LM = { att = 2, def = 2 }, CDM = { att = 1, def = 3 },
        DEF = { att = 0, def = 5 }, CB = { att = 0, def = 5 }, RB = { att = 0, def = 4 }, LB = { att = 0, def = 4 },
        GK = { att = 0, def = 6 },
    },

    -- rare versions play better: bonus added to both ATT and DEF
    boosts = {
        parallel = { black = 10, red = 7, gold = 5, blue = 3 },
        foil = 2,
        insert = 5,
    },

    -- wagers: both players pay in, the winner takes the pot. Draw / timeout tie = refunded.
    bets = { enabled = true, account = 'cash', min = 10, max = 50000 },

    -- the placeable battle table (item `ascard_table`)
    table = {
        item = 'ascard_table',
        model = 'prop_table_03b',
        zOffset = 0.0,             -- raise/lower the prop on the ground
        pickupBy = 'owner',        -- 'owner' | 'anyone' (staff can always pick up)
        maxPerPlayer = 1,
        maxTotal = 30,
        range = 3.0,               -- how close you must be to play / watch
        spectateRange = 8.0,
        placeAnim = { dict = 'pickup_object', clip = 'pickup_low' },
        spectators = true,
    },

    -- a match gets rank points only if the same two players haven't played each other this many times today
    rankedPairLimit = 3,
}

--[[ ---------------------------------------------------------------------------
    RANKS AND SEASONS
--------------------------------------------------------------------------- ]]
Config.Season = {
    lengthDays = 28,
    start = 1791158400,            -- Monday 5 Oct 2026 00:00 UTC. Season 1 begins here.
    leaderboardSize = 25,
    winPoints = 25,
    lossPoints = 8,                -- lost on a loss (never below 0)
    drawPoints = 0,
    forfeitWinPoints = 15,         -- win by the other player leaving
    -- tiers (each is split into III / II / I)
    tiers = {
        { id = 'bronze',   label = 'Bronze',   min = 0 },
        { id = 'silver',   label = 'Silver',   min = 100 },
        { id = 'gold',     label = 'Gold',     min = 300 },
        { id = 'platinum', label = 'Platinum', min = 600 },
        { id = 'diamond',  label = 'Diamond',  min = 1000 },
        { id = 'legend',   label = 'Legend',   min = 1500 },
    },
    announce = true,               -- tell the server when a season starts / its top 3
}

--[[ ---------------------------------------------------------------------------
    TOURNAMENTS (staff run them: /cardtourney)
--------------------------------------------------------------------------- ]]
Config.Tournament = {
    command = 'cardtourney',
    sizes = { 4, 8, 16 },
    readySeconds = 90,             -- a player who doesn't turn up for their match forfeits it
    roundPoints = 10,              -- extra rank points per round won
    championPoints = 50,
    entryFee = 0,                  -- always free (no prize money is paid out; rank points only)
}

--[[ ---------------------------------------------------------------------------
    PLAYMATS
    Built-in mats are CSS. Mats made in your board creator are listed in custom/mats.json
    (see custom/README.txt) and show up here with no code changes.
--------------------------------------------------------------------------- ]]
Config.Mats = {
    default = 'night',
    list = {
        { id = 'night',  label = 'Night Pitch',    bg = 'linear-gradient(180deg,#17233a,#0f1626)', line = 'rgba(255,255,255,.2)', slot = 'rgba(255,255,255,.3)' },
        { id = 'green',  label = 'Matchday Green', bg = 'linear-gradient(180deg,#1f6b3f,#12482a)', line = 'rgba(255,255,255,.4)', slot = 'rgba(255,255,255,.45)' },
        { id = 'amber',  label = 'Ink and Amber',  bg = 'linear-gradient(180deg,#241c10,#120e08)', line = 'rgba(240,168,50,.5)',   slot = 'rgba(240,168,50,.5)' },
    },
}
