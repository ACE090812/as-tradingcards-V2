--[[ ---------------------------------------------------------------------------
    TOP TRUMPS
    Challenge a player standing near you (/toptrumps, or target them with ox_target).
    Both players use cards from their own pockets (raw cards and slabs). Each round
    the chooser picks Attack or Defence; the higher number wins the round and picks
    next. Most rounds won wins the game. Cards never change hands.
--------------------------------------------------------------------------- ]]
Config.TopTrumps = {
    enabled = true,
    command = 'toptrumps',
    target = true,               -- ox_target option on nearby players
    rounds = 5,                  -- cards dealt to each player (they need at least this many)
    range = 4.0,                 -- how close the other player must be to challenge
    inviteSeconds = 30,          -- how long a challenge waits for an answer
    turnSeconds = 20,            -- chooser's time to pick; then the better stat is picked for them
    revealSeconds = 3.5,         -- pause after each round

    -- bets: players choose a cash bet or no bet when they challenge. Both pay the same into the pot.
    bets = {
        enabled = true,
        account = 'cash',        -- 'cash' | 'bank'
        min = 10,
        max = 50000,
    },

    -- rare versions play better: bonus added to both Attack and Defence
    boosts = {
        parallel = { blue = 3, gold = 5, red = 7, black = 10 },
        foil = 2,
        insert = 5,              -- autographs / relics / case hits
    },
    maxStat = 110,               -- cap after boosts
}
