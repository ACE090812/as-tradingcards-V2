--[[ Shop till. Talks to your banking / society resource when it can, otherwise keeps a balance in the database.
     Society.Balance(), Society.Add(amount, reason), Society.Remove(amount, reason) -> bool ]]
Society = { mode = 'internal' }
local SC = (Config.CardShop or {}).society or {}
local ACCOUNT = SC.account or ((Config.CardShop or {}).job or 'cardshop')

local function started(r) return GetResourceState(r) == 'started' end

local drivers = {
    ['Renewed-Banking'] = {
        balance = function() return exports['Renewed-Banking']:getAccountMoney(ACCOUNT) end,
        add = function(a, r) return exports['Renewed-Banking']:addAccountMoney(ACCOUNT, a) end,
        remove = function(a, r) return exports['Renewed-Banking']:removeAccountMoney(ACCOUNT, a) end,
    },
    ['qb-banking'] = {
        balance = function() return exports['qb-banking']:GetAccountBalance(ACCOUNT) end,
        add = function(a, r) return exports['qb-banking']:AddMoney(ACCOUNT, a, r) end,
        remove = function(a, r) return exports['qb-banking']:RemoveMoney(ACCOUNT, a, r) end,
    },
    ['okokBanking'] = {
        balance = function() return exports['okokBanking']:GetAccount(ACCOUNT) end,
        add = function(a, r) return exports['okokBanking']:AddMoney(ACCOUNT, a) end,
        remove = function(a, r) return exports['okokBanking']:RemoveMoney(ACCOUNT, a) end,
    },
    ['qbx_management'] = {
        balance = function() return exports.qbx_management:GetAccount(ACCOUNT) end,
        add = function(a, r) return exports.qbx_management:AddMoney(ACCOUNT, a) end,
        remove = function(a, r) return exports.qbx_management:RemoveMoney(ACCOUNT, a) end,
    },
}

local driver
local function pick()
    local want = SC.resource or 'auto'
    if want == 'internal' then return nil end
    if want ~= 'auto' then return started(want) and drivers[want] and want or nil end
    for _, name in ipairs({ 'Renewed-Banking', 'qb-banking', 'okokBanking', 'qbx_management' }) do
        if started(name) then return name end
    end
end

CreateThread(function()
    Wait(1500)
    local name = pick()
    if name then Society.mode, driver = name, drivers[name] end
    print(('^2[as-tradingcards] card shop till: %s (account "%s")^0'):format(Society.mode, ACCOUNT))
end)

local function internalBalance()
    local row = MySQL.single.await('SELECT balance FROM ascard_shop_till WHERE account = ?', { ACCOUNT })
    return row and tonumber(row.balance) or 0
end

function Society.Balance()
    if driver then
        local ok, v = pcall(driver.balance)
        if ok and tonumber(v) then return math.floor(tonumber(v)) end
        if type(v) == 'table' then return math.floor(tonumber(v.money or v.balance or v.account_balance) or 0) end
        return 0
    end
    return internalBalance()
end

function Society.Add(amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return true end
    if driver then
        local ok, res = pcall(driver.add, amount, reason or 'ascard')
        return ok and res ~= false
    end
    MySQL.query.await('INSERT INTO ascard_shop_till (account, balance) VALUES (?, ?) ON DUPLICATE KEY UPDATE balance = balance + VALUES(balance)', { ACCOUNT, amount })
    return true
end

function Society.Remove(amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return true end
    if driver then
        if Society.Balance() < amount then return false end
        local ok, res = pcall(driver.remove, amount, reason or 'ascard')
        return ok and res ~= false
    end
    local n = MySQL.update.await('UPDATE ascard_shop_till SET balance = balance - ? WHERE account = ? AND balance >= ?', { amount, ACCOUNT, amount })
    return (n or 0) > 0
end
