--[[ ---------------------------------------------------------------------------
    PRODUCTS: extra packs, boxes, tins, chase cards (inserts), error cards, rookies,
    sealed value and big-pull announcements
--------------------------------------------------------------------------- ]]

-- more packs (merged into Config.Packs). insertChance = chance a pack holds an autograph / relic.
-- Packs with a hit weigh a little more in the inventory (Config.Inserts.hitWeight).
local P = Config.Packs
P['ascard_booster_pack1'].insertChance = 0.01
P['ascard_booster_pack2'].insertChance = 0.02
P['ascard_fat_pack'] = {
    label = 'Series 1 Fat Pack', set = 'series1', cards = 7,
    weights = { player = 66, star = 20, captain = 7, winner = 5, century = 1.5, legend = 0.5 },
    guaranteed = { count = 1, minRarity = 'star' },
    foilChance = 0.05, guaranteedFoil = 1,          -- always at least 1 foil
    insertChance = 0.015,
}
P['ascard_blaster_pack'] = {
    label = 'Blaster Exclusive Pack', set = 'series1', cards = 3,
    weights = { player = 40, star = 35, captain = 12, winner = 9, century = 3, legend = 1 },
    guaranteed = { count = 1, minRarity = 'captain' },
    foilChance = 0.25, guaranteedParallel = true,   -- always one numbered parallel (blue or better)
    insertChance = 0.03,
}
P['ascard_hobby_pack'] = {
    label = 'Series 1 Hobby Pack', set = 'series1', cards = 8,
    weights = { player = 55, star = 24, captain = 9, winner = 7, century = 3, legend = 2 },
    guaranteed = { count = 2, minRarity = 'star' },
    foilChance = 0.10,
    insertChance = 0.06,                            -- plus one guaranteed hit per hobby box
}

-- boxes & tins: use them to get their contents (the old Config.BoosterBox still works too)
Config.Boxes = {
    ['ascard_blaster'] = {
        label = 'Series 1 Blaster Box', duration = 4000,
        gives = { { item = 'ascard_booster_pack1', count = 6 }, { item = 'ascard_blaster_pack', count = 1 } },
    },
    ['ascard_hobby_box'] = {
        label = 'Series 1 Hobby Box', duration = 5000,
        gives = { { item = 'ascard_hobby_pack', count = 12 } },
        guaranteedHits = 1,                         -- this many of the packs are guaranteed to hold a hit
    },
    ['ascard_tin'] = {
        label = 'Series 1 Collector Tin', duration = 3500,
        gives = { { item = 'ascard_booster_pack1', count = 4 } },
        bonusCard = { minRarity = 'winner', foil = true },   -- plus one limited card straight into your inventory
    },
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
    boxes = { ascard_hobby_box = 12 },       -- box item = about 1 in N of these boxes has a case hit
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
Config.Rookies = { 'abbot', 'acheampongg', 'adupoke', 'amassive', 'ansahh', 'armstrongg', 'auto', 'baba', 'baby', 'bane', 'board', 'braggo', 'burgerfall', 'cadamarteree', 'castlediney', 'collier', 'doughman', 'drawer', 'dribbling', 'echoverri', 'ehibhatiomhann', 'essugoh', 'estevow', 'fetched', 'fetchedmu', 'fredricck', 'frypan', 'fury', 'gameswo', 'greyth', 'hatto', 'hearings', 'heavens', 'ibehh', 'jacket', 'jamswx', 'jimohalba', 'khusanova', 'koleoshoh', 'koli', 'kroupier', 'lace', 'leonee', 'lewisshelly', 'lissahh', 'madjoh', 'mainoodle', 'make', 'mamma', 'manzambee', 'mash', 'mbayey', 'mouzakitiss', 'mubamah', 'mukasah', 'ngumoka', 'nicolljazulee', 'nwanderi', 'nyonion', 'obikwoo', 'opokoo', 'oreally', 'osmun', 'pick', 'quenchda', 'reds', 'rigging', 'sari', 'scales', 'series', 'shutter', 'smiley', 'steer', 'subuloyey', 'telly', 'tour', 'tune', 'vazz', 'vita', 'vuskovitch', 'wagonch', 'waltz', 'wheatlee', 'yeoh', 'yohannah', 'yoyo' }

-- sealed product slowly gains value while it stays unopened (sell it back to the buyer)
Config.Sealed = {
    released = { series1 = 1790380800 },   -- set release time (unix)
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
