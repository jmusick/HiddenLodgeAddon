---@diagnostic disable: inject-field, undefined-field, undefined-global
local addonName = ...
---@type HiddenLodgeAddon
local HiddenLodge = LibStub("AceAddon-3.0"):GetAddon(addonName) --[[@as HiddenLodgeAddon]]

local TIER_SCORES = {
    ["S Tier"] = 5,
    ["A Tier"] = 4,
    ["B Tier"] = 3,
    ["C Tier"] = 2,
    ["D Tier"] = 1,
    ["-"] = 0,
    ["—"] = 0,
    [""] = 0,
}

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
    local n = 0
    if type(map) ~= "table" then
        return 0
    end
    for _ in pairs(map) do
        n = n + 1
    end
    return n
end

local function formatAge(seconds)
    if not seconds or seconds < 0 then
        return "unknown"
    end

    if seconds < 60 then
        return seconds .. "s ago"
    end

    local minutes = math.floor(seconds / 60)
    if minutes < 60 then
        return minutes .. "m ago"
    end

    local hours = math.floor(minutes / 60)
    if hours < 48 then
        return hours .. "h ago"
    end

    local days = math.floor(hours / 24)
    return days .. "d ago"
end

function HiddenLodge:GetPreparednessTierSortValue(tier)
    local cleanTier = trim(tier)
    return TIER_SCORES[cleanTier] or 0
end

function HiddenLodge:GetPreparednessTierColor(tier)
    local score = self:GetPreparednessTierSortValue(tier)
    if score >= 5 then
        return 0.45, 0.95, 0.45
    end
    if score == 4 then
        return 0.65, 0.95, 0.45
    end
    if score == 3 then
        return 0.95, 0.90, 0.40
    end
    if score == 2 then
        return 0.95, 0.70, 0.35
    end
    if score == 1 then
        return 0.95, 0.45, 0.35
    end
    return 0.70, 0.70, 0.70
end

function HiddenLodge:GetPreparednessTierForCandidate(candidate)
    if not candidate or candidate == "" then
        return "-"
    end

    local character, realm = strsplit("-", tostring(candidate), 2)
    if not realm or realm == "" then
        realm = GetRealmName()
    end

    local fullKey = normalizedFullKey(character, realm)
    local nameKey = normalizeName(character)
    local store = self.db and self.db.preparedness

    if not store then
        return "-"
    end

    local tier = store.byFull[fullKey] or store.byName[nameKey]
    if not tier or trim(tier) == "" then
        return "-"
    end
    return tier
end

function HiddenLodge:GetPreparednessSyncStatus()
    local store = self.db and self.db.preparedness or {}
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

    local syncedAt = tonumber(sync.syncedAt) or 0

    return {
        source = source,
        entries = entries,
        syncedAt = syncedAt,
    }
end

function HiddenLodge:GetPreparednessSyncStatusText()
    local status = self:GetPreparednessSyncStatus()
    if status.entries <= 0 then
        return "No synced data found yet.\nRun sync from HiddenLodge Desktop, then /reload.", 0.95, 0.70, 0.35
    end

    local syncedLine
    if status.syncedAt > 0 then
        local nowTs = time()
        local age = nowTs - status.syncedAt
        syncedLine = date("%Y-%m-%d %H:%M:%S", status.syncedAt) .. " (" .. formatAge(age) .. ")"
    else
        syncedLine = "Not recorded (sync metadata unavailable)"
    end

    local text = string.format(
        "Synced data is present and ready.\nEntries: %d\nLast desktop sync: %s\nSource: %s",
        status.entries,
        syncedLine,
        status.source
    )
    return text, 0.35, 0.95, 0.50
end
