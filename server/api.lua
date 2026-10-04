--[[ One set of requests for the phone app and the website.
     Phone:   html/market/phone.html -> NUI 'market' -> lib.callback 'as-tradingcards:server:market'
     Website: html/market/site.html  -> as-browser Site.call -> exports['as-browser']:registerHandler ]]
local RES = GetCurrentResourceName()

local rate = {}   -- [src] = { t, n }
local function allowed(src)
    local now = os.clock()
    local r = rate[src]
    if not r or now - r.t > 3 then rate[src] = { t = now, n = 1 } return true end
    r.n = r.n + 1
    return r.n <= 20
end
AddEventHandler('playerDropped', function() rate[source] = nil end)

local function str(v, max) return tostring(v or ''):sub(1, max or 64) end

local H = {}

H.home = function(src, id)
    local p = Auctions.Prefs(id)
    local lockers = Auctions.Lockers()
    return {
        name = Framework.GetName(src),
        currency = '£',
        types = (function() local t = {} for _, x in ipairs(Config.Types) do t[#t + 1] = { id = x.id, label = x.label } end return t end)(),
        movers = Market.Movers(),
        sealed = Market.SealedList(),
        updatedAt = Market.updatedAt,
        auctions = { enabled = Config.Auctions.enabled, live = (function() local n = 0 for _ in pairs(Auctions.live) do n = n + 1 end return n end)() },
        lockers = lockers, locker = p.locker or (lockers[1] and lockers[1].id) or nil, postal = #lockers > 0,
        account = Config.Auctions.account or 'bank',
        nextRestock = Stock and Stock.NextRestock() or nil,
        drops = Releases and Releases.Summary() or nil,
        maxLot = Config.Auctions.maxLot or 10,
        now = os.time(),
    }
end

H.prices = function(src, id, d) return Market.Search({ search = str(d.search, 40), type = str(d.type, 20), sort = str(d.sort, 10), page = d.page }) end
H.card = function(src, id, d)
    local r, e = Market.CardDetail(str(d.id))
    if r then r.wanted = Wants and Wants.Has(id, r.id) or false end
    return r, e
end
H.want = function(src, id, d) return Wants.Toggle(id, str(d.cardId)) end
H.stats = function(src, id) return Stats.Get(id) end
H.appraise = function(src, id, d) return Appraisal.Order(src, id, d.slot, d.serial and str(d.serial) or nil) end
H.appraisals = function(src, id) return { list = Appraisal.Mine(id), phone = GetResourceState('sd-phone') == 'started', printer = GetResourceState('as-printer') == 'started', computer = GetResourceState('as-computer') == 'started' } end
H.appraisalSaveComputer = function(src, id, d) return Appraisal.SaveToComputer(src, id, d.ref) end
H.appraisalSave = function(src, id, d) return Appraisal.SaveToPhone(src, id, d.ref) end
H.appraisalPrint = function(src, id, d) return Appraisal.Print(src, id, d.ref, d) end
H.appraisable = function(src, id)
    local list = {}
    for _, it in ipairs(Auctions.Sellable(src).items) do if it.kind ~= 'sealed' then list[#list + 1] = it end end
    return { items = list, price = (Config.Appraisal or {}).price or 50, enabled = (Config.Appraisal or {}).enabled }
end
H.wants = function(src, id) return Wants.List(id) end
H.weekly = function() return Community.Weekly() end
H.drops = function(src, id) return Releases.List(id) end
H.dropBuy = function(src, id, d) return Releases.Buy(src, id, str(d.id), d.qty) end
H.offer = function(src, id, d) return Auctions.MakeOffer(src, id, d.id, d.amount) end
H.offerAnswer = function(src, id, d) return Auctions.AnswerOffer(id, d.id, d.accept == true) end
H.rate = function(src, id, d) return Auctions.Rate(id, d.id, d.score, d.comment) end
H.seller = function(src, id, d) return Auctions.Seller(id, d.id) end
H.odds = function() return PackOdds() end

H.checklist = function(src, id) return Market.Checklist(src, id) end
H.portfolio = function(src, id) return Market.Portfolio(src) end
H.pulls = function(src, id) return Market.Pulls(id) end
H.report = function(src, id, d) return Market.SetStolen(id, d.serial, d.stolen == true) end
H.stolen = function(src, id, d) return Market.CheckSerial(d.serial) end
H.seal = function(src, id, d) if not Seals then return nil, "Seal checks are off." end return Seals.Check(d.seal) end

H.alerts = function(src, id) return Market.AlertsFor(id) end
H.alertAdd = function(src, id, d) return Market.AddAlert(id, str(d.cardId), str(d.dir, 8), d.price) end
H.alertDel = function(src, id, d) return Market.DeleteAlert(id, d.id) end

H.auctions = function(src, id, d)
    return Auctions.Browse(id, { search = str(d.search, 40), kind = str(d.kind, 12), sort = str(d.sort, 10), page = d.page, cardId = d.cardId and str(d.cardId) or nil })
end
H.auction = function(src, id, d) return Auctions.Get(id, d.id) end
H.bid = function(src, id, d) return Auctions.Bid(src, id, d.id, d.amount) end
H.buyNow = function(src, id, d) return Auctions.BuyNow(src, id, d.id) end
H.watch = function(src, id, d) return Auctions.ToggleWatch(id, d.id) end
H.mine = function(src, id) return Auctions.Mine(id) end
H.sellable = function(src, id) return Auctions.Sellable(src) end
H.list = function(src, id, d)
    local slots = nil
    if type(d.slots) == 'table' then
        slots = {}
        for i, p in ipairs(d.slots) do
            if i > 20 then break end
            slots[#slots + 1] = { slot = tonumber(type(p) == 'table' and p.slot or p), serial = type(p) == 'table' and p.serial and str(p.serial) or nil }
        end
    end
    return Auctions.Create(src, id, {
        slots = slots, title = d.title and str(d.title, 60) or nil,
        slot = d.slot, serial = d.serial and str(d.serial) or nil, duration = str(d.duration, 8),
        start = d.start, buyNow = d.buyNow, reserve = d.reserve,
    })
end
H.cancel = function(src, id, d) return Auctions.Cancel(id, d.id) end
H.setLocker = function(src, id, d) return Auctions.SetLocker(id, str(d.locker)) end

local needsAuctions = { offer = true, offerAnswer = true, rate = true, seller = true, auctions = true, auction = true, bid = true, buyNow = true, watch = true, mine = true, sellable = true, list = true, cancel = true }

function Market.Handle(src, name, data)
    if not (Config.Market.enabled) then return nil, 'The card market is closed.' end
    if not Market.ready or not Auctions.ready then return nil, 'The card market is starting up. Try again in a moment.' end
    local fn = H[name]
    if not fn then return nil, 'Unknown request.' end
    if needsAuctions[name] and not Config.Auctions.enabled then return nil, 'Auctions are closed.' end
    if not allowed(src) then return nil, 'Slow down a little.' end
    local id = Market.Track(src)
    if not id then return nil, 'No character loaded.' end
    local ok, res, err = pcall(fn, src, id, type(data) == 'table' and data or {})
    if not ok then
        print(('^1[as-tradingcards] market request %s failed: %s^0'):format(tostring(name), tostring(res)))
        return nil, 'Something went wrong. Try again.'
    end
    return res, err
end

-- phone
lib.callback.register('as-tradingcards:server:market', function(src, name, data)
    local res, err = Market.Handle(src, tostring(name or ''), data)
    if res == nil then return { ok = false, error = err or 'Something went wrong.' } end
    return { ok = true, data = res }
end)

--[[ ---------------------------------------------------------------------------
    WEBSITE (as-browser)
--------------------------------------------------------------------------- ]]
local SC = Config.Site or {}

local function registerSite()
    if not SC.enabled or GetResourceState('as-browser') ~= 'started' then return end
    pcall(function() exports['as-browser']:unregisterSite(SC.domain) end)
    local ok, done, err = pcall(function()
        return exports['as-browser']:registerSite({
            domain = SC.domain, title = SC.title, description = SC.description, keywords = SC.keywords,
            category = SC.category, icon = SC.icon, color = SC.color,
            ui = RES .. '/html/market/site.html',
            pages = {
                { path = '/prices', title = 'Price guide', description = 'Every card and what it is worth', keywords = { 'price', 'value' } },
                { path = '/auctions', title = 'Live auctions', description = 'Bid on cards', keywords = { 'auction', 'bid', 'buy' } },
                { path = '/check', title = 'Stolen card check', description = 'Check a serial number', keywords = { 'stolen', 'serial' } },
                { path = '/week', title = 'This week', description = 'Biggest sales and pulls this week', keywords = { 'news', 'week', 'sales', 'pulls' } },
                { path = '/drops', title = 'Release days', description = 'New releases and drops', keywords = { 'release', 'drop', 'launch' } },
                { path = '/odds', title = 'Pack odds', description = 'The odds for every pack and box', keywords = { 'odds', 'chance', 'pull rate' } },
                { path = '/checklist', title = 'Set checklist', description = 'Which cards you have and need', keywords = { 'checklist', 'collection' } },
            },
        })
    end)
    if not ok or not done then
        print(('^3[as-tradingcards] could not add %s to as-browser: %s^0'):format(tostring(SC.domain), tostring(ok and err or done)))
        return
    end
    for name in pairs(H) do
        exports['as-browser']:registerHandler(SC.domain, name, function(src, data)
            local res, e = Market.Handle(src, name, data)
            -- errors travel inside the result (a second return value may not survive the export call)
            if res == nil then return { __error = e or 'Something went wrong.' } end
            return res
        end)
    end
    print(('^2[as-tradingcards] website live at %s^0'):format(SC.domain))
end

CreateThread(function()
    while not (Market.ready and Auctions.ready) do Wait(500) end
    registerSite()
end)
AddEventHandler('onResourceStart', function(res)
    if res == 'as-browser' then SetTimeout(3000, registerSite) end
end)
