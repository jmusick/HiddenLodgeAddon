---@diagnostic disable: inject-field, undefined-field, undefined-global
local addonName = ...
---@type HiddenLodgeAddon
local HiddenLodge = LibStub("AceAddon-3.0"):GetAddon(addonName)

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
