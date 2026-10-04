--[[ ---------------------------------------------------------------------------
    ADMIN PANEL, MONEY LOGS, SEALED BOXES, SUN & DAMP DAMAGE, SHOP HOURS
--------------------------------------------------------------------------- ]]

-- /cardadmin (needs Config.AdminAce): economy stats, give cards / packs, pause things, auctions, repack pool, logs
Config.Admin = { enabled = true, command = 'cardadmin' }

-- Money logs: every money movement in the card economy goes to the ascard_money_log table.
-- Big ones also go to Discord:  set ascard_log_webhook "https://discord.com/api/webhooks/..."
Config.MoneyLogs = {
    enabled = true,
    keepDays = 60,
    discord = {
        enabled = true,
        minAmount = 2500,       -- only movements this big or bigger are posted
        username = 'Card Economy Log',
    },
    -- flag a player who sells this much to the card shop within `minutes` (possible dupe / exploit)
    watch = { sellBackTotal = 25000, minutes = 30 },
}

-- Sealed boxes: every factory box (hobby, blaster, tin, booster box) gets a seal number that can be
-- checked on the website / app. Shrink wrap (`ascard_shrinkwrap`) lets anyone reseal packs into a box.
-- It looks the same in the inventory, but a seal check shows it isn't factory sealed.
Config.Seals = {
    enabled = true,
    shrinkwrap = 'ascard_shrinkwrap',
    allowReseal = true,
}

-- Sun and damp: raw cards left in a vehicle (glovebox / boot) or on the ground fade and can warp.
-- Worked out when the card is taken back out, from how long it was left there.
Config.Weather = {
    enabled = true,
    places = {
        glovebox = { safeHours = 2,   fadePerHour = 0.04, warpPerHour = 0.02 },   -- sun through the windscreen
        trunk    = { safeHours = 4,   fadePerHour = 0.00, warpPerHour = 0.03 },   -- dark but damp
        drop     = { safeHours = 0.5, fadePerHour = 0.08, warpPerHour = 0.05 },   -- out on the ground
    },
    maxFade = 0.85,
    sleeve = 0.5,               -- a penny sleeve halves the damage
    toploader = 0.0,            -- a toploader stops it (graded slabs are always safe)
}

-- Card shop opening hours (the shop, grader and buyer NPCs). The website, phone app and auctions stay open.
-- clock: 'server' = real time on the server, 'game' = the in-game clock
Config.ShopHours = {
    enabled = true,
    clock = 'server',
    open = 9,                   -- 09:00
    close = 23,                 -- 23:00 (close < open = open past midnight)
    closedDays = {},            -- e.g. { 0 } = closed on Sundays (0 = Sunday ... 6 = Saturday)
}
