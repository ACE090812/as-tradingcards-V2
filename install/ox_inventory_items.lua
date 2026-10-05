-- Add to ox_inventory/data/items.lua  (replace the old ascard_* entries)
-- Folder name used in every export below: as-tradingcards-V2  (must match your resource folder exactly)
-- Item images: put ascard_*.png in ox_inventory/web/images/

-- custom ACE Studios pack
['acestudios'] = {
    label = 'ACE Studios',
    weight = 10,
    stack = false,
    close = true,
    description = 'Common trading card',
    server = { export = 'as-tradingcards-V2.useItem' },
},

-- One item per custom pack. Copy this block for each new series pack, change the key and label.
-- The key must match the pack name in custom/cards.lua (Config.Packs['pack_xxx']).
['pack_acestudios'] = {
    label = 'ACE STUDIOS Test Pack',
    weight = 50,
    stack = true,
    close = true,
    description = 'Opens 5 cards',
    server = { export = 'as-tradingcards-V2.useItem' },
},

['ascard_player'] = {
    label = 'Common Card',
    weight = 1,
    stack = false,
    close = true,
    server = { export = 'as-tradingcards-V2.useItem' },
},

['ascard_star'] = {
    label = 'Uncommon Card',
    weight = 1,
    stack = false,
    close = true,
    server = { export = 'as-tradingcards-V2.useItem' },
},

['ascard_captain'] = {
    label = 'Rare Card',
    weight = 1,
    stack = false,
    close = true,
    server = { export = 'as-tradingcards-V2.useItem' },
},

['ascard_winner'] = {
    label = 'Epic Card',
    weight = 1,
    stack = false,
    close = true,
    server = { export = 'as-tradingcards-V2.useItem' },
},

['ascard_century'] = {
    label = 'Legendary Card',
    weight = 1,
    stack = false,
    close = true,
    server = { export = 'as-tradingcards-V2.useItem' },
},

['ascard_legend'] = {
    label = 'Mythic Card',
    weight = 1,
    stack = false,
    close = true,
    server = { export = 'as-tradingcards-V2.useItem' },
},

['ascard_slab'] = {
    label = 'Graded Card',
    weight = 60,
    stack = false,
    close = true,
    description = 'A professionally graded card in a sealed case',
    server = { export = 'as-tradingcards-V2.useItem' },
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
    server = { export = 'as-tradingcards-V2.useItem' },
    buttons = { { label = 'Rename', action = function(slot) exports['as-tradingcards-V2']:renameItem(slot) end } },
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
    server = { export = 'as-tradingcards-V2.useItem' },
},

['ascard_slabcase'] = {
    label = 'Slab Case',
    weight = 600,
    stack = false,
    close = true,
    description = 'Holds 10 graded slabs',
    server = { export = 'as-tradingcards-V2.useItem' },
    buttons = { { label = 'Rename', action = function(slot) exports['as-tradingcards-V2']:renameItem(slot) end } },
},

['ascard_appraisal'] = {
    label = 'Appraisal Letter',
    weight = 10,
    stack = false,
    close = true,
    description = 'An official card appraisal',
    server = { export = 'as-tradingcards-V2.useItem' },
},

['ascard_shrinkwrap'] = {
    label = 'Shrink Wrap',
    weight = 50,
    stack = true,
    close = true,
    description = 'Wrap loose packs back into a box. It won’t pass a seal check.',
    server = { export = 'as-tradingcards-V2.useItem' },
},

-- Battle items (deck box and battle table)
['ascard_deckbox'] = {
    label = 'Deck Box',
    weight = 150,
    stack = false,
    close = true,
    description = 'Holds a 30 card battle deck',
    server = { export = 'as-tradingcards-V2.useItem' },
},

['ascard_table'] = {
    label = 'Card Battle Table',
    weight = 2500,
    stack = false,
    close = true,
    description = 'A foldable table for card battles. Place it down, battle, pick it up.',
    server = { export = 'as-tradingcards-V2.useItem' },
},
