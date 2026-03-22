---@diagnostic disable: inject-field, undefined-field
local addonName = ...

---@class HiddenLodgeMainFrame: Frame
---@field statusText FontString
---@field importEditBox EditBox

---@class HiddenLodgeAddon: AceAddon
---@field db table
---@field mainWindow HiddenLodgeMainFrame|nil
---@field Constants table

local aceAddon = LibStub and LibStub("AceAddon-3.0", true)

if not aceAddon then
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("ADDON_LOADED")
    frame:SetScript("OnEvent", function(_, event, loadedAddonName)
        if event ~= "ADDON_LOADED" or loadedAddonName ~= addonName then
            return
        end

        DEFAULT_CHAT_FRAME:AddMessage("|cffff3333HiddenLodge|r requires Ace3. Install the Ace3 addon first.")
    end)
    return
end

local HiddenLodge = aceAddon:NewAddon(addonName, "AceConsole-3.0", "AceEvent-3.0") --[[@as HiddenLodgeAddon]]

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

local function parseJson(text)
    local i = 1
    local n = #text

    local function decodeError(msg)
        error("JSON parse error at position " .. i .. ": " .. msg)
    end

    local function skipWhitespace()
        while i <= n do
            local c = text:sub(i, i)
            if c == " " or c == "\n" or c == "\r" or c == "\t" then
                i = i + 1
            else
                break
            end
        end
    end

    local parseValue

    local function parseString()
        if text:sub(i, i) ~= '"' then
            decodeError("expected string")
        end

        i = i + 1
        local parts = {}

        while i <= n do
            local c = text:sub(i, i)
            if c == '"' then
                i = i + 1
                return table.concat(parts)
            end

            if c == "\\" then
                i = i + 1
                if i > n then
                    decodeError("unterminated escape sequence")
                end
                local esc = text:sub(i, i)
                if esc == '"' or esc == "\\" or esc == "/" then
                    parts[#parts + 1] = esc
                elseif esc == "b" then
                    parts[#parts + 1] = "\b"
                elseif esc == "f" then
                    parts[#parts + 1] = "\f"
                elseif esc == "n" then
                    parts[#parts + 1] = "\n"
                elseif esc == "r" then
                    parts[#parts + 1] = "\r"
                elseif esc == "t" then
                    parts[#parts + 1] = "\t"
                else
                    decodeError("unsupported escape '\\" .. esc .. "'")
                end
            else
                parts[#parts + 1] = c
            end

            i = i + 1
        end

        decodeError("unterminated string")
    end

    local function parseNumber()
        local startPos = i
        local c = text:sub(i, i)
        if c == "-" then
            i = i + 1
        end

        while i <= n and text:sub(i, i):match("%d") do
            i = i + 1
        end

        if text:sub(i, i) == "." then
            i = i + 1
            while i <= n and text:sub(i, i):match("%d") do
                i = i + 1
            end
        end

        local exp = text:sub(i, i)
        if exp == "e" or exp == "E" then
            i = i + 1
            local sign = text:sub(i, i)
            if sign == "+" or sign == "-" then
                i = i + 1
            end
            while i <= n and text:sub(i, i):match("%d") do
                i = i + 1
            end
        end

        local num = tonumber(text:sub(startPos, i - 1))
        if not num then
            decodeError("invalid number")
        end
        return num
    end

    local function parseLiteral(literal, value)
        if text:sub(i, i + #literal - 1) ~= literal then
            decodeError("expected '" .. literal .. "'")
        end
        i = i + #literal
        return value
    end

    local function parseArray()
        i = i + 1
        skipWhitespace()
        local arr = {}
        if text:sub(i, i) == "]" then
            i = i + 1
            return arr
        end

        while i <= n do
            arr[#arr + 1] = parseValue()
            skipWhitespace()
            local c = text:sub(i, i)
            if c == "]" then
                i = i + 1
                return arr
            end
            if c ~= "," then
                decodeError("expected ',' or ']' in array")
            end
            i = i + 1
            skipWhitespace()
        end

        decodeError("unterminated array")
    end

    local function parseObject()
        i = i + 1
        skipWhitespace()
        local obj = {}
        if text:sub(i, i) == "}" then
            i = i + 1
            return obj
        end

        while i <= n do
            if text:sub(i, i) ~= '"' then
                decodeError("expected object key string")
            end
            local key = parseString()
            skipWhitespace()
            if text:sub(i, i) ~= ":" then
                decodeError("expected ':' after object key")
            end
            i = i + 1
            skipWhitespace()
            obj[key] = parseValue()
            skipWhitespace()
            local c = text:sub(i, i)
            if c == "}" then
                i = i + 1
                return obj
            end
            if c ~= "," then
                decodeError("expected ',' or '}' in object")
            end
            i = i + 1
            skipWhitespace()
        end

        decodeError("unterminated object")
    end

    function parseValue()
        skipWhitespace()
        if i > n then
            decodeError("unexpected end of input")
        end

        local c = text:sub(i, i)
        if c == '"' then
            return parseString()
        end
        if c == "{" then
            return parseObject()
        end
        if c == "[" then
            return parseArray()
        end
        if c == "-" or c:match("%d") then
            return parseNumber()
        end
        if c == "t" then
            return parseLiteral("true", true)
        end
        if c == "f" then
            return parseLiteral("false", false)
        end
        if c == "n" then
            return parseLiteral("null", nil)
        end

        decodeError("unexpected token '" .. c .. "'")
    end

    local result = parseValue()
    skipWhitespace()
    if i <= n then
        decodeError("trailing characters after JSON payload")
    end
    return result
end

local function ensureDefaults(db)
    db.ui = db.ui or {}
    db.ui.windowPoint = db.ui.windowPoint or nil
    db.preparedness = db.preparedness or {}
    db.preparedness.byFull = db.preparedness.byFull or {}
    db.preparedness.byName = db.preparedness.byName or {}
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

function HiddenLodge:ImportPreparednessJSON(jsonText)
    local payload = trim(jsonText)
    if payload == "" then
        return false, "Paste JSON before importing."
    end

    local ok, decoded = pcall(parseJson, payload)
    if not ok then
        return false, decoded
    end

    if type(decoded) ~= "table" then
        return false, "Expected a JSON array of player objects."
    end

    local byFull = {}
    local byName = {}
    local imported = 0

    for _, entry in ipairs(decoded) do
        if type(entry) == "table" then
            local character = trim(entry.character)
            local realm = trim(entry.realm)
            local tier = trim(entry.preparednessTier)

            if character ~= "" then
                if tier == "" or tier == "—" then
                    tier = "-"
                end
                if realm == "" then
                    realm = GetRealmName()
                end

                byFull[normalizedFullKey(character, realm)] = tier
                byName[normalizeName(character)] = tier
                imported = imported + 1
            end
        end
    end

    if imported == 0 then
        return false, "No valid player entries were found in the JSON payload."
    end

    self.db.preparedness.byFull = byFull
    self.db.preparedness.byName = byName

    return true, imported
end

function HiddenLodge:EnsureRCLootCouncilColumn()
    local ace = LibStub and LibStub("AceAddon-3.0", true)
    if not ace then
        return false, "AceAddon-3.0 is not available."
    end

    local rc = ace:GetAddon("RCLootCouncil", true)
    if not rc then
        return false, "RCLootCouncil is not loaded."
    end

    local voting = rc.GetModule and rc:GetModule("RCVotingFrame", true)
    if not voting then
        return false, "RCVotingFrame module is unavailable."
    end

    local function preparednessSort(tableObj, rowa, rowb, sortbycol)
        local column = tableObj.cols[sortbycol]
        local a = tableObj:GetRow(rowa)
        local b = tableObj:GetRow(rowb)
        if not (a and b) then
            return false
        end

        local at = self:GetPreparednessTierSortValue(self:GetPreparednessTierForCandidate(a.name))
        local bt = self:GetPreparednessTierSortValue(self:GetPreparednessTierForCandidate(b.name))

        if at == bt then
            local an = tostring(a.name or "")
            local bn = tostring(b.name or "")
            if an == bn then
                return false
            end
            local direction = column.sort or column.defaultsort or 1
            if direction == 1 then
                return an < bn
            end
            return an > bn
        end

        local direction = column.sort or column.defaultsort or 1
        if direction == 1 then
            return at < bt
        end
        return at > bt
    end

    local function setCellPreparedness(rowFrame, frame, data, cols, row, realrow, column)
        local name = data and data[realrow] and data[realrow].name or nil
        local tier = self:GetPreparednessTierForCandidate(name)
        local r, g, b = self:GetPreparednessTierColor(tier)
        frame.text:SetText(tier)
        frame.text:SetTextColor(r, g, b, 1)
        if data and data[realrow] and data[realrow].cols and data[realrow].cols[column] then
            data[realrow].cols[column].value = self:GetPreparednessTierSortValue(tier)
        end
    end

    local columnExists = false
    for _, col in ipairs(voting.scrollCols or {}) do
        if col.colName == "preparednessTier" then
            col.DoCellUpdate = setCellPreparedness
            col.comparesort = preparednessSort
            columnExists = true
            break
        end
    end

    if not columnExists then
        tinsert(voting.scrollCols, {
            name = "Prep",
            DoCellUpdate = setCellPreparedness,
            colName = "preparednessTier",
            width = 70,
            align = "CENTER",
            comparesort = preparednessSort,
            sortnext = 2,
        })
    end

    if voting.frame and voting.frame.UpdateSt then
        voting.frame.UpdateSt()
    end
    if voting.frame and voting.frame.st and voting.frame.st.Refresh then
        voting.frame.st:Refresh()
    end

    return true
end

function HiddenLodge:OnInitialize()
    HiddenLodgeDB = HiddenLodgeDB or {}
    self.db = HiddenLodgeDB
    ensureDefaults(self.db)

    self:RegisterChatCommand("hl", "HandleSlashCommand")
    self:Print("loaded. Use /hl")
end

function HiddenLodge:OnEnable()
    self:RegisterEvent("ADDON_LOADED", "HandleAddonLoaded")
    self:EnsureRCLootCouncilColumn()
end

function HiddenLodge:HandleAddonLoaded(_, loadedAddonName)
    if loadedAddonName == "RCLootCouncil" then
        self:EnsureRCLootCouncilColumn()
    end
end

function HiddenLodge:HandleSlashCommand(input)
    local command = input and strlower(strtrim(input)) or ""

    if command == "" or command == "show" then
        self:ToggleMainWindow()
        return
    end

    if command == "hide" then
        self:HideMainWindow()
        return
    end

    self:Print("Usage: /hl [show|hide]")
end
