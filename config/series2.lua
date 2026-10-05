--[[ ---------------------------------------------------------------------------
    SERIES 2  (built now, hidden until staff switch it on in /cardadmin > Switches > "Series 2")
    and SEASONAL LIMITED CARDS (retire from packs when their window closes)

    Series 2 cards come from your card creator output (custom/cards.json, set = "series2").
    The shop only sells Series 2 packs when the switch is ON *and* at least one Series 2 card exists.
--------------------------------------------------------------------------- ]]
-- No built-in series or packs. Series come from your cards (each card's `set` in custom/cards.lua creates one)
-- and packs are defined in custom/cards.lua too. This file only keeps the "switch a series on" plumbing.

-- Anything listed here is sold in the card shop (and the player shop) only while its set is live.
-- Custom packs are added to the shop automatically (Config.Custom.shop), so this stays empty.
Config.Series2 = {
    set = 'series2',
    shop = {
        -- { item = 'pack_myseries', price = 12, label = 'My Series Pack (5 cards)' },
    },
    released = nil,                -- unix time the series came out (sealed value growth). nil = when staff switched it on
}

-- SEASONAL LIMITED CARDS
-- Put  seasonal = 'halloween26'  on a card (in custom/cards.json or config/cards.lua).
-- It can only drop from packs while its window is open. After `to` it never drops again (cards already pulled stay).
Config.Seasonal = {
    windows = {
        -- halloween26 = { label = 'Halloween 2026', from = 1792800000, to = 1793664000 },
    },
}
