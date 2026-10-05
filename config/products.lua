--[[ ---------------------------------------------------------------------------
    PRODUCTS: extra packs, boxes, tins, chase cards (inserts), error cards, rookies,
    sealed value and big-pull announcements
--------------------------------------------------------------------------- ]]

-- more packs (merged into Config.Packs). insertChance = chance a pack holds an autograph / relic.
-- Packs with a hit weigh a little more in the inventory (Config.Inserts.hitWeight).
local P = Config.Packs
-- (no built-in packs: each series defines its own, see config/series2.lua)

-- boxes & tins: use them to get their contents (the old Config.BoosterBox still works too)
Config.Boxes = {
    -- empty on purpose. Example:
    -- ['ascard_my_box'] = { label = 'My Box', duration = 4000, gives = { { item = 'ascard_s2_booster', count = 6 } } },
}

-- chase cards. Numbered like parallels (print runs shared server-wide per player)
Config.Inserts = {
    hitWeight = 3,              -- extra grams on a pack that holds a hit (ox_inventory metadata.weight)
    packWeight = 20,            -- normal pack weight in grams
    types = {
        { id = 'relic',     label = 'Match-Worn Relic',  weight = 60, maxPrints = 99, value = 8 },
        { id = 'auto',      label = 'Autograph',         weight = 32, maxPrints = 50, value = 15 },
        { id = 'autorelic', label = 'Autograph Relic',   weight = 8,  maxPrints = 10, value = 40 },
        -- case hit: never in normal packs, only as a Config.CaseHits pull
        { id = 'legendsgame', label = 'Legends of the Game', weight = 0, maxPrints = 25, value = 60, caseHit = true },
    },
    -- which card types can get an insert, and how likely each is picked
    cardWeights = { player = 40, star = 30, captain = 14, winner = 10, century = 4, legend = 2 },
}

-- CASE HITS: the rarest insert. Roughly one per `perBoxes` hobby boxes (a "case" of 12 in real life).
-- The box's pack that holds it is chosen when the box is opened. Only big names can be a case hit.
Config.CaseHits = {
    enabled = true,
    insert = 'legendsgame',
    boxes = {},                              -- e.g. { ascard_my_box = 12 }: about 1 in N of these boxes has a case hit
    cardWeights = { legend = 50, century = 30, winner = 20 },
}

-- rare misprints (chance per card pulled). value = sell multiplier
Config.Errors = {
    chance = 0.002,
    kinds = {
        { id = 'misspelt',  label = 'Misspelt Name',  weight = 30, value = 3 },
        { id = 'noStats',   label = 'Missing Stats',  weight = 25, value = 3 },
        { id = 'wrongFlag', label = 'Wrong Flag',     weight = 25, value = 2.5 },
        { id = 'inkShift',  label = 'Ink Shift',      weight = 15, value = 4 },
        { id = 'blankBack', label = 'Blank Back',     weight = 5,  value = 6 },
    },
}

-- rookie cards (RC logo, worth a bit more)
Config.RookieValue = 1.5
Config.Rookies = {}   -- card ids (from your own cards) that get the RC logo

-- sealed product slowly gains value while it stays unopened (sell it back to the buyer)
Config.Sealed = {
    released = {},                         -- set release time (unix), e.g. { series2 = 1790380800 }
    growthPerWeek = 0.03,                  -- +3% a week...
    maxMultiplier = 3.0,                   -- ...up to 3x the shop price
    buyerPays = 0.8,                       -- the buyer pays 80% of the current sealed value
}

-- big pulls posted to Discord only (nothing in game). Put the webhook in server.cfg:
--   set ascard_webhook "https://discord.com/api/webhooks/..."
Config.Discord = {
    enabled = true,
    username = 'UKC Card Pulls',
    announce = { inserts = true, oneOfOne = true, legendsNumbered = false, errors = true },

    -- daily market report: top sales, biggest pulls, price movers. Webhook in server.cfg:
    --   set ascard_market_webhook "https://discord.com/api/webhooks/..."   (falls back to ascard_webhook)
    -- /cardreport (admin) posts one now.
    marketReport = { enabled = true, hour = 20, minute = 0, username = 'LS Card Exchange' },
}
