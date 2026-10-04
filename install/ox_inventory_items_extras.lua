-- Pack scale and slab case: add to ox_inventory/data/items.lua

['ascard_scale'] = {
    label = 'Digital Pack Scale',
    weight = 400,
    stack = false,
    close = true,
    description = 'Weigh sealed packs. The heavy ones might hold a hit.',
    server = { export = 'as-tradingcards.useItem' },
},

['ascard_slabcase'] = {
    label = 'Slab Case',
    weight = 600,
    stack = false,
    close = true,
    description = 'Holds 10 graded slabs',
    server = { export = 'as-tradingcards.useItem' },
    buttons = { { label = 'Rename', action = function(slot) exports['as-tradingcards']:renameItem(slot) end } },
},

['ascard_appraisal'] = {
    label = 'Appraisal Letter',
    weight = 10,
    stack = false,
    close = true,
    description = 'An official card appraisal',
    server = { export = 'as-tradingcards.useItem' },
},

['ascard_shrinkwrap'] = {
    label = 'Shrink Wrap',
    weight = 50,
    stack = true,
    close = true,
    description = 'Wrap loose packs back into a box. It won’t pass a seal check.',
    server = { export = 'as-tradingcards.useItem' },
},
