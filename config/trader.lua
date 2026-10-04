--[[ ---------------------------------------------------------------------------
    NPC TRADER and COLLECTOR DESK
    One ped. Swaps cards (no cash) and pays cash for the day's "wants".
    The NPC covers when nobody is on duty at the player card shop, and steps back
    (ped removed, options closed) as soon as a `cardshop` employee clocks on.

    >>> SET coords below (x, y, z, heading). Leave it at 0,0,0,0 and the trader stays off. <<<
--------------------------------------------------------------------------- ]]
Config.Trader = {
    enabled = true,
    ped = {
        model = 'a_m_y_business_02',
        coords = vec4(0.0, 0.0, 0.0, 0.0),
        scenario = 'WORLD_HUMAN_STAND_IMPATIENT',
        blip = { sprite = 605, colour = 5, scale = 0.6, label = 'Card Trader' },
    },
    coverWhenNoStaff = true,       -- false = the NPC is always there

    swapsPerDay = 10,              -- per player
    rollHour = 6,                  -- rates (and wants) change at this hour, server time

    -- plain cards only for quantity / sidegrade swaps (no parallels, inserts, errors, graded slabs)
    plainOnly = true,

    -- QUANTITY: hand over N cards of a type, get 1 card of the next type up.
    -- Base counts; each day the trader shifts them by -1..+1 (never below minGive).
    quantity = { minGive = 2, base = { player = 5, star = 4, captain = 3, winner = 3, century = 2 } },

    -- CONDITION: hand over a raw card + N copies of the same card (any condition) and get YOUR card back
    -- restored: base scores +steps, and dust / fingerprints / dirt / stains / whitening / sun fade removed.
    -- Creases, dings, water damage and warping are NOT fixed.
    condition = { steps = 2, dupes = 2, dupesRange = 1 },

    -- SIDEGRADE: 1 card of a type for a different card of the same type.
    -- Today's 'hot' types swap 1 for 1, everything else needs `others` cards.
    sidegrade = { hotTypes = 2, others = 2 },
}

Config.Collector = {
    enabled = true,                -- the same ped
    wantsPerDay = 3,
    -- cash only (x the card's market value)
    pay = { card = 1.35, slab = 1.5, brand = 1.25 },
    slabMinGrade = { 8, 9, 10 },   -- a slab want picks one of these
    brandCards = 3,                -- a brand want = this many cards of the club
    brandBonus = 0.20,             -- brand week: cards from that club pay this much more
    brandWeekDay = 1,              -- brand week changes on this weekday at rollHour (1 = Monday, 0 = Sunday)
}
