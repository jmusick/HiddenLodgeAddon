---@diagnostic disable: inject-field, undefined-field, undefined-global
local addonName = ...
---@type HiddenLodgeAddon
local HiddenLodge = LibStub("AceAddon-3.0"):GetAddon(addonName) --[[@as HiddenLodgeAddon]]

local STATUS_LABELS = {
    ["coming"] = "Coming",
    ["tentative"] = "Tentative",
    ["late"] = "Late",
    ["absent"] = "Absent",
    ["not-signed"] = "Not Signed",
}

local STATUS_SORT = {
    ["coming"] = 5,
    ["tentative"] = 4,
    ["late"] = 3,
    ["absent"] = 2,
    ["not-signed"] = 1,
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

function HiddenLodge:GetRaidSignupSortValue(status)
    local key = trim(status):lower()
    return STATUS_SORT[key] or 0
end

function HiddenLodge:GetRaidSignupColor(status)
    local key = trim(status):lower()
    if key == "coming" then
        return 0.35, 0.95, 0.50
    end
    if key == "tentative" then
        return 0.95, 0.90, 0.35
    end
    if key == "late" then
        return 0.95, 0.72, 0.32
    end
    if key == "absent" then
        return 0.95, 0.45, 0.35
    end
    return 0.70, 0.70, 0.70
end

function HiddenLodge:FormatRaidSignupSignedAt(signedAt)
    local ts = tonumber(signedAt) or 0
    if ts <= 0 then
        return "-"
    end

    local nowTs = time()
    local today = date("%Y%m%d", nowTs)
    local tsDay = date("%Y%m%d", ts)
    if today == tsDay then
        return date("%H:%M", ts)
    end

    return date("%m/%d %H:%M", ts)
end

function HiddenLodge:GetRaidSignupForCandidate(candidate)
    if not candidate or candidate == "" then
        return "not-signed", STATUS_LABELS["not-signed"], nil
    end

    local character, realm = strsplit("-", tostring(candidate), 2)
    if not realm or realm == "" then
        realm = GetRealmName()
    end

    local fullKey = normalizedFullKey(character, realm)
    local nameKey = normalizeName(character)
    local store = self.db and self.db.raidSignup
    if not store then
        return "not-signed", STATUS_LABELS["not-signed"], nil
    end

    local status = store.byFullStatus[fullKey] or store.byNameStatus[nameKey] or "not-signed"
    status = trim(status):lower()
    if STATUS_LABELS[status] == nil then
        status = "not-signed"
    end

    local signedAt = tonumber(store.byFullSignedAt[fullKey]) or tonumber(store.byNameSignedAt[nameKey])
    if not signedAt or signedAt <= 0 then
        signedAt = nil
    end

    return status, STATUS_LABELS[status], signedAt
end
