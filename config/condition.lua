--[[ ---------------------------------------------------------------------------
    CARD CONDITION
    Every card has four scores (centering, corners, edges, surface) plus a list of
    issues. Loose cards wear while carried, sleeves / toploaders protect them,
    dirt can be cleaned at a cleaning bench, and grading uses the real condition.
--------------------------------------------------------------------------- ]]
Config.Condition = {
    enabled = true,

    -- items
    items = {
        sleeve    = 'ascard_sleeve',     -- penny sleeve: stops dust, fingerprints, scratches, water
        toploader = 'ascard_toploader',  -- rigid case (needs a sleeve first): also stops corners, edges, creases
        loupe     = 'ascard_loupe',      -- magnifier: see every flaw and the exact scores
        cloth     = 'ascard_cloth',      -- microfibre cloth: dust + fingerprints
        spray     = 'ascard_spray',      -- card cleaner spray: dirt + stains (spray, then wipe)
    },
    clothUses = 5,   -- cleaning sessions per cloth
    sprayUses = 3,   -- cleaning sessions per bottle (only used up if you actually spray)

    -- straight out of the pack
    factory = {
        centering = { min = 6.5, max = 10.0, bias = 2.2 },  -- bias > 1 = most cards well centred
        printLineChance = 0.05,
        dingChance = 0.02,
    },

    -- wear while carried (checked every `interval` seconds for every online player)
    wear = {
        interval = 300,
        loose = {      -- no protection
            dust = 0.18,            -- amount added (0-1)
            scratchChance = 0.07,
            dingChance = 0.03,
            whitenChance = 0.08,  whiten = 0.08,
            creaseChance = 0.004,
        },
        sleeve = {     -- penny sleeve only
            dingChance = 0.015,
            whitenChance = 0.04,  whiten = 0.05,
            creaseChance = 0.002,
        },
        -- toploader = no wear
        handleFingerprintChance = 0.35,  -- viewing / showing a loose card
        handleFingerprint = 0.3,
        swimWaterChance = 0.6,           -- per check while swimming with loose cards
        rainWaterChance = 0.04,          -- per check while out in heavy rain
        waterCheck = 20,                 -- seconds between water checks
        dropDingChance = 0.35,           -- dropping a loose card on the floor
        dropCreaseChance = 0.03,
    },

    -- the cleaning bench (in the card shop)
    benches = {
        {
            coords = vec4(-135.40, 231.10, 93.95, 90.0),  -- CHANGE ME: stand where the desk should be, use /cardbenchpos
            desk = true,                                   -- false = use furniture that is already there (only the mat + lamp spawn)
        },
    },
    -- first model that exists is used; the table-top height is measured from it
    deskModels = { 'prop_table_03', 'prop_table_04', 'prop_ven_market_table1', 'bkr_prop_weed_table_01a', 'v_corp_offdesk' },
    matModels  = { 'prop_mouse_pad_01', 'prop_cs_mouse_pad' },
    lampModels = { 'v_res_d_lampa', 'prop_cs_lamp_01', 'v_ilev_fh_lampa_on' },
    deskHeight = 0.79,            -- only used when desk = false (your own furniture): table top height above the floor
    cardLift = 0.008,             -- card height above the table top (mat thickness)

    camera = { height = 0.30, minHeight = 0.12, maxHeight = 0.50, fov = 34.0 },
    anim = { dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', clip = 'machinic_loop_mechandplayer' },
}
