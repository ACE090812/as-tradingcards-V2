-- New packs, boxes and tins: add to ox_inventory/data/items.lua

['ascard_fat_pack'] = {
    label = 'Series 1 Fat Pack',
    weight = 20,
    stack = true,
    close = true,
    description = '7 cards, at least one foil',
    server = { export = 'as-tradingcards.useItem' },
},

['ascard_blaster_pack'] = {
    label = 'Blaster Exclusive Pack',
    weight = 20,
    stack = true,
    close = true,
    description = '3 cards with a guaranteed numbered parallel',
    server = { export = 'as-tradingcards.useItem' },
},

['ascard_hobby_pack'] = {
    label = 'Series 1 Hobby Pack',
    weight = 20,
    stack = true,
    close = true,
    description = '8 cards - hobby packs are where the hits are',
    server = { export = 'as-tradingcards.useItem' },
},

['ascard_blaster'] = {
    label = 'Series 1 Blaster Box',
    weight = 200,
    stack = true,
    close = true,
    description = '6 boosters + 1 exclusive pack',
    server = { export = 'as-tradingcards.useItem' },
},

['ascard_hobby_box'] = {
    label = 'Series 1 Hobby Box',
    weight = 500,
    stack = true,
    close = true,
    description = '12 hobby packs, one guaranteed autograph or relic',
    server = { export = 'as-tradingcards.useItem' },
},

['ascard_tin'] = {
    label = 'Series 1 Collector Tin',
    weight = 300,
    stack = true,
    close = true,
    description = '4 boosters + 1 limited card',
    server = { export = 'as-tradingcards.useItem' },
},
