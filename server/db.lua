DB = {}

local prints = {}      -- [cardId] = printed count (cached, source of truth for serials)
DB.Ready = false
DB.Stolen = {}   -- [serial] = true

CreateThread(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `ascard_prints` (
            `card_id` VARCHAR(64) NOT NULL,
            `printed` INT NOT NULL DEFAULT 0,
            PRIMARY KEY (`card_id`)
        )
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `ascard_collection` (
            `identifier` VARCHAR(64) NOT NULL,
            `card_id` VARCHAR(64) NOT NULL,
            `pulls` INT NOT NULL DEFAULT 1,
            `foils` INT NOT NULL DEFAULT 0,
            `first_pulled` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`identifier`, `card_id`)
        )
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `ascard_grading` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `identifier` VARCHAR(64) NOT NULL,
            `item` VARCHAR(64) NOT NULL,
            `metadata` LONGTEXT NOT NULL,
            `ready_at` INT NOT NULL,
            `collected` TINYINT(1) NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`),
            KEY `identifier` (`identifier`)
        )
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `ascard_binder` (
            `binder_id` VARCHAR(40) NOT NULL,
            `card_id` VARCHAR(64) NOT NULL,
            `item` VARCHAR(64) NOT NULL,
            `metadata` LONGTEXT NOT NULL,
            `added_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`binder_id`, `card_id`)
        )
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `ascard_owners` (
            `serial` VARCHAR(64) NOT NULL,
            `identifier` VARCHAR(64) NOT NULL,
            `card_id` VARCHAR(64) NOT NULL,
            `pulled_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`serial`)
        )
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `ascard_stolen` (
            `serial` VARCHAR(64) NOT NULL,
            `identifier` VARCHAR(64) NOT NULL,
            `reported_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`serial`)
        )
    ]])
    for _, row in ipairs(MySQL.query.await('SELECT serial FROM ascard_stolen') or {}) do DB.Stolen[row.serial] = true end

    for _, row in ipairs(MySQL.query.await('SELECT card_id, printed FROM ascard_prints') or {}) do
        prints[row.card_id] = row.printed
    end
    DB.Ready = true
end)

function DB.GetPrinted(cardId)
    return prints[cardId] or 0
end

function DB.IsSoldOut(cardId)
    local card = Config.Cards[cardId]
    return card and card.maxPrints ~= nil and DB.GetPrinted(cardId) >= card.maxPrints
end

-- Reserves the next print number for a card. Lua is single threaded so this is race-free.
function DB.NextPrint(cardId)
    local n = (prints[cardId] or 0) + 1
    prints[cardId] = n
    MySQL.insert('INSERT INTO ascard_prints (card_id, printed) VALUES (?, ?) ON DUPLICATE KEY UPDATE printed = VALUES(printed)', { cardId, n })
    return n
end

function DB.LogPull(identifier, cardId, foil)
    MySQL.insert([[
        INSERT INTO ascard_collection (identifier, card_id, pulls, foils) VALUES (?, ?, 1, ?)
        ON DUPLICATE KEY UPDATE pulls = pulls + 1, foils = foils + VALUES(foils)
    ]], { identifier, cardId, foil and 1 or 0 })
end

function DB.GetCollection(identifier)
    local out = {}
    for _, row in ipairs(MySQL.query.await('SELECT card_id, pulls, foils FROM ascard_collection WHERE identifier = ?', { identifier }) or {}) do
        out[row.card_id] = { pulls = row.pulls, foils = row.foils }
    end
    return out
end

-- grading
function DB.AddGrading(identifier, item, metadata, readyAt)
    return MySQL.insert.await('INSERT INTO ascard_grading (identifier, item, metadata, ready_at) VALUES (?, ?, ?, ?)',
        { identifier, item, json.encode(metadata), readyAt })
end

function DB.GetGrading(identifier)
    return MySQL.query.await('SELECT id, item, metadata, ready_at FROM ascard_grading WHERE identifier = ? AND collected = 0 ORDER BY ready_at', { identifier }) or {}
end

function DB.MarkCollected(id)
    return (MySQL.update.await('UPDATE ascard_grading SET collected = 1 WHERE id = ? AND collected = 0', { id }) or 0) > 0
end

-- binder pockets (one card per card id per binder)
function DB.GetBinder(binderId)
    local out = {}
    for _, row in ipairs(MySQL.query.await('SELECT card_id, item, metadata FROM ascard_binder WHERE binder_id = ?', { binderId }) or {}) do
        out[row.card_id] = { item = row.item, metadata = json.decode(row.metadata) or {} }
    end
    return out
end

-- returns false if that pocket is already filled
function DB.BinderInsert(binderId, cardId, item, metadata)
    local affected = MySQL.update.await('INSERT IGNORE INTO ascard_binder (binder_id, card_id, item, metadata) VALUES (?, ?, ?, ?)',
        { binderId, cardId, item, json.encode(metadata) })
    return (affected or 0) > 0
end

-- returns false if the pocket was already empty (stops double take-outs)
function DB.BinderRemove(binderId, cardId)
    local affected = MySQL.update.await('DELETE FROM ascard_binder WHERE binder_id = ? AND card_id = ?', { binderId, cardId })
    return (affected or 0) > 0
end

-- numbered parallels share ascard_prints, keyed "<cardId>:<parallelId>"
function DB.ParallelKey(cardId, parId) return cardId .. ':' .. parId end
function DB.ParallelLeft(cardId, par)
    return par.maxPrints - DB.GetPrinted(DB.ParallelKey(cardId, par.id))
end

-- first owner of each physical card (whoever pulled it)
function DB.SetOwner(serial, identifier, cardId)
    if not serial or not identifier then return end
    MySQL.insert('INSERT IGNORE INTO ascard_owners (serial, identifier, card_id) VALUES (?, ?, ?)', { serial, identifier, cardId or '' })
end
-- a real card turned up in someone's hands with no pull record (cards from before the record
-- existed, or given by staff): the first person seen holding it goes on record
function DB.Seen(src, meta)
    if type(meta) ~= 'table' or not meta.serial or not meta.cardId then return end
    local id = type(src) == 'number' and Framework.GetIdentifier(src) or src
    if id then DB.SetOwner(meta.serial, id, meta.cardId) end
end
function DB.GetOwner(serial)
    return MySQL.scalar.await('SELECT identifier FROM ascard_owners WHERE serial = ?', { serial })
end
function DB.OwnedSerials(identifier)
    return MySQL.query.await('SELECT serial, card_id FROM ascard_owners WHERE identifier = ? ORDER BY pulled_at DESC LIMIT 200', { identifier }) or {}
end

-- stolen reports
function DB.IsStolen(serial) return serial and DB.Stolen[serial] == true end
function DB.ReportStolen(serial, identifier)
    DB.Stolen[serial] = true
    MySQL.insert('INSERT IGNORE INTO ascard_stolen (serial, identifier) VALUES (?, ?)', { serial, identifier })
end
function DB.ClearStolen(serial)
    DB.Stolen[serial] = nil
    MySQL.update('DELETE FROM ascard_stolen WHERE serial = ?', { serial })
end
