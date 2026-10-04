-- Card condition items: add these to ox_inventory/data/items.lua (next to your other ascard_* items)
-- Images are already in ox_inventory/web/images
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
