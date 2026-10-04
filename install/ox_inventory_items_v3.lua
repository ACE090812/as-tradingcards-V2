-- v3 items: add to ox_inventory/data/items.lua and copy the matching PNGs from html/img/items to ox_inventory/web/images

['ascard_deckbox'] = {
    label = 'Deck Box',
    weight = 150,
    stack = false,
    close = true,
    description = 'Holds a 30 card battle deck',
    server = { export = 'as-tradingcards.useItem' },
},

['ascard_table'] = {
    label = 'Card Battle Table',
    weight = 2500,
    stack = false,
    close = true,
    description = 'A foldable table for card battles. Place it down, battle, pick it up.',
    server = { export = 'as-tradingcards.useItem' },
},

['ascard_s2_booster'] = {
    label = 'Series 2 Booster',
    weight = 20,
    stack = true,
    close = true,
    description = 'Contains 5 football cards',
    server = { export = 'as-tradingcards.useItem' },
},

['ascard_s2_hobby_pack'] = {
    label = 'Series 2 Hobby Pack',
    weight = 30,
    stack = true,
    close = true,
    description = 'Contains 8 football cards',
    server = { export = 'as-tradingcards.useItem' },
},

['ascard_cr_booster'] = {
    label = 'Creature Booster',
    weight = 20,
    stack = true,
    close = true,
    description = 'Contains 5 creature cards',
    server = { export = 'as-tradingcards.useItem' },
},

['ascard_ls_booster'] = {
    label = 'Los Santos Booster',
    weight = 20,
    stack = true,
    close = true,
    description = 'Contains 5 Los Santos cards',
    server = { export = 'as-tradingcards.useItem' },
},

-- Binder cover icons (shown after a player picks a cover; no item needed, image only):
-- ascard_binder_leather.png, ascard_binder_pitch.png, ascard_binder_midnight.png, ascard_binder_terrace.png

-- OPTIONAL: add these buttons to each card item (ascard_player, ascard_star, ... ascard_legend) for Hold / Gift:
-- buttons = {
--     { label = 'Hold in hand', action = function(slot) exports['as-tradingcards']:holdCard(slot) end },
--     { label = 'Send as a gift', action = function(slot) exports['as-tradingcards']:giftCard(slot) end },
-- },
