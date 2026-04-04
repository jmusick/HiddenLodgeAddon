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

function HiddenLodge:GetAttendanceScoreForCandidate(candidate)
    if not candidate or candidate == "" then
        return nil
    end

    local character, realm = strsplit("-", tostring(candidate), 2)
    if not realm or realm == "" then
        realm = GetRealmName()
    end

    local fullKey = normalizedFullKey(character, realm)
    local nameKey = normalizeName(character)
    local store = self.db and self.db.attendanceScore
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

    if score < 0 then
        score = 0
    elseif score > 100 then
        score = 100
    end

    return math.floor(score * 10 + 0.5) / 10
end

function HiddenLodge:GetAttendanceScoreColor(score)
    if type(score) ~= "number" then
        return 0.70, 0.70, 0.70
    end
    if score >= 100 then
        return 1.00, 0.50, 0.00
    end
    if score >= 90 then
        return 0.64, 0.21, 0.93
    end
    if score >= 80 then
        return 0.00, 0.44, 0.87
    end
    if score >= 65 then
        return 0.12, 1.00, 0.12
    end
    return 1.00, 1.00, 1.00
end