--[[ ---------------------------------------------------------------------------
    MARKET, AUCTIONS, PHONE APP AND WEBSITE
    Prices move with supply (how many copies have been pulled compared with other
    cards of the same type) and with what players actually pay in auctions.
    The same prices, checklist, auctions and stolen-serial lookup are on:
      - the sd-phone app   (needs sd-phone)
      - the website        (needs as-browser)
    Won auctions (and unsold / cancelled items going back) are delivered to a
    Postal Prime locker (needs as-postalprime). Without it, items go straight
    into the player's pockets the next time they are online.
--------------------------------------------------------------------------- ]]

Config.Market = {
    enabled = true,
    recomputeMinutes = 2,           -- how often prices are worked out again (also straight after every auction sale)
    historyMinutes = 60,            -- how often a price point is saved for the charts
    historyDays = 30,               -- how far back the charts go

    -- supply: fewer copies pulled than the average card of the same type = worth more
    supply = {
        elasticity = 0.35,          -- how strongly supply moves the price (0 = not at all)
        padding = 25,               -- stops the first few pulls swinging prices wildly
        min = 0.6, max = 2.5,       -- the supply multiplier never goes outside this
        soldOutBonus = 1.25,        -- a card with maxPrints that can't be pulled any more
    },

    -- demand: recent auction sales pull the price towards what people actually pay
    demand = {
        days = 14,                  -- sales from the last N days count
        minSales = 3,               -- need at least this many sales before demand counts
        weight = 0.5,               -- 0 = ignore sales, 1 = follow sales completely
        min = 0.6, max = 1.8,
    },

    -- selling to the card shop uses market prices too (false = fixed config values)
    shopUsesMarket = true,
}

Config.Auctions = {
    enabled = true,
    account = 'bank',               -- bids and fees are taken from this account ('bank' | 'cash')

    -- the seller picks one; fee = listing fee paid up front (never refunded)
    durations = {
        { id = '1h',  label = '1 hour',   seconds = 3600,  fee = 25 },
        { id = '6h',  label = '6 hours',  seconds = 21600, fee = 50 },
        { id = '24h', label = '24 hours', seconds = 86400, fee = 100 },
    },
    finalValueFee = 0.05,           -- taken from the winning bid before the seller is paid (0.05 = 5%)

    minStart = 1,
    maxPrice = 10000000,
    minIncrement = 5,               -- next bid must beat the current one by at least this much...
    minIncrementPct = 0.05,         -- ...or this percent, whichever is bigger

    -- anti-snipe: a bid in the last `window` seconds pushes the end back to `extend` seconds from now
    antiSnipe = { window = 120, extend = 120 },

    maxActivePerPlayer = 10,        -- live listings per player
    maxBidsWatching = 50,
    allowSealed = true,             -- sealed packs / boxes / tins can be auctioned
    allowSelfBid = false,

    -- delivery (as-postalprime lockers)
    delivery = {
        prepSeconds = 300,          -- how long before the parcel is ready at the locker
        expireSeconds = 172800,     -- how long it waits there once ready (then it comes back to you as a new parcel)
        sender = 'LS Card Exchange',
        retrySeconds = 60,          -- a player with too many parcels waiting gets it on the next try
    },

    sweepSeconds = 10,              -- how often ended auctions are settled

    -- lots: several cards / sealed items sold together in one auction
    maxLot = 10,

    -- make an offer: on a buy it now listing (before any bids) buyers can offer less.
    -- The offer money is held until the seller answers; declined / expired offers are refunded.
    offers = {
        enabled = true,
        minPercent = 0.5,           -- lowest offer = 50% of buy it now
        expireHours = 24,           -- unanswered offers are refunded after this
        maxPending = 10,            -- per listing
    },

    -- seller ratings: the winner can rate the seller once (positive / neutral / negative + a comment)
    ratings = {
        enabled = true,
        days = 14,                  -- how long after the sale the buyer can leave a rating
    },
}

Config.Alerts = {
    outbid = true,
    won = true,
    sold = true,
    unsold = true,
    endingSoon = 300,               -- seconds before the end to remind bidders (false = off)
    gradingReady = true,
    priceAlerts = true,
    maxPriceAlerts = 10,            -- per player
    paidOut = true,                 -- money that was waiting (you were offline) has been paid in
}

-- the sd-phone app
Config.Phone = {
    enabled = true,
    identifier = 'as-tradingcards',
    name = 'Card Market',
    description = 'Card prices, auctions, your checklist and stolen-card checks.',
    defaultApp = false,             -- false = download it from the App Store
}

-- the as-browser website
Config.Site = {
    enabled = true,
    domain = 'lscardexchange.co.uk',
    title = 'LS Card Exchange',
    description = 'Trading card prices, live auctions, set checklists and stolen card checks.',
    keywords = { 'cards', 'trading cards', 'football cards', 'auction', 'price guide', 'stolen', 'serial', 'checklist' },
    category = 'Shopping',
    icon = '🃏',
    color = '#e8a33b',
}
