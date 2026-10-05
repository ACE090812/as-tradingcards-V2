--[[ ---------------------------------------------------------------------------
    CUSTOM FOLDER (card creator / board creator output), SKINS, HAND PROPS, GIFTS
--------------------------------------------------------------------------- ]]
-- Cards: custom/cards.json (an array of card objects, or { "cards": [...] }). Images go in custom/img/.
-- Mats:  custom/mats.json. Full format in custom/README.txt. Loaded on start (restart the resource to reload).
Config.Custom = {
    enabled = true,
    cardFiles = { 'custom/cards.json' },
    matFiles = { 'custom/mats.json' },
    slabFiles = { 'custom/slabs.json' },   -- custom slab design(s) from the website's Slab Creator (max 2, see Config.SlabDesigns)
    defaultSet = 'series2',        -- set for cards that don't say
    defaultType = 'player',        -- card type for cards that don't say
    defaultClub = nil,             -- club key for cards that don't say (nil = 'unattached')
    imagePrefix = '../custom/img/',

    -- Creator output (paste the Lua the creators give you straight into these files; no editing):
    creatorCardFiles = { 'custom/cards.lua' },        -- Card Creator export
    creatorMatFiles = { 'custom/playmats.lua' },      -- Playmat Creator export. Mat images go in html/img/playmats/
    matImagePrefix = 'img/playmats/',
    -- which set each creator theme goes into. All three start hidden and are released by the "Series 2" switch (once the set has cards).
    creatorSets = { football = 'series2', creatures = 'creatures', lossantos = 'lossantos' },
    creatorRarity = { Common = 'player', Uncommon = 'star', Rare = 'captain', Epic = 'winner', Legendary = 'century', Mythic = 'legend' },
    creatorPos = 'CM',             -- creator cards have no position, so they get this one (position bonuses apply)
    creatorStatScale = 1.0,        -- creator ATK / DEF are multiplied by this (then capped)
    creatorMaxStat = 99,           -- highest ATK or DEF a creator card can have
    creatorNation = nil,           -- e.g. 'ENG' if you want a flag on creator cards
    creatorNumberBase = 7000,      -- card numbers for creator cards count up from here

    -- MULTIPLE SERIES: every card keeps the `set` it was made with in the Card Creator (e.g. set = 'myseries'),
    -- and that becomes its own series. Make a pack for each one with the same set name:
    --   Config.Packs['pack_myseries'] = { label = '...', set = 'myseries', cards = 5, rates = { ... } }
    -- Cards with no set fall back to creatorSets / defaultSet above.
    creatorSetsHidden = false,     -- false = new series are live straight away. true = they wait for /cardadmin > Switches > Series 2
    sets = {                       -- optional: a nice name and 3-letter serial code per series
        -- myseries = { label = 'My Series', code = 'MYS' },
    },

    -- put every custom pack in the card shop automatically
    shop = {
        enabled = true,
        pricePerCard = 3,          -- pack price = cards in the pack x this
        prices = {                 -- or set a price for one pack
            -- pack_myseries = 25,
        },
    },
}

-- BINDER COVERS (4). Pick one on the binder screen. price = 0 means everyone has it, otherwise it is bought at the card shop.
Config.Skins = {
    binders = {
        { id = 'leather',  label = 'Leather Classic', price = 0,   cover = 'linear-gradient(160deg,#6a4327,#3b2413)', edge = '#8a6038', ring = '#e0b671', title = '#f1d6a4', spine = '#2c1a0d' },
        { id = 'pitch',    label = 'Pitch Green',     price = 100, cover = 'linear-gradient(160deg,#1f6b3f,#0f3a22)', edge = '#2f8f58', ring = '#d8f0e0', title = '#e6f7ec', spine = '#0b2916' },
        { id = 'midnight', label = 'Midnight',        price = 100, cover = 'linear-gradient(160deg,#1c2442,#0c1122)', edge = '#34406b', ring = '#f0a832', title = '#f0a832', spine = '#080c18' },
        { id = 'terrace',  label = 'Terrace Red',     price = 150, cover = 'linear-gradient(160deg,#a8322b,#5a1b19)', edge = '#d6584f', ring = '#ffe3df', title = '#fff0ee', spine = '#3a100e' },
    },

    -- SLAB LABEL SKINS (8). Chosen automatically, first match from the top wins.
    -- when: pristine | legend | chase (insert or error) | parallel | foil | rookie | grade10 | grade (min, max)
    slabs = {
        { id = 'pristine', label = 'Pristine',      use = 'All four sub-grades 10',  when = 'pristine', bg = '#101114', fg = '#f6d57a' },
        { id = 'legend',   label = 'Legend edition',use = 'Legend cards only',       when = 'legend',   bg = 'linear-gradient(90deg,#1d1e24,#3a3320)', fg = '#f6d57a' },
        { id = 'chase',    label = 'Chase',         use = 'Autographs, relics, errors', when = 'chase',  bg = 'linear-gradient(90deg,#3a1d44,#1d1030)', fg = '#f4c6ff' },
        { id = 'parallel', label = 'Parallel',      use = 'Numbered parallels',      when = 'parallel', bg = 'linear-gradient(90deg,#0b2a6b,#1c6bd0)', fg = '#e6f1ff' },
        { id = 'gem',      label = 'Gem Mint',      use = 'Grade 10',                when = 'grade10',  bg = '#d8a31f', fg = '#1a1200' },
        { id = 'foil',     label = 'Foil',          use = 'Foil cards',              when = 'foil',     bg = 'linear-gradient(90deg,#d9dde6,#f6f7fb,#c8ccd8)', fg = '#14171f' },
        { id = 'rookie',   label = 'Rookie',        use = 'Rookie cards',            when = 'rookie',   bg = '#2f8f58', fg = '#f1fff6' },
        { id = 'standard', label = 'Standard',      use = 'Grades 1 to 9',           when = 'grade',    bg = '#f2f3f6', fg = '#14171f' },
    },
}

-- CARD IN HAND (use a card > "Hold in hand"). Nearby players see the prop. Flip, show and put away.
Config.HandProp = {
    enabled = true,
    model = 'p_ld_id_card_01',     -- same prop the "show card" action uses; swap for your own card prop
    bone = 28422,                  -- right hand
    pos = vec3(0.0, 0.0, 0.0),
    rot = vec3(0.0, 0.0, 0.0),
    anim = { dict = 'paper_1_rcm_alt1-9', clip = 'player_one_dual-9', flag = 49 },
    flipRot = vec3(0.0, 180.0, 0.0),   -- added to rot when the card is turned over
    showRange = 6.0,               -- "Show" sends the card to people this close
    keys = { flip = 47, show = 74, put = 73 },   -- G, H, X
}

-- GIFTING: send a card as a parcel (Postal Prime) with a message
Config.Gift = {
    enabled = true,
    fee = 0,                       -- cash fee to send a gift
    messageMax = 140,
    sender = 'A friend',           -- shown on the parcel when the sender hides their name
}


--[[ ---------------------------------------------------------------------------
    CARD THEMES (the Card Creator's Football / Creatures / Los Santos switch).
    stats = what ATK / DEF are called on the card face. Everything else is look and filing.
--------------------------------------------------------------------------- ]]
Config.Themes = {
    football = { label = 'Football', stats = { att = 'ATTACK', def = 'DEFENCE' } },
    creatures = {
        label = 'Creatures', stats = { att = 'ATK', def = 'DEF' },
        -- element id = label, colours (used for the club filing and the card colours when the creator doesn't send any)
        elements = {
            ember  = { label = 'Ember',  c1 = '#c4452b', c2 = '#f6b36b' },
            tide   = { label = 'Tide',   c1 = '#2f6fb5', c2 = '#8fd0f0' },
            leaf   = { label = 'Leaf',   c1 = '#3b8a45', c2 = '#b6e08a' },
            volt   = { label = 'Volt',   c1 = '#b89a1d', c2 = '#fff1a0' },
            shade  = { label = 'Shade',  c1 = '#4b3a7a', c2 = '#b9a6e6' },
            stone  = { label = 'Stone',  c1 = '#6f6a60', c2 = '#d6cfc0' },
            frost  = { label = 'Frost',  c1 = '#4aa0b8', c2 = '#e0f6ff' },
            spirit = { label = 'Spirit', c1 = '#a14a8a', c2 = '#f0c2e6' },
        },
        stages = { basic = 'Basic', stage1 = 'Stage 1', stage2 = 'Stage 2', apex = 'Apex' },
    },
    lossantos = {
        label = 'Los Santos', stats = { att = 'CLOUT', def = 'GRIT' },
        categories = { character = 'Character', vehicle = 'Vehicle', landmark = 'Landmark', crew = 'Crew', item = 'Item' },
        districts = {
            vinewood = 'Vinewood', delperro = 'Del Perro', mirrorpark = 'Mirror Park', davis = 'Davis', strawberry = 'Strawberry',
            rockford = 'Rockford Hills', lamesa = 'La Mesa', port = 'Port of Los Santos', sandy = 'Sandy Shores', paleto = 'Paleto Bay',
            grapeseed = 'Grapeseed', blaine = 'Blaine County',
        },
    },
}

-- CUSTOM SLAB DESIGNS (the holder around a graded card). Made in the website's Slab Creator, loaded from custom/slabs.json.
-- At most TWO designs exist:
--   server   = used for every card graded at the NPC grader (replaces the default slab look)
--   business = used only for cards graded through the player card shop (Config.CardShop), so the shop has its own brand
-- Leave a slot out and that grading route keeps the default slab. Players can't pick a slab, it follows where the card was graded.
Config.SlabDesigns = {}
