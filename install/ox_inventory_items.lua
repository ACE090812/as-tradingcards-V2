-- Add to ox_inventory/data/items.lua  (replace the old ascard_* entries)
-- IMPORTANT: 'as-tradingcards' below must match this resource's folder name.
-- If you rename the folder, change it in every `export` line.
-- Item images: put ascard_*.png in ox_inventory/web/images/

['ascard_booster_pack1'] = {
    label = 'Series 1 Booster',
    weight = 20,
    stack = true,
    close = true,
    description = 'Contains 5 trading cards',
    server = { export = 'as-tradingcards.useItem' },
},

['ascard_booster_pack2'] = {
    label = 'Series 1 Mega Booster',
    weight = 35,
    stack = true,
    close = true,
    description = 'Contains 10 trading cards',
    server = { export = 'as-tradingcards.useItem' },
},

['ascard_booster_box'] = {
    label = 'Series 1 Booster Box',
    weight = 300,
    stack = true,
    close = true,
    description = 'Contains 12 booster packs',
    server = { export = 'as-tradingcards.useItem' },
},

['ascard_player'] = {
    label = 'Common Card',
    weight = 1,
    stack = false,
    close = true,
    server = { export = 'as-tradingcards.useItem' },
},

['ascard_star'] = {
    label = 'Uncommon Card',
    weight = 1,
    stack = false,
    close = true,
    server = { export = 'as-tradingcards.useItem' },
},

['ascard_captain'] = {
    label = 'Rare Card',
    weight = 1,
    stack = false,
    close = true,
    server = { export = 'as-tradingcards.useItem' },
},

['ascard_winner'] = {
    label = 'Epic Card',
    weight = 1,
    stack = false,
    close = true,
    server = { export = 'as-tradingcards.useItem' },
},

['ascard_century'] = {
    label = 'Legendary Card',
    weight = 1,
    stack = false,
    close = true,
    server = { export = 'as-tradingcards.useItem' },
},

['ascard_legend'] = {
    label = 'Mythic Card',
    weight = 1,
    stack = false,
    close = true,
    server = { export = 'as-tradingcards.useItem' },
},

['ascard_slab'] = {
    label = 'Graded Card',
    weight = 60,
    stack = false,
    close = true,
    description = 'A professionally graded card in a sealed case',
    server = { export = 'as-tradingcards.useItem' },
},

['ascard_psa'] = {
    label = 'Grading Case',
    weight = 50,
    stack = true,
    close = true,
    description = 'Hand this in with a card at the grader',
},

['ascard_binder'] = {
    label = 'Card Binder',
    weight = 250,
    stack = false,
    close = true,
    description = 'Track your collection',
    server = { export = 'as-tradingcards.useItem' },
    buttons = { { label = 'Rename', action = function(slot) exports['as-tradingcards']:renameItem(slot) end } },
},

-- card condition
['ascard_sleeve'] = {
    label = 'Penny Sleeve',
    weight = 1,
    stack = true,
    close = true,
    description = 'Protects a card from dust, fingerprints, scratches and water',
},

['ascard_toploader'] = {
    label = 'Toploader',
    weight = 10,
    stack = true,
    close = true,
    description = 'Rigid case for a sleeved card - stops corner and edge damage',
},

['ascard_loupe'] = {
    label = 'Magnifier Loupe',
    weight = 50,
    stack = false,
    close = true,
    description = 'Inspect a card for the smallest flaws',
},

['ascard_cloth'] = {
    label = 'Microfibre Cloth',
    weight = 10,
    stack = false,
    close = true,
    description = 'Wipes dust and fingerprints off cards (use at a cleaning bench)',
},

['ascard_spray'] = {
    label = 'Card Cleaner Spray',
    weight = 100,
    stack = false,
    close = true,
    description = 'Lifts dirt and stains off cards (use at a cleaning bench)',
},

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
