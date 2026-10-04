-- Server-side framework bridge: QBX / QBCore / ESX
Framework = { name = nil }

local QBCore, ESX

local function started(res) return GetResourceState(res) == 'started' end

local function detect()
    local cfg = Config.Framework
    if cfg == 'qbx' or (cfg == 'auto' and started('qbx_core')) then return 'qbx' end
    if cfg == 'qb' or (cfg == 'auto' and started('qb-core')) then return 'qb' end
    if cfg == 'esx' or (cfg == 'auto' and started('es_extended')) then return 'esx' end
end

Framework.name = detect()

if Framework.name == 'qb' then
    QBCore = exports['qb-core']:GetCoreObject()
elseif Framework.name == 'esx' then
    ESX = exports.es_extended:getSharedObject()
elseif not Framework.name then
    print('^1[as-tradingcards] No supported framework found (qbx_core / qb-core / es_extended)^0')
end

print(('^2[as-tradingcards] framework: %s^0'):format(tostring(Framework.name)))

function Framework.GetPlayer(src)
    if Framework.name == 'qbx' then return exports.qbx_core:GetPlayer(src) end
    if Framework.name == 'qb' then return QBCore.Functions.GetPlayer(src) end
    if Framework.name == 'esx' then return ESX.GetPlayerFromId(src) end
end

function Framework.GetIdentifier(src)
    local p = Framework.GetPlayer(src)
    if not p then return nil end
    if Framework.name == 'esx' then return p.identifier end
    return p.PlayerData.citizenid
end

function Framework.GetName(src)
    local p = Framework.GetPlayer(src)
    if not p then return GetPlayerName(src) end
    if Framework.name == 'esx' then return p.getName() end
    local ci = p.PlayerData.charinfo
    return ci and ('%s %s'):format(ci.firstname, ci.lastname) or GetPlayerName(src)
end

-- account: 'cash' | 'bank'
function Framework.GetMoney(src, account)
    local p = Framework.GetPlayer(src)
    if not p then return 0 end
    if Framework.name == 'esx' then
        local acc = p.getAccount(account == 'cash' and 'money' or 'bank')
        return acc and acc.money or 0
    end
    return p.PlayerData.money[account] or 0
end

function Framework.RemoveMoney(src, account, amount, reason)
    local p = Framework.GetPlayer(src)
    if not p then return false end
    if Framework.name == 'esx' then
        local accName = account == 'cash' and 'money' or 'bank'
        local acc = p.getAccount(accName)
        if not acc or acc.money < amount then return false end
        p.removeAccountMoney(accName, amount, reason)
        return true
    end
    return p.Functions.RemoveMoney(account, amount, reason) and true or false
end

function Framework.AddMoney(src, account, amount, reason)
    local p = Framework.GetPlayer(src)
    if not p then return false end
    if Framework.name == 'esx' then
        p.addAccountMoney(account == 'cash' and 'money' or 'bank', amount, reason)
        return true
    end
    return p.Functions.AddMoney(account, amount, reason) and true or false
end

-- Takes from cash first, then bank if Config.Money.allowBank
function Framework.Charge(src, amount, reason)
    if amount <= 0 then return true end
    if Framework.GetMoney(src, 'cash') >= amount then
        return Framework.RemoveMoney(src, 'cash', amount, reason)
    end
    if Config.Money.allowBank and Framework.GetMoney(src, 'bank') >= amount then
        return Framework.RemoveMoney(src, 'bank', amount, reason)
    end
    return false
end

-- Normalises usable item callbacks to handler(src, { name, slot, metadata })
local function normaliseItem(name, a, b)
    local item = type(a) == 'table' and a or (type(b) == 'table' and b) or {}
    return {
        name = item.name or name,
        slot = item.slot,
        metadata = item.metadata or item.info or {},
    }
end

function Framework.RegisterUsableItem(name, handler)
    if Framework.name == 'qbx' then
        exports.qbx_core:CreateUseableItem(name, function(src, a, b) handler(src, normaliseItem(name, a, b)) end)
    elseif Framework.name == 'qb' then
        QBCore.Functions.CreateUseableItem(name, function(src, a, b) handler(src, normaliseItem(name, a, b)) end)
    elseif Framework.name == 'esx' then
        ESX.RegisterUsableItem(name, function(src, a, b) handler(src, normaliseItem(name, a, b)) end)
    end
end

function Framework.Notify(src, msg, typ)
    TriggerClientEvent('ox_lib:notify', src, { description = msg, type = typ or 'inform' })
end

function Framework.IsAdmin(src)
    return IsPlayerAceAllowed(src, Config.AdminAce) or IsPlayerAceAllowed(src, 'command')
end

-- Used by the qb inventory bridge
function Framework.GetQBCore() return QBCore end

-- { name, grade (level number), onduty } for the player's job
function Framework.GetJob(src)
    local p = Framework.GetPlayer(src)
    if not p then return nil end
    if Framework.name == 'esx' then
        local j = p.job or (p.getJob and p.getJob()) or {}
        return { name = j.name, grade = tonumber(j.grade) or 0, onduty = (Config.CardShop or {}).esxAlwaysOnDuty ~= false }
    end
    local j = p.PlayerData.job or {}
    local g = j.grade
    return { name = j.name, grade = type(g) == 'table' and tonumber(g.level) or tonumber(g) or 0, onduty = j.onduty == true }
end

-- give a bank / cash amount to an offline-safe identifier is not supported: online players only
function Framework.GetSourceByIdentifier(identifier)
    for _, s in ipairs(GetPlayers()) do
        s = tonumber(s)
        if Framework.GetIdentifier(s) == identifier then return s end
    end
end
