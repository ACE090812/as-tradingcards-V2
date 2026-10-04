Config = {}

Config.Debug = false

--[[ ---------------------------------------------------------------------------
    FRAMEWORK / INVENTORY / TARGET
    'auto' detects in this order:
      Framework : qbx_core -> qb-core -> es_extended
      Inventory : ox_inventory -> qb-inventory (also ps-/lj-inventory via QBCore player functions)
      Target    : ox_target -> qb-target -> 'textui' (ox_lib [E] prompt)
    ESX needs ox_inventory (the default ESX inventory has no item metadata).
--------------------------------------------------------------------------- ]]
Config.Framework = 'auto'   -- 'auto' | 'qbx' | 'qb' | 'esx'
Config.Inventory = 'auto'   -- 'auto' | 'ox' | 'qb'
Config.Target    = 'auto'   -- 'auto' | 'ox' | 'qb' | 'textui'

-- qb-inventory only: fallback slot count if it can't be read from the inventory
Config.QBMaxSlots = 41
-- qb-inventory only: item box popup event ('qb-inventory:client:ItemBox' on new qb-inventory, 'inventory:client:ItemBox' on old/forks)
Config.QBItemBoxEvent = 'qb-inventory:client:ItemBox'

-- Money account used for buying / grading fees / selling. Cash first, then bank if allowed.
Config.Money = {
    allowBank = true,
    sellPaysTo = 'cash',    -- 'cash' | 'bank'
}

--[[ ---------------------------------------------------------------------------
    ITEMS
--------------------------------------------------------------------------- ]]
Config.Items = {
    slab   = 'ascard_slab',     -- graded card in a PSA slab
    case   = 'ascard_psa',      -- empty grading case (consumed when grading, see Config.Grading.requireCase)
    binder = 'ascard_binder',
}

--[[ ---------------------------------------------------------------------------
    CARD TYPES  (order matters: most common -> rarest)
    item    = inventory item that holds cards of this type (unique, metadata)
    value   = base sell-back price
    frame   = card border (any CSS background)
    plate / plateText / posBg = name strip colours
    effects = sweep (shine colour), speed, glitter (colour), follow (light follows
              the mouse), holo (rainbow), glow (edge glow), dark (dark background)
    glow    = reveal glow colour in the pack opening
    sound   = frontend sound on reveal
--------------------------------------------------------------------------- ]]
Config.Types = {
    {
        id = 'player', label = 'Common', item = 'ascard_player', value = 5,
        frame = '#f4f4f4',
        plate = '#ffffff', plateText = '#121212', posBg = '#121212',
        effects = {},
        glow = '#cfcfcf',
        sound = { name = 'NAV_UP_DOWN', set = 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
    },
    {
        id = 'star', label = 'Uncommon', item = 'ascard_star', value = 20,
        frame = 'linear-gradient(145deg, #7e868e 0%, #eef1f4 35%, #9aa2a9 60%, #ffffff 85%)',
        plate = 'linear-gradient(90deg, #d7dce1, #ffffff 50%, #d7dce1)', plateText = '#121212', posBg = '#1a4fb5',
        effects = { sweep = 'rgba(255,255,255,0.95)', speed = '4.5s' },
        glow = '#dfe6ee',
        sound = { name = 'CHALLENGE_UNLOCKED', set = 'HUD_AWARDS' },
    },
    {
        id = 'captain', label = 'Rare', item = 'ascard_captain', value = 35,
        frame = 'linear-gradient(145deg, #c9a100 0%, #ffe45c 40%, #d9b200 70%, #fff1a0 100%)',
        plate = '#ffd400', plateText = '#121212', posBg = '#121212',
        effects = { sweep = 'rgba(255,240,170,0.95)', speed = '4s' },
        glow = '#ffd400',
        sound = { name = 'CHALLENGE_UNLOCKED', set = 'HUD_AWARDS' },
    },
    {
        id = 'winner', label = 'Epic', item = 'ascard_winner', value = 75,
        frame = 'linear-gradient(145deg, #7a570c 0%, #f7d774 30%, #a87c1a 56%, #fff0b3 80%, #8a6512 100%)',
        plate = 'linear-gradient(90deg, #d9a92f, #ffe9a3 50%, #d9a92f)', plateText = '#1d1606', posBg = '#6b4b06',
        effects = { glitter = '#ffe38a', follow = true, sweep = 'rgba(255,236,160,0.8)', speed = '5.5s' },
        glow = '#ffb13b',
        sound = { name = 'RANK_UP', set = 'HUD_AWARDS' },
    },
    {
        id = 'century', label = 'Legendary', item = 'ascard_century', value = 200,
        frame = 'linear-gradient(135deg, #ff4fa3, #ffd23f 25%, #3fffc2 50%, #3fb8ff 75%, #c43fff)',
        plate = '#111111', plateText = '#ffffff', posBg = '#c43fff',
        effects = { holo = true, glitter = '#ffffff', follow = true },
        glow = '#c43fff',
        sound = { name = 'RANK_UP', set = 'HUD_AWARDS' },
    },
    {
        id = 'legend', label = 'Mythic', item = 'ascard_legend', value = 400,
        frame = 'linear-gradient(145deg, #141414 0%, #d4af37 24%, #0d0d0d 46%, #f5e6a8 66%, #151515 84%, #b8912a 100%)',
        plate = 'linear-gradient(90deg, #111111, #2a2415 50%, #111111)', plateText = '#f5d77a', posBg = '#b8912a',
        effects = { glitter = '#f5d77a', follow = true, sweep = 'rgba(245,215,122,0.9)', speed = '5s', glow = true, dark = true },
        glow = '#f5d77a',
        sound = { name = 'RANK_UP', set = 'HUD_AWARDS' },
    },
}

--[[ ---------------------------------------------------------------------------
    FOIL  (a rainbow + glitter version of any card)
--------------------------------------------------------------------------- ]]
Config.Foil = {
    label = 'Foil',
    valueMultiplier = 3.0,
}

--[[ ---------------------------------------------------------------------------
    NUMBERED PARALLELS
    Any card can drop as a numbered parallel. Each player has their own print run
    per parallel (e.g. only ONE Black Erling Highland will ever exist).
    chance     = chance per card pulled (checked rarest first)
    maxPrints  = how many of that player's parallel can ever exist
    value      = sell-value multiplier
    frame      = card border, stamp = colour of the "RED 03/10" stamp
    effects    = extra effects on top of the card's own (same keys as Config.Types)
    Order: common -> rarest. The binder shows the best version you've put in.
--------------------------------------------------------------------------- ]]
Config.Parallels = {
    {
        id = 'blue', label = 'Blue', maxPrints = 99, chance = 1 / 200, value = 4.0,
        frame = 'linear-gradient(145deg, #0b2a6b 0%, #4f9dff 30%, #123e94 55%, #9fd0ff 80%, #0b2a6b 100%)',
        stamp = '#2f7bff',
        effects = { sweep = 'rgba(160,210,255,0.95)', speed = '4s' },
    },
    {
        id = 'gold', label = 'Gold', maxPrints = 50, chance = 1 / 500, value = 8.0,
        frame = 'linear-gradient(145deg, #7a570c 0%, #ffe07a 28%, #b8860b 52%, #fff4c2 76%, #8a6512 100%)',
        stamp = '#d9a92f',
        effects = { glitter = '#ffe38a', sweep = 'rgba(255,236,160,0.9)', speed = '4.5s', follow = true },
    },
    {
        id = 'red', label = 'Red', maxPrints = 10, chance = 1 / 2500, value = 25.0,
        frame = 'linear-gradient(145deg, #4a0008 0%, #ff3b4a 30%, #8c0010 55%, #ff9aa2 80%, #4a0008 100%)',
        stamp = '#e0202f',
        effects = { glitter = '#ff8a94', sweep = 'rgba(255,170,170,0.9)', speed = '4s', follow = true, pulse = '#ff3b4a' },
    },
    {
        id = 'black', label = 'Black', maxPrints = 1, chance = 1 / 25000, value = 150.0,
        frame = 'linear-gradient(145deg, #000 0%, #3a3a3a 22%, #050505 44%, #d4af37 62%, #0a0a0a 80%, #6b6b6b 100%)',
        stamp = '#111111',
        effects = { holo = true, glitter = '#f5d77a', follow = true, sweep = 'rgba(245,215,122,0.9)', speed = '5s', pulse = '#f5d77a', dark = true },
    },
}

--[[ ---------------------------------------------------------------------------
    PACKS  (key = item name)
    set        = which set's cards can drop (Config.Sets in cards.lua)
    cards      = cards per pack
    weights    = card type roll weights (don't need to add to 100)
    guaranteed = at least `count` cards of `minRarity` type or better
    foilChance = 0.0 - 1.0 per card
--------------------------------------------------------------------------- ]]
Config.Packs = {
    ['ascard_booster_pack1'] = {
        label = 'Series 1 Booster',
        set = 'series1',
        cards = 5,
        weights = { player = 70, star = 18, captain = 6, winner = 4, century = 1.5, legend = 0.5 },
        guaranteed = { count = 1, minRarity = 'star' },
        foilChance = 0.05,
    },
    ['ascard_booster_pack2'] = {
        label = 'Series 1 Mega Booster',
        set = 'series1',
        cards = 10,
        weights = { player = 60, star = 22, captain = 8, winner = 6, century = 2.5, legend = 1.5 },
        guaranteed = { count = 2, minRarity = 'star' },
        foilChance = 0.07,
    },
}

Config.PackOpening = {
    duration = 3000,
    -- true: each card goes into your inventory when you click it over. Leave the screen early
    -- (Done / Esc) and every card you haven't turned over is given to you straight away.
    -- false: all cards go in as soon as the pack is opened.
    giveOnReveal = true,
    giveAllAfter = 120,     -- seconds: safety net, anything not handed out by then is given anyway
    -- booster pack prop in the right hand (streamed prop from stream/)
    anim = { dict = 'mp_arresting', clip = 'a_uncuff', flag = 49 },
    prop = { model = 'prop_boosterpack_01', bone = 57005, pos = vec3(0.1, 0.1, 0.0), rot = vec3(70.0, 10.0, 90.0) },
}

-- Art on the front of the 3D pack you rip open (inside html/, or an https:// URL).
-- A pack can override it with `art = '...'` in Config.Packs.
Config.PackArt = 'img/card_back.jpg'

--[[ ---------------------------------------------------------------------------
    BOOSTER BOX  - use it to get a stack of packs
--------------------------------------------------------------------------- ]]
Config.BoosterBox = {
    enabled = true,
    item = 'ascard_booster_box',
    label = 'Series 1 Booster Box',
    gives = { item = 'ascard_booster_pack1', count = 12 },
    duration = 4000,
    anim = { dict = 'mp_arresting', clip = 'a_uncuff', flag = 49 },
    prop = { model = 'prop_boosterbox_01', bone = 57005, pos = vec3(0.1, 0.1, 0.0), rot = vec3(0.0, 10.0, 90.0) },
}

-- Binder size: pages of 9 sleeves (60 pages = 540 cards)
Config.Binder = { pages = 60 }

-- Deck box held while the binder is open
Config.BinderProp = {
    anim = { dict = 'clothingshirt', clip = 'try_shirt_positive_d', flag = 49 },
    prop = { model = 'prop_deckbox_01', bone = 57005, pos = vec3(0.1, 0.1, 0.0), rot = vec3(0.0, 10.0, 90.0) },
}

--[[ ---------------------------------------------------------------------------
    SOUNDS  (html/sounds/*.ogg, played in the card screen)
--------------------------------------------------------------------------- ]]
Config.Sounds = {
    enabled = true,
    volume = 0.5,
    rip = 'snap',          -- pack top torn off
    deal = 'dealfour',     -- cards dealt out
    flip = 'flip',         -- every card flip
    rare = 'badge',        -- extra sound for these card types (and any foil)
    rareTypes = { 'winner', 'century', 'legend' },
    box = 'boxopen',       -- booster box opened
}

--[[ ---------------------------------------------------------------------------
    VIEWING / SHOWING CARDS
--------------------------------------------------------------------------- ]]
Config.Show = {
    enabled = true,
    radius = 3.0,          -- players within this distance see the card
    duration = 8000,       -- how long it shows on their screen (ms), they keep control
    cooldown = 5,          -- seconds between shows
    anim = { dict = 'paper_1_rcm_alt1-9', clip = 'player_one_dual-9', flag = 49 },
    prop = { model = 'p_ld_id_card_01', bone = 28422, pos = vec3(0.0, 0.0, 0.0), rot = vec3(0.0, 0.0, 0.0) },
}

--[[ ---------------------------------------------------------------------------
    GRADING (PSA)
--------------------------------------------------------------------------- ]]
Config.Grading = {
    enabled = true,
    -- service levels: pick one at the grader
    tiers = {
        { id = 'economy',  label = 'Economy',  fee = 150, time = 120 * 60 },
        { id = 'standard', label = 'Standard', fee = 250, time = 30 * 60 },
        { id = 'express',  label = 'Express',  fee = 750, time = 5 * 60 },
    },
    -- crack a slab to get the raw card back (to resubmit). Small chance the card gets damaged.
    crack = { enabled = true, damageChance = 0.12 },
    fee = 250,
    requireCase = true,        -- consumes one Config.Items.case
    time = 30 * 60,            -- seconds until the graded card can be collected (real time, survives restarts)
    maxPending = 5,            -- max cards a player can have at the grader at once
    -- grade = weight
    weights = { [10] = 4, [9] = 12, [8] = 22, [7] = 22, [6] = 15, [5] = 10, [4] = 7, [3] = 4, [2] = 3, [1] = 1 },
    labels = {
        [10] = 'GEM MT', [9] = 'MINT', [8] = 'NM-MT', [7] = 'NM', [6] = 'EX-MT',
        [5] = 'EX', [4] = 'VG-EX', [3] = 'VG', [2] = 'GOOD', [1] = 'POOR',
    },
    -- sell value multiplier per grade
    multipliers = { [10] = 10.0, [9] = 4.0, [8] = 2.0, [7] = 1.5, [6] = 1.2, [5] = 1.0, [4] = 0.9, [3] = 0.8, [2] = 0.7, [1] = 0.5 },
}

--[[ ---------------------------------------------------------------------------
    SELL-BACK
--------------------------------------------------------------------------- ]]
Config.Buyer = {
    enabled = true,
    -- bonus for low print numbers (e.g. #1-#10 of a limited card)
    lowPrintBonus = { upTo = 10, multiplier = 1.5 },
}

--[[ ---------------------------------------------------------------------------
    PRICING
    A card's bonuses (foil, parallel, hit, error, rookie, grade, low print number)
    don't just multiply together. The biggest bonus counts in full, the next at
    stackDamping strength (0.5 = half), the next at half of that, and so on.
    cap: true = no card is ever worth more than maxValue (shop sell-back and market
    price), false = no limit, a card can be worth any amount.
--------------------------------------------------------------------------- ]]
Config.Pricing = {
    stackDamping = 0.5,     -- 1 = old behaviour (everything multiplies), 0 = only the biggest bonus counts
    cap = false,            -- true = limit card values to maxValue, false = no limit
    maxValue = 250000,      -- the most one card can be worth while cap = true
}

--[[ ---------------------------------------------------------------------------
    SHOP
--------------------------------------------------------------------------- ]]
Config.Shop = {
    label = 'Card Shop',
    items = {
        { item = 'ascard_booster_pack1', price = 10,  label = 'Series 1 Booster (5 cards)' },
        { item = 'ascard_booster_pack2', price = 20,  label = 'Series 1 Mega Booster (10 cards)' },
        { item = 'ascard_booster_box',   price = 100, label = 'Series 1 Booster Box (12 packs)' },
        { item = 'ascard_fat_pack',      price = 15,  label = 'Series 1 Fat Pack (7 cards, 1 foil)' },
        { item = 'ascard_tin',           price = 60,  label = 'Collector Tin (4 packs + limited card)' },
        { item = 'ascard_blaster',       price = 75,  label = 'Blaster Box (6 packs + exclusive)' },
        { item = 'ascard_hobby_box',     price = 400, label = 'Hobby Box (12 hobby packs, 1 guaranteed hit)' },
        { item = 'ascard_psa',           price = 100, label = 'Grading Case' },
        { item = 'ascard_binder',        price = 50,  label = 'Card Binder' },
        { item = 'ascard_sleeve',        price = 1,   label = 'Penny Sleeve' },
        { item = 'ascard_toploader',     price = 3,   label = 'Toploader' },
        { item = 'ascard_cloth',         price = 8,   label = 'Microfibre Cloth (5 uses)' },
        { item = 'ascard_spray',         price = 12,  label = 'Card Cleaner Spray (3 uses)' },
        { item = 'ascard_loupe',         price = 40,  label = 'Magnifier Loupe' },
        { item = 'ascard_scale',         price = 60,  label = 'Digital Pack Scale' },
        { item = 'ascard_slabcase',      price = 75,  label = 'Slab Case (holds 10 slabs)' },
        { item = 'ascard_shrinkwrap',    price = 5,   label = 'Shrink Wrap' },
    },
    maxPerPurchase = 20,
}

--[[ ---------------------------------------------------------------------------
    PEDS  - one ped can do any mix of roles: 'shop', 'grader', 'buyer'
--------------------------------------------------------------------------- ]]
Config.Peds = {
    {
        model = 'u_m_y_pogo_01',
        coords = vec4(-136.68, 229.74, 93.95, 358.07),
        scenario = nil,
        anim = { dict = 'mini@strip_club@idles@bouncer@base', clip = 'base' },
        roles = { 'shop', 'grader', 'buyer' },
        blip = { sprite = 605, colour = 27, scale = 0.7, label = 'Trading Cards' },
    },
}
Config.PedSpawnDistance = 40.0
Config.InteractDistance = 2.0

--[[ ---------------------------------------------------------------------------
    CARD FACE
--------------------------------------------------------------------------- ]]
Config.CardFooter = 'UK CENTRAL'
-- Image for the back of every card (inside html/, or an https:// URL). Best at 600x840 (5:7).
-- Set to false to use the built-in navy pitch design instead.
Config.CardBack = 'img/card_back.jpg'

-- Player photos. The card looks for a photo in this order:
--   1. html/img/players/<cardId>.png / .jpg / .webp  (photos you put in the resource)
--   2. Config.PhotoUrl with {id} swapped for the card id  (photos hosted online)
--   3. a plain silhouette in the club colours
-- Example: 'https://r2.fivemanage.com/yourbucket/cards/{id}.jpg'  or  'https://raw.githubusercontent.com/you/cards/main/{id}.jpg'
-- The card id is the key in config/cards.lua (e.g. highland, rayban, icecake). Leave '' to only use local photos.
Config.PhotoUrl = ''

-- ox_inventory: graded slabs show a picture of their card inside the slab. false = use the plain slab item picture.
Config.SlabPhotoIcon = true
Config.GradingBrand = 'UKC GRADING'

--[[ ---------------------------------------------------------------------------
    ADMIN
--------------------------------------------------------------------------- ]]
Config.AdminAce = 'group.admin'   -- ace used for /givecard, /givepack, /previewcard

--[[ ---------------------------------------------------------------------------
    TEXT
--------------------------------------------------------------------------- ]]
Config.Locale = {
    grading_stolen     = 'This card has been reported stolen - the grader won\'t take it',
    buyer_stolen       = 'This card has been reported stolen - nobody will buy it',
    stolen_reported    = 'Card %s reported stolen',
    stolen_cleared     = 'Card %s marked as recovered',
    stolen_not_owner   = 'That serial isn\'t registered to you',
    stolen_unknown     = 'No card with that serial',
    cracked            = 'You cracked the slab open',
    cracked_damaged    = 'You cracked the slab open - but dinged the card getting it out',
    target_stolen      = 'Report a stolen card',
    -- condition
    need_sleeve        = 'You need a penny sleeve',
    need_toploader     = 'You need a toploader',
    toploader_needs_sleeve = 'Put the card in a penny sleeve first',
    need_cloth         = 'You need a microfibre cloth to clean cards',
    clean_take_out     = 'Take the card out of its sleeve first',
    clean_done         = 'Card cleaned - surface %s',
    target_clean       = 'Clean cards',
    clean_pick         = 'Pick a card to clean',
    nothing_to_clean   = 'You have no loose cards to clean',
    opening_pack       = 'Opening %s...',
    opening_box        = 'Opening %s...',
    box_opened         = 'You got %dx %s',
    cancelled          = 'Cancelled',
    already_busy       = 'You are already doing something',
    no_space           = 'You need %d free inventory slots',
    not_enough_money   = 'You can\'t afford that',
    bought             = 'Bought %dx %s for %s',
    sold               = 'Sold %s for %s',
    nothing_to_sell    = 'You have no cards to sell',
    nothing_to_grade   = 'You have no ungraded cards',
    need_case          = 'You need an empty grading case',
    grading_submitted  = '%s sent for grading. Come back in %s',
    grading_full       = 'You already have %d cards at the grader',
    grading_none       = 'You have nothing waiting at the grader',
    grading_pending    = '%d card(s) still being graded - next ready in %s',
    grading_collected  = 'Collected %d graded card(s)',
    shown_to           = 'You showed your card to %d player(s)',
    nobody_near        = 'Nobody is close enough',
    showing_you        = '%s is showing you a card',
    show_cooldown      = 'Wait a moment before showing again',
    binder_filled      = 'That sleeve already has a card in it',
    binder_full        = 'Your binder is full',
    binder_swapped     = 'Swapped in the better version - the old one is back in your inventory',
    item_missing       = 'That item is no longer in your inventory',
    target_shop        = 'Browse cards',
    target_grade       = 'Submit card for grading',
    target_collect     = 'Collect graded cards',
    target_sell        = 'Sell cards',
    textui             = '[E] %s',
    menu_shop          = 'Card Shop',
    menu_grade         = 'Choose a card to grade',
    menu_sell          = 'Sell cards',
    menu_amount        = 'Amount',
    confirm_grade      = 'Grade %s for £%d%s?',
    confirm_grade_case = ' (uses 1 grading case)',
    confirm_sell       = 'Sell %s for %s?',
}
