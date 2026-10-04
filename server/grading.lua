local function rollGrade()
    return tonumber(Utils.WeightedPick(Config.Grading.weights)) or 5
end

local function newCert()
    return ('%08d'):format(math.random(0, 99999999))
end

lib.callback.register('as-tradingcards:server:getGradable', function(src)
    if not Config.Grading.enabled or not IsNearRole(src, 'grader') then return nil end
    if Cardshop and Cardshop.Staffed and Cardshop.Staffed() then
        Framework.Notify(src, 'The shop is staffed. Ask a member of staff to send cards for grading.', 'inform')
        return nil
    end
    local list = {}
    for _, item in ipairs(Inventory.GetItems(src, Utils.IsCardItem)) do
        list[#list + 1] = {
            slot = item.slot,
            serial = item.metadata.serial,
            title = Utils.CardTitle(item.metadata, item.name),
            rarity = Utils.BuildDisplay(item.metadata, item.name).rarity.label,
        }
    end
    return {
        cards = list,
        fee = Config.Grading.fee,
        requireCase = Config.Grading.requireCase,
        time = Utils.FormatTime(Config.Grading.time),
        tiers = (function()
            local t = {}
            for i, tier in ipairs(Config.Grading.tiers or {}) do t[i] = { id = tier.id, label = tier.label, fee = tier.fee, time = Utils.FormatTime(tier.time) } end
            return t
        end)(),
    }
end)

local function tierById(id)
    for _, t in ipairs(Config.Grading.tiers or {}) do if t.id == id then return t end end
    return { id = 'standard', label = 'Standard', fee = Config.Grading.fee, time = Config.Grading.time }
end

Grading = Grading or {}

-- Does the whole submission. Returns true, fee  or  false, message. (Used by the NPC grader and by shop staff.)
function Grading.Submit(src, slot, serial, tierId, viaShop)
    local tier = tierById(tierId)
    if not Config.Grading.enabled then return false, 'Grading is off.' end
    local identifier = Framework.GetIdentifier(src)
    if not identifier then return false, L('item_missing') end

    local item = GetVerifiedCollectible(src, slot, serial)
    if not item or not Utils.IsCardItem(item.name) then return false, L('item_missing') end
    if DB.IsStolen(item.metadata.serial) then return false, L('grading_stolen') end
    if #DB.GetGrading(identifier) >= Config.Grading.maxPending then return false, L('grading_full', Config.Grading.maxPending) end
    if Config.Grading.requireCase and Inventory.Count(src, Config.Items.case) < 1 then return false, L('need_case') end
    if not Framework.Charge(src, tier.fee, 'ascard-grading') then return false, L('not_enough_money') end

    if not Inventory.RemoveItem(src, item.name, 1, item.slot, Inventory.name == 'ox' and item.metadata or nil) then
        Framework.AddMoney(src, 'cash', tier.fee, 'ascard-grading-refund')
        return false, L('item_missing')
    end
    if Config.Grading.requireCase then Inventory.RemoveItem(src, Config.Items.case, 1) end

    local meta = item.metadata
    DB.Seen(src, meta)
    meta.rank = meta.rank or Utils.CardItems[item.name]
    meta.tier = tier.id
    meta.slabBy = viaShop and 'business' or 'server'   -- which custom slab design this card gets (Config.SlabDesigns)
    DB.AddGrading(identifier, item.name, meta, os.time() + tier.time)
    if MoneyLog then MoneyLog.Add(src, 'grading', -tier.fee, ('%s (%s)%s'):format(Utils.CardTitle(meta, item.name), meta.serial or '?', viaShop and ' via the player shop' or '')) end
    if SerialLog then SerialLog.Add(meta.serial, 'submitted', ('Sent for grading (%s)'):format(tier.label or tier.id)) end
    Framework.Notify(src, L('grading_submitted', Utils.CardTitle(meta, item.name), Utils.FormatTime(tier.time)), 'success')
    return true, tier.fee
end

lib.callback.register('as-tradingcards:server:submitGrading', function(src, slot, serial, tierId)
    if not Config.Grading.enabled or not IsNearRole(src, 'grader') then return false end
    if Cardshop and Cardshop.Staffed and Cardshop.Staffed() then
        Framework.Notify(src, 'Ask a member of staff to send it off for you.', 'inform')
        return false
    end
    local ok, msg = Grading.Submit(src, slot, serial, tierId)
    if not ok and msg then Framework.Notify(src, msg, 'error') end
    return ok
end)

lib.callback.register('as-tradingcards:server:collectGrading', function(src)
    if not Config.Grading.enabled or not IsNearRole(src, 'grader') then return false end
    local identifier = Framework.GetIdentifier(src)
    if not identifier then return false end

    local rows = DB.GetGrading(identifier)
    if #rows == 0 then
        Framework.Notify(src, L('grading_none'), 'error')
        return false
    end

    local now, collected, pending, nextReady = os.time(), 0, 0, nil
    local reveal = {}

    for _, row in ipairs(rows) do
        if row.ready_at <= now then
            if Inventory.FreeSlots(src) < 1 then
                Framework.Notify(src, L('no_space', 1), 'error')
                break
            end
            if DB.MarkCollected(row.id) then
                local meta = json.decode(row.metadata) or {}
                local grade
                if Config.Condition and Config.Condition.enabled then
                    Condition.Ensure(meta)
                    local sc
                    grade, sc = Condition.Grade(meta.cond)
                    meta.sub = { cen = sc.centering, cor = sc.corners, edg = sc.edges, sur = sc.surface }
                    meta.prot = nil -- the grader takes it out of any sleeve before slabbing
                else
                    grade = rollGrade()
                end
                meta.grade = grade
                meta.pristine = nil
                local pc = Config.Pristine
                if pc and pc.enabled and grade == 10 and meta.sub and meta.sub.cen == 10 and meta.sub.cor == 10 and meta.sub.edg == 10 and meta.sub.sur == 10 then
                    meta.pristine = true
                end
                meta.cert = newCert()
                meta.gradedFrom = row.item
                local title = Utils.CardTitle(meta, row.item)
                meta.label = ('%s %d %s'):format(meta.pristine and 'Pristine' or 'Graded', grade, Utils.BuildDisplay(meta, row.item).label)
                meta.description = ('%s | %s | Cert %s'):format(title, meta.pristine and Config.Pristine.label or (Config.Grading.labels[grade] or ''), meta.cert)
                if meta.sub then
                    meta.description = meta.description .. (' | CEN %s · COR %s · EDG %s · SUR %s'):format(meta.sub.cen, meta.sub.cor, meta.sub.edg, meta.sub.sur)
                end
                Inventory.AddItem(src, Config.Items.slab, 1, meta)
                collected = collected + 1
                if Pop then Pop.Add(meta) end
                if SerialLog then SerialLog.Add(meta.serial, 'graded', ('Graded %s%d · Cert %s'):format(meta.pristine and 'Pristine ' or '', grade, meta.cert)) end
                reveal[#reveal + 1] = { card = Utils.BuildDisplay(meta, Config.Items.slab), pop = Pop and Pop.For(meta) or nil,
                                        value = Utils.CardValue(meta, Config.Items.slab) }
            end
        else
            pending = pending + 1
            nextReady = nextReady and math.min(nextReady, row.ready_at) or row.ready_at
        end
    end

    if collected > 0 and not (Config.GradeReveal and Config.GradeReveal.enabled) then
        Framework.Notify(src, L('grading_collected', collected), 'success')
    end
    if pending > 0 then
        Framework.Notify(src, L('grading_pending', pending, Utils.FormatTime(nextReady - now)), 'inform')
    end
    if collected > 0 then return { reveal = (Config.GradeReveal and Config.GradeReveal.enabled) and reveal or nil } end
    return false
end)

--[[ crack a slab open -> raw card back (resubmit it for a better grade) ]]
lib.callback.register('as-tradingcards:server:crackSlab', function(src, slot, serial)
    local cc = Config.Grading.crack
    if not cc or not cc.enabled then return false end
    local item = GetVerifiedCollectible(src, slot, serial)
    if not item or item.name ~= Config.Items.slab then return false end
    local meta = item.metadata
    local rawItem = meta.gradedFrom or Cards.ItemFor(meta.cardId)
    if not rawItem then return false end
    if not Inventory.RemoveItem(src, item.name, 1, item.slot, Inventory.name == 'ox' and meta or nil) then return false end
    if SerialLog then SerialLog.Add(meta.serial, 'cracked', ('Slab cracked open (was %s%s · Cert %s)'):format(meta.pristine and 'Pristine ' or 'grade ', tostring(meta.grade), tostring(meta.cert))) end
    meta.pristine = nil

    meta.grade, meta.cert, meta.sub, meta.gradedFrom, meta.tier, meta.slabBy = nil, nil, nil, nil, nil, nil
    if Condition then Condition.Ensure(meta) end
    local damaged = false
    if meta.cond and math.random() < (cc.damageChance or 0) then
        if math.random() < 0.5 then meta.cond.ding = math.min(4, (meta.cond.ding or 0) + 1) else meta.cond.scratch = math.min(8, (meta.cond.scratch or 0) + 1) end
        damaged = true
    end
    meta.label = Utils.BuildDisplay(meta, rawItem).label
    local card = Config.Cards[meta.cardId]
    if card then
        -- rebuild the label the same way minting does
        local t = Utils.CardTitle(meta, rawItem)
        meta.label = t:gsub(' #%d+/?%d*$', '')
    end
    meta.description = Utils.CardDescription and Utils.CardDescription(meta, rawItem) or meta.description
    if CardImages then CardImages.Apply(rawItem, meta) end
    if not Inventory.AddItem(src, rawItem, 1, meta) then
        Framework.Notify(src, L('no_space', 1), 'error')
        return false
    end
    Framework.Notify(src, L(damaged and 'cracked_damaged' or 'cracked'), damaged and 'error' or 'success')
    return true
end)

--[[ stolen card reports (only the player who pulled the card can report / clear it) ]]
lib.callback.register('as-tradingcards:server:myPulls', function(src)
    local id = Framework.GetIdentifier(src)
    if not id then return {} end
    local out = {}
    for _, row in ipairs(DB.OwnedSerials(id)) do
        local card = Config.Cards[row.card_id]
        out[#out + 1] = { serial = row.serial, name = card and Utils.FullName(card) or row.card_id, stolen = DB.IsStolen(row.serial) }
    end
    return out
end)

lib.callback.register('as-tradingcards:server:reportStolen', function(src, serial, clear)
    local id = Framework.GetIdentifier(src)
    if type(serial) ~= 'string' or not id then return false end
    serial = serial:upper():gsub('%s', '')
    local owner = DB.GetOwner(serial)
    if not owner then Framework.Notify(src, L('stolen_unknown'), 'error') return false end
    if owner ~= id then Framework.Notify(src, L('stolen_not_owner'), 'error') return false end
    if clear then DB.ClearStolen(serial) Framework.Notify(src, L('stolen_cleared', serial), 'success')
    else DB.ReportStolen(serial, id) Framework.Notify(src, L('stolen_reported', serial), 'success') end
    return true
end)
