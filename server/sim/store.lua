---@type table Shared server helpers (server.util): digits/formatNumber.
local util = require 'server.util'

---@type table Store module; the table returned at end of file. Persistence for the SIM registry
---(number -> data identity) and the per-character cloud-backup pointers.
local store = {}

---Generates a random 10-digit phone number as raw digits, with the first block starting at 200
---(mirrors server.settings.store's generator).
---@return string number ten raw digits
local function genNumber()
    return ('%03d%03d%04d'):format(math.random(200, 989), math.random(100, 999), math.random(0, 9999))
end

---Creates the SIM registry and cloud-backup tables.
function store.ensureSchema()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS phone_sim_cards (
            number     VARCHAR(20) NOT NULL,
            identity   VARCHAR(64) NOT NULL,
            owner_cid  VARCHAR(64) NULL,
            created_at TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (number),
            INDEX idx_phone_sim_identity (identity)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS phone_cloud_backups (
            citizenid  VARCHAR(64) NOT NULL,
            identity   VARCHAR(64) NOT NULL,
            enabled    TINYINT(1)  NOT NULL DEFAULT 1,
            updated_at TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP
                ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (citizenid)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
end

---True when a number is already claimed - by a registered SIM or by any legacy
---phone_settings row (pre-SIM assignments must never be duplicated onto a new SIM).
---@param digits string bare-digit number
---@return boolean taken
local function numberTaken(digits)
    local sim = MySQL.scalar.await('SELECT 1 FROM phone_sim_cards WHERE number = ? LIMIT 1', { digits })
    if sim then return true end
    local legacy = MySQL.scalar.await('SELECT 1 FROM phone_settings WHERE phone_number = ? LIMIT 1', { digits })
    return legacy ~= nil
end

---Generates a phone number that is free in both the SIM registry and phone_settings; tries 20
---random candidates, then accepts an unchecked one.
---@return string number ten raw digits
function store.generateNumber()
    for _ = 1, 20 do
        local candidate = genNumber()
        if not numberTaken(candidate) then return candidate end
    end
    return genNumber()
end

---Reads a SIM registry row by number. Read-only.
---@param number string phone number in any formatting
---@return { number: string, identity: string, owner_cid: string|nil }|nil
function store.get(number)
    local digits = util.digits(number)
    if digits == '' then return nil end
    return MySQL.single.await(
        'SELECT number, identity, owner_cid FROM phone_sim_cards WHERE number = ?', { digits })
end

---Registers a new SIM. When `bindCid` is given the SIM is character-bound: its identity is that
---citizenid (so the character's pre-SIM data carries over) and, unless a number was passed, it
---reuses the character's already-assigned number when that number isn't on a SIM yet. A blank
---SIM gets a fresh `sim:<number>` identity.
---@param opts? { number?: string, bindCid?: string }
---@return string|nil number registered bare-digit number, nil when the requested number is taken
function store.create(opts)
    opts = opts or {}
    local digits = util.digits(opts.number)

    if digits ~= '' then
        if store.get(digits) then return nil end
    elseif opts.bindCid then
        local existing = MySQL.scalar.await(
            'SELECT phone_number FROM phone_settings WHERE citizenid = ?', { opts.bindCid })
        existing = util.digits(existing)
        if existing ~= '' and not store.get(existing) then digits = existing end
    end
    if digits == '' then digits = store.generateNumber() end

    local identity = opts.bindCid or ('sim:' .. digits)
    MySQL.update.await([[
        INSERT INTO phone_sim_cards (number, identity, owner_cid) VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE number = number
    ]], { digits, identity, opts.bindCid })
    return digits
end

---Resolves a SIM number to its data identity, registering unknown numbers on the fly (a SIM
---spawned raw through an inventory admin tool still works: it becomes a blank `sim:<number>`
---profile). First activation also stamps `owner_cid` - the character a blank SIM "belongs" to,
---used to gate Face Unlock so a thief's face never unlocks a stolen phone.
---@param number string bare-digit SIM number
---@param activatorCid string|nil real citizenid of the player activating the SIM
---@return string|nil identity data identity for the number, nil for an unusable number
function store.ensureRegistered(number, activatorCid)
    local digits = util.digits(number)
    if digits == '' then return nil end

    local row = store.get(digits)
    if not row then
        -- Unknown number: honour a legacy phone_settings assignment (that character's number
        -- became a SIM), otherwise open a fresh blank profile.
        local legacyCid = MySQL.scalar.await(
            'SELECT citizenid FROM phone_settings WHERE phone_number = ? LIMIT 1', { digits })
        local identity = legacyCid or ('sim:' .. digits)
        MySQL.update.await([[
            INSERT INTO phone_sim_cards (number, identity, owner_cid) VALUES (?, ?, ?)
            ON DUPLICATE KEY UPDATE number = number
        ]], { digits, identity, activatorCid })
        return identity
    end

    if not row.owner_cid and activatorCid then
        MySQL.update.await(
            'UPDATE phone_sim_cards SET owner_cid = ? WHERE number = ? AND owner_cid IS NULL',
            { activatorCid, digits })
        row.owner_cid = activatorCid
    end
    return row.identity
end

---Reads a character's cloud-backup pointer, or nil when never enabled. Read-only.
---@param citizenid string real (framework) citizenid
---@return { identity: string, enabled: boolean }|nil
function store.getBackup(citizenid)
    if not citizenid or citizenid == '' then return nil end
    local row = MySQL.single.await(
        'SELECT identity, enabled FROM phone_cloud_backups WHERE citizenid = ?', { citizenid })
    if not row then return nil end
    return { identity = row.identity, enabled = util.truthy(row.enabled) }
end

---Upserts a character's cloud-backup pointer: which phone profile is "in the cloud" and
---whether backup is currently on.
---@param citizenid string real (framework) citizenid
---@param identity string phone profile the backup points at
---@param enabled boolean
function store.setBackup(citizenid, identity, enabled)
    if not citizenid or citizenid == '' or not identity or identity == '' then return end
    MySQL.update.await([[
        INSERT INTO phone_cloud_backups (citizenid, identity, enabled) VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE identity = VALUES(identity), enabled = VALUES(enabled)
    ]], { citizenid, identity, enabled and 1 or 0 })
end

return store
