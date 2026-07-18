---@type table SIM feature flags (server.sim.state): active + mode.
local state         = require 'server.sim.state'
---@type table SIM registry persistence (server.sim.store): number -> identity mapping.
local simStore      = require 'server.sim.store'
---@type table Slot-level inventory access for SIMs (server.sim.inv).
local siminv        = require 'server.sim.inv'
---@type table Settings persistence (server.settings.store): phone_settings number sync.
local settingsStore = require 'server.settings.store'

---@type table Session module; the table returned at end of file. Resolves which SIM (and
---therefore which data identity) each connected player is currently carrying, with a short
---cache so the per-callback identity wrapper stays cheap.
local session = {}

---@type fun(source: number): string|nil Real framework identifier resolver, injected by
---server/sim/init.lua BEFORE the getIdentifier wrapper is installed (never the wrapped fn).
local realIdentifier = function() return nil end

---Injects the unwrapped framework-identifier resolver.
---@param fn fun(source: number): string|nil
function session.setRealResolver(fn) realIdentifier = fn end

---@type integer Cache lifetime in ms; inventory scans are re-run at most this often per player.
local TTL = 5000

---@class SimSession
---@field hasPhone boolean player carries at least one configured phone item
---@field hasSim boolean a SIM is installed in the active phone
---@field identity string|nil data identity the SIM maps to
---@field number string|nil bare-digit SIM number
---@field color string|nil frame colour of the active phone
---@field slot number|nil inventory slot of the active phone

---@type table<number, { at: number, s: SimSession|nil }> Per-source cache; `s = nil` caches "no phone".
local cache = {}

---Drops one player's cached session (or everyone's with nil) so the next resolve re-scans.
---@param source number|nil player server id, nil to flush all
function session.invalidate(source)
    if source then cache[source] = nil else cache = {} end
end

---Scans the player's inventory and binds the found SIM: the active phone is the first phone
---(config order) with a SIM installed, else the first phone. Binding registers unknown numbers,
---stamps the SIM's first activator, and mirrors the number onto the identity's phone_settings
---row so every existing "my number" read keeps working.
---@param source number player server id
---@return SimSession|nil s nil when the player carries no phone item
local function compute(source)
    local phones = siminv.findPhones(source)
    if #phones == 0 then return nil end

    local active, number = phones[1], nil
    for _, phone in ipairs(phones) do
        local n = siminv.getSimNumber(source, phone)
        if n then
            active, number = phone, n
            break
        end
    end

    local s = {
        hasPhone = true,
        hasSim   = number ~= nil,
        color    = active.color,
        slot     = active.slot,
        number   = number,
    }
    if number then
        s.identity = simStore.ensureRegistered(number, realIdentifier(source))
        if s.identity and settingsStore.getPhoneNumber(s.identity) ~= number then
            settingsStore.setPhoneNumber(s.identity, number)
        end
    end
    return s
end

---The player's current SIM session, cached for TTL ms. Nil when the player carries no phone.
---@param source number player server id
---@return SimSession|nil
function session.resolve(source)
    if not state.active then return nil end
    local now = GetGameTimer()
    local hit = cache[source]
    if hit and (now - hit.at) < TTL then return hit.s end
    local s = compute(source)
    cache[source] = { at = now, s = s }
    return s
end

---The acting data identity for a source: the installed SIM's identity, or nil without a SIM
---(no SIM = no service = every identity-keyed callback fails closed).
---@param source number player server id
---@return string|nil identity
function session.identity(source)
    local s = session.resolve(source)
    return s and s.identity or nil
end

---True when the phone the player holds "belongs" to them: the SIM's first activator matches
---their real character. Gates Face Unlock so a stolen phone never face-unlocks for the thief.
---@param source number player server id
---@return boolean owner
function session.isOwner(source)
    if not state.active then return true end
    local s = session.resolve(source)
    if not s or not s.number then return false end
    local row = simStore.get(s.number)
    if not row or not row.owner_cid then return false end
    return row.owner_cid == realIdentifier(source)
end

---Recomputes a player's SIM state and pushes it to their client (the NUI swaps the "No SIM"
---screen in or out live). Call after anything that may have moved a SIM or phone.
---@param source number player server id
function session.push(source)
    if not state.active then return end
    session.invalidate(source)
    local s = session.resolve(source)
    TriggerClientEvent('sd-phone:client:simState', source, {
        enabled = true,
        hasSim  = s ~= nil and s.hasSim or false,
        number  = s and s.number or nil,
    })
end

-- Dropped players release their cache entry.
AddEventHandler('playerDropped', function()
    cache[source] = nil
end)

return session
