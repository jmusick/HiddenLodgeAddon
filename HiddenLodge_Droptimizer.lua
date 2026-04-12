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

local function countNestedEntries(map)
    if type(map) ~= "table" then
        return 0
    end

    local count = 0
    for _, value in pairs(map) do
        if type(value) == "table" then
            for _ in pairs(value) do
                count = count + 1
            end
        end
    end
    return count
end

local function countItems(map)
    if type(map) ~= "table" then
        return 0
    end

    local count = 0
    for _ in pairs(map) do
        count = count + 1
    end
    return count
end

function HiddenLodge:GetDroptimizerUpgradeForCandidate(candidate, itemId)
    local numericItemId = tonumber(itemId)
    if not candidate or candidate == "" or not numericItemId or numericItemId <= 0 then
        return nil, nil
    end

    local character, realm = strsplit("-", tostring(candidate), 2)
    if not realm or realm == "" then
        realm = GetRealmName()
    end

    local fullKey = normalizedFullKey(character, realm)
    local nameKey = normalizeName(character)
    local store = self.db and self.db.droptimizer
    if not store then
        return nil, nil
    end

    local itemKey = tostring(math.floor(numericItemId))
    local byFullDelta = store.byItemByFullDelta and store.byItemByFullDelta[itemKey]
    local byNameDelta = store.byItemByNameDelta and store.byItemByNameDelta[itemKey]
    local byFullPct = store.byItemByFullPct and store.byItemByFullPct[itemKey]
    local byNamePct = store.byItemByNamePct and store.byItemByNamePct[itemKey]

    local delta = nil
    if type(byFullDelta) == "table" then
        delta = tonumber(byFullDelta[fullKey])
    end
    if delta == nil and type(byNameDelta) == "table" then
        delta = tonumber(byNameDelta[nameKey])
    end

    local pct = nil
    if type(byFullPct) == "table" then
        pct = tonumber(byFullPct[fullKey])
    end
    if pct == nil and type(byNamePct) == "table" then
        pct = tonumber(byNamePct[nameKey])
    end

    return delta, pct
end

function HiddenLodge:FormatDroptimizerUpgrade(delta, pct)
    if not delta then
        return "-"
    end

    local sign = delta >= 0 and "+" or ""
    local absValue = math.abs(delta)
    local deltaText
    if absValue >= 1000 then
        deltaText = string.format("%s%.1fk", sign, delta / 1000)
    else
        deltaText = string.format("%s%.0f", sign, delta)
    end

    if pct and pct > 0 then
        return string.format("%s (%.1f%%)", deltaText, pct)
    end

    return deltaText
end

function HiddenLodge:GetDroptimizerUpgradeColor(delta)
    if not delta then
        return 0.70, 0.70, 0.70
    end
    if delta >= 10000 then
        return 0.35, 0.98, 0.45
    end
    if delta >= 5000 then
        return 0.50, 0.95, 0.45
    end
    if delta >= 2000 then
        return 0.75, 0.95, 0.40
    end
    if delta > 0 then
        return 0.95, 0.90, 0.40
    end
    if delta == 0 then
        return 0.75, 0.75, 0.75
    end
    return 0.95, 0.45, 0.35
end

function HiddenLodge:GetDroptimizerSyncStatus()
    local store = self.db and self.db.droptimizer or {}
    local sync = (store and store.sync) or {}

    local source = trim(sync.source)
    if source == "" then
        source = "Unknown"
    end

    local entries = tonumber(sync.entries)
    if not entries or entries <= 0 then
        entries = countNestedEntries(store.byItemByFullDelta)
    end

    local items = tonumber(sync.items)
    if not items or items <= 0 then
        items = countItems(store.byItemByFullDelta)
    end

    local syncedAt = tonumber(sync.syncedAt) or 0

    return {
        source = source,
        entries = entries,
        syncedAt = syncedAt,
        items = items,
    }
end

function HiddenLodge:GetCurrentRCLootItemId(voting)
    local candidates = {}

    if voting and type(voting.GetCurrentItemLink) == "function" then
        local ok, link = pcall(voting.GetCurrentItemLink, voting)
        if ok and link then
            table.insert(candidates, link)
        end
    end

    if voting and type(voting.GetCurrentItem) == "function" then
        local ok, currentItem = pcall(voting.GetCurrentItem, voting)
        if ok and currentItem then
            table.insert(candidates, currentItem.link)
            table.insert(candidates, currentItem.itemLink)
        end
    end

    if voting and voting.frame then
        local frameItem = voting.frame.item
        if type(frameItem) == "table" then
            table.insert(candidates, frameItem.link)
            table.insert(candidates, frameItem.itemLink)
        else
            table.insert(candidates, frameItem)
        end
    end

    for _, value in ipairs(candidates) do
        if value then
            local itemId = nil
            if C_Item and C_Item.GetItemInfoInstant then
                itemId = select(1, C_Item.GetItemInfoInstant(value))
            end
            if itemId and itemId > 0 then
                return itemId
            end

            local fromLink = tostring(value):match("item:(%d+)")
            if fromLink then
                local parsed = tonumber(fromLink)
                if parsed and parsed > 0 then
                    return parsed
                end
            end
        end
    end

    return nil
end
