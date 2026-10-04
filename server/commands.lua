lib.addCommand('givecard', {
    help = 'Give a trading card (mints a real serial)',
    restricted = Config.AdminAce,
    params = {
        { name = 'target', type = 'playerId', help = 'Player ID' },
        { name = 'card', type = 'string', help = 'Card id from config/cards.lua' },
        { name = 'foil', type = 'number', help = '1 = foil', optional = true },
        { name = 'parallel', type = 'string', help = 'blue / gold / red / black', optional = true },
    },
}, function(src, args)
    local card = Config.Cards[args.card]
    if args.parallel and not Utils.ParallelById[args.parallel] then return Framework.Notify(src, 'Unknown parallel', 'error') end
    if not card then return Framework.Notify(src, 'Unknown card id', 'error') end
    if DB.IsSoldOut(args.card) then return Framework.Notify(src, 'That card has hit its print limit', 'error') end
    local meta = Cards.Mint(args.card, args.foil == 1, args.parallel)
    if Inventory.AddItem(args.target, Cards.ItemFor(args.card), 1, meta) then
        DB.SetOwner(meta.serial, Framework.GetIdentifier(args.target), args.card)
        if SerialLog then SerialLog.Add(meta.serial, 'admin', 'Given by staff') end
        Framework.Notify(src, ('Gave %s %s'):format(args.target, meta.serial), 'success')
    else
        Framework.Notify(src, 'Could not add item (inventory full?)', 'error')
    end
end)

lib.addCommand('givepack', {
    help = 'Give booster packs',
    restricted = Config.AdminAce,
    params = {
        { name = 'target', type = 'playerId', help = 'Player ID' },
        { name = 'pack', type = 'string', help = 'Pack item name' },
        { name = 'count', type = 'number', help = 'Amount', optional = true },
    },
}, function(src, args)
    if not Config.Packs[args.pack] and not (Config.Boxes or {})[args.pack] then return Framework.Notify(src, 'Unknown pack', 'error') end
    Cards.GivePacks(args.target, args.pack, args.count or 1)
end)

lib.addCommand('previewcard', {
    help = 'Preview how a card looks (no item given)',
    restricted = Config.AdminAce,
    params = {
        { name = 'card', type = 'string', help = 'Card id' },
        { name = 'foil', type = 'number', help = '1 = foil', optional = true },
        { name = 'grade', type = 'number', help = 'Grade 1-10', optional = true },
        { name = 'parallel', type = 'string', help = 'blue / gold / red / black', optional = true },
    },
}, function(src, args)
    if not Config.Cards[args.card] then return Framework.Notify(src, 'Unknown card id', 'error') end
    local meta = {
        cardId = args.card,
        foil = args.foil == 1 or nil,
        parallel = Utils.ParallelById[args.parallel or ''] and args.parallel or nil,
        parPrint = 1,
        serial = 'PREVIEW',
        print = 1,
        grade = args.grade and math.max(1, math.min(10, math.floor(args.grade))) or nil,
        cert = args.grade and '00000000' or nil,
    }
    TriggerClientEvent('as-tradingcards:client:viewCard', src, Utils.BuildDisplay(meta), nil, false)
end)

lib.addCommand('cardprints', {
    help = 'Show print counts for limited cards',
    restricted = Config.AdminAce,
}, function(src)
    for id, card in pairs(Config.Cards) do
        local line = ('%s: %d%s'):format(id, DB.GetPrinted(id), card.maxPrints and ('/' .. card.maxPrints) or '')
        if src == 0 then print(line) else TriggerClientEvent('chat:addMessage', src, { args = { 'as-tradingcards', line } }) end
    end
end)

lib.addCommand('cardparallels', {
    help = 'Show how many numbered parallels of a card are left',
    restricted = Config.AdminAce,
    params = { { name = 'card', type = 'string', help = 'Card id' } },
}, function(src, args)
    if not Config.Cards[args.card] then return Framework.Notify(src, 'Unknown card id', 'error') end
    for _, par in ipairs(Config.Parallels) do
        local line = ('%s %s: %d/%d printed'):format(args.card, par.label, DB.GetPrinted(DB.ParallelKey(args.card, par.id)), par.maxPrints)
        if src == 0 then print(line) else TriggerClientEvent('chat:addMessage', src, { args = { 'as-tradingcards', line } }) end
    end
end)
