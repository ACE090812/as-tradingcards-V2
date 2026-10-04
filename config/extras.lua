--[[ ---------------------------------------------------------------------------
    EXTRAS: pop report, weekly shop stock, pack scale, slab case, grade reveal
--------------------------------------------------------------------------- ]]

-- Population report: how many of each card have been graded, and at what grade.
-- Like the real thing, cracking a slab does NOT take it off the report.
Config.Pop = { enabled = true }

-- Weekly stock: these shop items only get `amount` a week and can sell out.
-- Everything not listed here is unlimited.
Config.Stock = {
    enabled = true,
    restockDay = 5,        -- 0 = Sunday, 1 = Monday ... 5 = Friday, 6 = Saturday (server time)
    restockHour = 18,      -- 0-23
    items = {
        ascard_hobby_box = 10,
        ascard_blaster   = 25,
        ascard_tin       = 25,
        ascard_booster_box = 20,
    },
}

-- Pack scale: weigh sealed packs to hunt for the ones with a hit in them.
-- A pack with a hit is `hitGrams` heavier. Every pack also varies a little on its own (`packSpread`,
-- the same every time you weigh that pack) and each reading wobbles (`wobble`), so a heavy reading
-- is a strong clue, not a guarantee. Bigger hitGrams = easier to find hits.
Config.Scale = {
    enabled = true,
    item = 'ascard_scale',
    baseGrams = 20.0,
    hitGrams = 0.8,
    packSpread = 0.5,
    wobble = 0.15,
    time = 1500,           -- ms per pack
    -- true = every pack is its own inventory slot with a seal number, so hit packs can't be
    -- spotted by stacking separately (the scale is the only way). false = packs stack.
    uniquePacks = true,
}

-- Slab case: holds graded slabs only (ox_inventory). The slabs stay with the case item.
Config.SlabCase = {
    enabled = true,
    item = 'ascard_slabcase',
    slots = 10,
    maxWeight = 5000,
}

-- Grade reveal: collecting from the grader plays a reveal for each slab
Config.GradeReveal = { enabled = true }

-- Repacks: cards players sell to the card shop go into a pool. The shop sells mystery "repacks"
-- made from that pool (opened on the spot). Cheap cards come up more often than expensive ones.
-- guarantee: nil | 'numbered' (numbered parallel, hit or graded) | 'bigHit' (graded or an autograph / relic)
-- maxValue: the most one card in that tier can be worth (nil = anything in the pool, including the chase card)
Config.Repacks = {
    enabled = true,
    tiers = {
        { id = 'bronze', label = 'Bronze Repack', price = 50,   cards = 3, maxValue = 300 },
        { id = 'silver', label = 'Silver Repack', price = 250,  cards = 3, maxValue = 3000, guarantee = 'numbered' },
        { id = 'gold',   label = 'Gold Repack',   price = 1000, cards = 2, guarantee = 'bigHit' },
    },
    -- if the pool runs short, Bronze repacks are topped up with fresh base cards (false = "out of stock")
    topUpBronze = true,
    maxPool = 2000,          -- oldest cheap cards drop out past this
}

-- Appraisal letter: ordered in the Card Market app / website for a card in your pockets.
-- The letter item (with the card, serial, condition, value and date) is sent to your Postal Prime locker.
Config.Appraisal = {
    enabled = true,
    item = 'ascard_appraisal',
    price = 50,
    issuer = 'LS Card Exchange Appraisals',
}

-- Pristine 10: a GEM MINT 10 where all four sub-grades are 10 gets a black PRISTINE label
Config.Pristine = {
    enabled = true,
    label = 'PRISTINE',
    valueMultiplier = 2.5,   -- on top of a normal 10
}

-- Collection value history (the chart in My cards): saved for online players every `minutes`
Config.ValueHistory = { enabled = true, minutes = 30, days = 60 }
