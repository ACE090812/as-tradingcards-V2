--[[ ---------------------------------------------------------------------------
    SERIES 2  (built now, hidden until staff switch it on in /cardadmin > Switches > "Series 2")
    and SEASONAL LIMITED CARDS (retire from packs when their window closes)

    Series 2 cards come from your card creator output (custom/cards.json, set = "series2").
    The shop only sells Series 2 packs when the switch is ON *and* at least one Series 2 card exists.
--------------------------------------------------------------------------- ]]
Config.Sets.series2 = { label = 'Series 2', code = 'S2', hidden = true }

local P = Config.Packs
P['ascard_s2_booster'] = {
    label = 'Series 2 Booster', set = 'series2', cards = 5,
    weights = { player = 70, star = 20, captain = 6, winner = 3, century = 0.8, legend = 0.2 },
    guaranteed = { count = 1, minRarity = 'star' },
    foilChance = 0.05, insertChance = 0.01,
}
P['ascard_s2_hobby_pack'] = {
    label = 'Series 2 Hobby Pack', set = 'series2', cards = 8,
    weights = { player = 55, star = 24, captain = 9, winner = 7, century = 3, legend = 2 },
    guaranteed = { count = 2, minRarity = 'star' },
    foilChance = 0.10, insertChance = 0.06,
}

-- CREATURES and LOS SANTOS sets (from the card creator's other two themes). Released by the same switch, once each set has cards.
Config.Sets.creatures = { label = 'Creatures', code = 'CR', hidden = true }
Config.Sets.lossantos = { label = 'Los Santos', code = 'LS', hidden = true }
P['ascard_cr_booster'] = {
    label = 'Creature Booster', set = 'creatures', cards = 5,
    weights = { player = 70, star = 20, captain = 6, winner = 3, century = 0.8, legend = 0.2 },
    guaranteed = { count = 1, minRarity = 'star' },
    foilChance = 0.05, insertChance = 0.01,
}
P['ascard_ls_booster'] = {
    label = 'Los Santos Booster', set = 'lossantos', cards = 5,
    weights = { player = 70, star = 20, captain = 6, winner = 3, century = 0.8, legend = 0.2 },
    guaranteed = { count = 1, minRarity = 'star' },
    foilChance = 0.05, insertChance = 0.01,
}

-- sold in the card shop (and the player shop) only while the set is live
Config.Series2 = {
    set = 'series2',
    shop = {
        { item = 'ascard_s2_booster',     price = 12, label = 'Series 2 Booster (5 cards)' },
        { item = 'ascard_s2_hobby_pack',  price = 45, label = 'Series 2 Hobby Pack (8 cards)' },
        { item = 'ascard_cr_booster',     price = 12, label = 'Creature Booster (5 cards)' },
        { item = 'ascard_ls_booster',     price = 12, label = 'Los Santos Booster (5 cards)' },
    },
    released = nil,                -- unix time Series 2 came out (sealed value growth). nil = when staff switched it on
}

-- SEASONAL LIMITED CARDS
-- Put  seasonal = 'halloween26'  on a card (in custom/cards.json or config/cards.lua).
-- It can only drop from packs while its window is open. After `to` it never drops again (cards already pulled stay).
Config.Seasonal = {
    windows = {
        -- halloween26 = { label = 'Halloween 2026', from = 1792800000, to = 1793664000 },
    },
}
