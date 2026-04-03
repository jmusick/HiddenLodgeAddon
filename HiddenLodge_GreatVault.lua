---@diagnostic disable: inject-field, undefined-field, undefined-global
local addonName = ...
---@type HiddenLodgeAddon
local HiddenLodge = LibStub("AceAddon-3.0"):GetAddon(addonName) --[[@as HiddenLodgeAddon]]

local function trim(value)
    return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function normalizeRealm(realm)
    return trim(realm):lower():gsub("[%s%-']", "")
end

local function normalizeName(name)
    return trim(name):lower()
end

local function normalizedFullKey(character, realm)
    local n = normalizeName(character)
    if n == "" then
        return ""
    end

    local r = normalizeRealm(realm)
    if r == "" then
        return n
    end

    return n .. "-" .. r
end

local function countEntries(map)
    local total = 0
    if type(map) ~= "table" then
        return 0
    end
    for _ in pairs(map) do
        total = total + 1
    end
    return total
end

function HiddenLodge:GetGreatVaultScoreForCandidate(candidate)
    if not candidate or candidate == "" then
        return nil
    end

    local character, realm = strsplit("-", tostring(candidate), 2)
    if not realm or realm == "" then
        realm = GetRealmName()
    end

    local fullKey = normalizedFullKey(character, realm)
    local nameKey = normalizeName(character)
    local store = self.db and self.db.greatVaultScore

    if not store then
        return nil
    end

    local score = tonumber(store.byFull[fullKey])
    if not score then
        score = tonumber(store.byName[nameKey])
    end
    if not score then
        return nil
    end

    score = math.floor(score + 0.5)
    if score < 0 then
        score = 0
    elseif score > 100 then
        score = 100
    end

    return score
end

function HiddenLodge:GetGreatVaultScoreColor(score)
    if type(score) ~= "number" then
        return 0.70, 0.70, 0.70
    end
    if score >= 95 then
        return 1.00, 0.50, 0.00
    end
    if score >= 85 then
        return 0.64, 0.21, 0.93
    end
    if score >= 70 then
        return 0.00, 0.44, 0.87
    end
    if score >= 40 then
        return 0.12, 1.00, 0.12
    end
    return 1.00, 1.00, 1.00
end

function HiddenLodge:GetGreatVaultSyncStatus()
    local store = self.db and self.db.greatVaultScore or {}
    local sync = (store and store.sync) or {}

    local source = trim(sync.source)
    if source == "" then
        source = "Unknown"
    end

    local entries = tonumber(sync.entries)
    if not entries or entries <= 0 then
        entries = countEntries(store.byFull)
    end

    if source == "Unknown" and entries > 0 then
        source = "HiddenLodgeDesktop (legacy)"
    end

    return {
        source = source,
        entries = entries,
        syncedAt = tonumber(sync.syncedAt) or 0,
    }
end