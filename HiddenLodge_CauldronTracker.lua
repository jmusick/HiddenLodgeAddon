---@diagnostic disable: inject-field, undefined-field, undefined-global
local addonName = ...
---@type HiddenLodgeAddon
local HiddenLodge = LibStub("AceAddon-3.0"):GetAddon(addonName) --[[@as HiddenLodgeAddon]]

-- Ported from the standalone CauldronTracker addon: tracks how many
-- flasks/phials each raider takes from raid cauldrons, using spell-cast
-- detection for placements and CHAT_MSG_LOOT for creates.

local CAULDRON_CHARGES = 40
local CAULDRON_ACTIVE_DURATION = 300 -- cauldron lasts 5 minutes after placement
local CAULDRON_SPELL_IDS = {
    [1240019] = "Prepare Midnight Flask Cauldron",
    [432878]  = "Prepare Algari Flask Cauldron",
}
local BURST_THRESHOLD = 3 -- distinct players required to infer an undetected cauldron
local BURST_WINDOW = 30
local LOOT_DEDUP_WINDOW = 1.0
local DEBUG_LOG_MAX = 500

local function Today()
    return date("%Y-%m-%d")
end

local function StripRealm(name)
    if not name then return name end
    return (strsplit("-", name, 2))
end

local function IsSecret(v)
    return issecretvalue and issecretvalue(v)
end

-- While a cauldron window is active, all writes stay anchored to the day the
-- window opened, so a raid that crosses midnight doesn't split its counts
-- across two days.
local cauldronActiveUntil = 0
local activeDayKey
local recentCreates = {}    -- buffer of {time, player} for creates not yet attributed to a cauldron
local recentCastGUIDs = {}  -- castGUID -> time, dedup spell-cast detections
local recentLootKeys = {}   -- (player|itemLink) -> time, dedup duplicate loot messages

local function CurrentDayKey()
    if activeDayKey and GetTime() < cauldronActiveUntil then
        return activeDayKey
    end
    return Today()
end

local function ActivateCauldron(now)
    if now >= cauldronActiveUntil then
        activeDayKey = Today()
    end
    cauldronActiveUntil = math.max(cauldronActiveUntil, now + CAULDRON_ACTIVE_DURATION)
end

-- Counts distinct players among buffered creates that happened within `window`
-- seconds of `now`. Used only to decide whether a burst is happening right
-- now; the buffer itself is retained much longer (see recentCreates trimming)
-- so that stragglers who created well before the 3rd distinct player showed
-- up still get credited once the burst is confirmed.
local function CountUniquePlayersWithin(buffer, now, window)
    local seen, n = {}, 0
    for _, e in ipairs(buffer) do
        if (now - e.time) <= window and not seen[e.player] then
            seen[e.player] = true
            n = n + 1
        end
    end
    return n
end

local function IsFleetingItem(itemLink)
    if not itemLink then return false end
    local name = C_Item.GetItemNameByID(itemLink) or C_Item.GetItemInfo(itemLink)
    if not name then
        name = itemLink:match("%[(.-)%]")
    end
    if not name then return false end
    return name:lower():find("^fleeting") ~= nil
end

local function DebugPrint(self, msg)
    local store = self.db and self.db.cauldron
    if not store then return end
    store.debugLog = store.debugLog or {}
    table.insert(store.debugLog,
        string.format("%s %.3f %s", date("%Y-%m-%d %H:%M:%S"), GetTime(), msg))
    if #store.debugLog > DEBUG_LOG_MAX then
        table.remove(store.debugLog, 1)
    end
end

-- ===== Data access =====

function HiddenLodge:GetCauldronDayKey()
    return CurrentDayKey()
end

function HiddenLodge:GetCauldronDayData(day)
    day = day or CurrentDayKey()
    self.db.cauldron = self.db.cauldron or {}
    self.db.cauldron.days = self.db.cauldron.days or {}
    self.db.cauldron.days[day] = self.db.cauldron.days[day] or { counts = {}, cauldrons = {} }
    return self.db.cauldron.days[day]
end

function HiddenLodge:GetCauldronCounts(day)
    return self:GetCauldronDayData(day).counts
end

function HiddenLodge:GetCauldronCauldrons(day)
    return self:GetCauldronDayData(day).cauldrons
end

function HiddenLodge:GetCauldronAllotment(day)
    local cauldrons = self:GetCauldronCauldrons(day)
    local numCauldrons = #cauldrons
    if numCauldrons == 0 then
        return 0, 0
    end
    local raidSize = GetNumGroupMembers()
    if raidSize == 0 then raidSize = 1 end
    return math.floor(numCauldrons * CAULDRON_CHARGES / raidSize), numCauldrons
end

function HiddenLodge:GetCauldronSortedCounts(day)
    local counts = self:GetCauldronCounts(day)
    local sorted = {}
    for name, count in pairs(counts) do
        if type(count) == "number" then
            table.insert(sorted, { name = name, count = count })
        end
    end
    table.sort(sorted, function(a, b) return a.count > b.count end)
    return sorted
end

function HiddenLodge:GetCauldronDays()
    self.db.cauldron = self.db.cauldron or {}
    local days = {}
    for day in pairs(self.db.cauldron.days or {}) do
        if day:match("^%d%d%d%d%-%d%d%-%d%d$") then
            table.insert(days, day)
        end
    end
    table.sort(days)
    return days
end

function HiddenLodge:ResetCauldronDay(day)
    day = day or CurrentDayKey()
    self.db.cauldron = self.db.cauldron or {}
    self.db.cauldron.days = self.db.cauldron.days or {}
    self.db.cauldron.days[day] = { counts = {}, cauldrons = {} }
    self:RefreshCauldronFrame()
end

function HiddenLodge:ClearCauldronLog()
    self.db.cauldron = self.db.cauldron or {}
    self.db.cauldron.debugLog = {}
end

function HiddenLodge:RecordCauldronManual(who)
    who = who and strtrim(who) ~= "" and strtrim(who) or UnitName("player")
    local cauldrons = self:GetCauldronCauldrons()
    table.insert(cauldrons, { player = who, time = date("%H:%M") })
    self:RefreshCauldronFrame()
    return #cauldrons
end

function HiddenLodge:ShareCauldronCounts()
    local sorted = self:GetCauldronSortedCounts()
    if #sorted == 0 then
        return false, "nothing"
    end
    local channel = IsInRaid() and "RAID" or IsInGroup() and "PARTY" or nil
    if not channel then
        return false, "not-grouped"
    end
    C_ChatInfo.SendChatMessage("[Cauldron] Flask/Phial counts:", channel)
    for _, entry in ipairs(sorted) do
        C_ChatInfo.SendChatMessage(string.format("  %s: %d", entry.name, entry.count), channel)
    end
    return true
end

function HiddenLodge:PrintCauldronDay(day)
    local sorted = self:GetCauldronSortedCounts(day)
    if #sorted == 0 then
        self:Print("No flasks/phials tracked for " .. day .. ".")
        return
    end
    local allotment, numCauldrons = self:GetCauldronAllotment(day)
    if numCauldrons > 0 then
        self:Print(string.format("--- %s (%d cauldrons, %d per person) ---", day, numCauldrons, allotment))
    else
        self:Print("--- " .. day .. " ---")
    end
    for _, entry in ipairs(sorted) do
        local color = (allotment > 0 and entry.count > allotment) and "|cffff5555" or "|cff00ff00"
        self:Print(string.format("  %s%s|r: %d", color, entry.name, entry.count))
    end
end

function HiddenLodge:PrintAllCauldronDays()
    local days = self:GetCauldronDays()
    if #days == 0 then
        self:Print("No cauldron data.")
        return
    end
    for _, day in ipairs(days) do
        self:PrintCauldronDay(day)
    end
end

-- ===== Event handling =====

function HiddenLodge:HandleCauldronSpellCast(event, unit, castGUID, spellID)
    if not unit then return end
    local prefix = string.sub(unit, 1, 4)
    if prefix ~= "raid" and prefix ~= "part" and unit ~= "player" then return end
    -- IsSecret must run before any truthiness test: boolean-testing a secret
    -- value is itself an error under 12.0 semantics.
    if IsSecret(spellID) or not spellID then return end

    local matched = CAULDRON_SPELL_IDS[spellID]
    if not matched then
        local spellName = C_Spell.GetSpellName(spellID)
        if IsSecret(spellName) or not spellName then return end
        if not string.find(string.lower(spellName), "cauldron") then return end
        matched = spellName
    end
    if IsSecret(castGUID) then castGUID = nil end
    DebugPrint(self, string.format("UNIT_SPELLCAST_START cauldron: unit=%s spellID=%s spell=%s castGUID=%s",
        tostring(unit), tostring(spellID), tostring(matched), tostring(castGUID)))

    -- Dedup: same cast can fire for both "player" and "raidN" when you're the caster
    if castGUID and recentCastGUIDs[castGUID] then return end
    if castGUID then recentCastGUIDs[castGUID] = GetTime() end

    local sourceName = UnitName(unit)
    if IsSecret(sourceName) then return end
    local placer = StripRealm(sourceName) or "?"
    local now = GetTime()
    ActivateCauldron(now)
    local cauldrons = self:GetCauldronCauldrons()
    table.insert(cauldrons, { player = placer, time = date("%H:%M"),
        expiresAt = time() + CAULDRON_ACTIVE_DURATION })

    -- Any creates buffered before the spell fired are part of this cauldron —
    -- credit anything within one cauldron's duration; older than that is stale
    -- data from an unrelated, already-finished cauldron.
    local counts = self:GetCauldronCounts()
    for _, e in ipairs(recentCreates) do
        if now - e.time <= CAULDRON_ACTIVE_DURATION then
            local prev = counts[e.player] or 0
            counts[e.player] = prev + 1
            DebugPrint(self, string.format("  retroactive +1 for %s on placement (was %d, now %d)",
                e.player, prev, counts[e.player]))
        else
            DebugPrint(self, string.format("  dropped stale buffered create from %s (%.0fs old)",
                e.player, now - e.time))
        end
    end
    recentCreates = {}

    self:Print(string.format("%s placed a cauldron! (%d total today)", placer, #cauldrons))
    self:RefreshCauldronFrame()
end

function HiddenLodge:HandleCauldronLoot(event, msg, playerName)
    if IsSecret(msg) or not msg then
        DebugPrint(self, string.format("CHAT_MSG_LOOT skipped: msg=%s playerName=%s",
            IsSecret(msg) and "secret" or "nil",
            IsSecret(playerName) and "secret" or tostring(playerName)))
        return
    end
    DebugPrint(self, string.format("CHAT_MSG_LOOT raw msg=%q playerName=%s",
        msg, IsSecret(playerName) and "secret" or tostring(playerName)))
    local itemLink = string.match(msg, "|Hitem:.-%|h%[.-%]|h")
    if not itemLink then
        DebugPrint(self, "  no item link found, skipping")
        return
    end
    if not IsFleetingItem(itemLink) then
        DebugPrint(self, "  item is not Fleeting, skipping: " .. itemLink)
        return
    end

    -- Flask cauldrons hand out one item per charge (no stack). Personal alchemy crafts
    -- in stacks of 5+ ("x5"), so any x-quantity is bench crafting and should be ignored.
    local qty = tonumber(string.match(msg, "x(%d+)")) or 1
    if qty > 1 then
        DebugPrint(self, string.format("  skipping personal craft (qty=%d): %s", qty, itemLink))
        return
    end

    local player
    if not IsSecret(playerName) and playerName and playerName ~= "" then
        player = StripRealm(playerName)
        DebugPrint(self, "  player from playerName arg: " .. player)
    else
        player = UnitName("player")
        DebugPrint(self, "  player fallback to UnitName('player'): " .. tostring(player))
    end

    if not player or player == "" then
        DebugPrint(self, "  no player resolved, skipping")
        return
    end

    -- Dedup: WoW can fire the same event twice (once as "You create", once as group broadcast).
    local now = GetTime()
    local lootKey = player .. "|" .. itemLink
    local lastSeen = recentLootKeys[lootKey]
    if lastSeen and (now - lastSeen) < LOOT_DEDUP_WINDOW then
        DebugPrint(self, string.format("  DEDUP HIT: same %s create %.2fs ago, skipping", player, now - lastSeen))
        return
    end
    recentLootKeys[lootKey] = now
    if math.random() < 0.05 then
        for k, t in pairs(recentLootKeys) do
            if now - t > LOOT_DEDUP_WINDOW then recentLootKeys[k] = nil end
        end
    end

    -- Each create == 1 charge consumed, regardless of stack size.
    if now < cauldronActiveUntil then
        local counts = self:GetCauldronCounts()
        local prev = counts[player] or 0
        counts[player] = prev + 1
        DebugPrint(self, string.format("  counted +1 for %s (was %d, now %d) [active window]",
            player, prev, counts[player]))
        self:RefreshCauldronFrame()
        return
    end

    -- No active cauldron: buffer and check for a burst that implies one is active.
    -- Retention is a full cauldron duration (not just BURST_WINDOW) so that
    -- early stragglers aren't evicted before a later create pushes the
    -- distinct-player count over BURST_THRESHOLD — only the trigger check
    -- below is scoped to the tight recent window.
    tinsert(recentCreates, { time = now, player = player })
    while #recentCreates > 0 and (now - recentCreates[1].time) > CAULDRON_ACTIVE_DURATION do
        tremove(recentCreates, 1)
    end
    local uniqueN = CountUniquePlayersWithin(recentCreates, now, BURST_WINDOW)
    DebugPrint(self, string.format("  buffered (no active cauldron, %d events from %d players in trigger window)",
        #recentCreates, uniqueN))

    if uniqueN >= BURST_THRESHOLD then
        ActivateCauldron(now)
        local cauldrons = self:GetCauldronCauldrons()
        table.insert(cauldrons, { player = "?", time = date("%H:%M"),
            expiresAt = time() + CAULDRON_ACTIVE_DURATION })
        local counts = self:GetCauldronCounts()
        for _, e in ipairs(recentCreates) do
            local prev = counts[e.player] or 0
            counts[e.player] = prev + 1
            DebugPrint(self, string.format("  burst counted +1 for %s (was %d, now %d)",
                e.player, prev, counts[e.player]))
        end
        self:Print(string.format("Cauldron detected (burst of %d creates from %d players)! (%d total today)",
            #recentCreates, uniqueN, #cauldrons))
        recentCreates = {}
        self:RefreshCauldronFrame()
    end
end

function HiddenLodge:OnEnableCauldronTracker()
    -- Restore a still-active cauldron window across /reload so stragglers'
    -- flasks keep counting (each placement stores its expiry as epoch time).
    local nowEpoch = time()
    for day, data in pairs((self.db.cauldron and self.db.cauldron.days) or {}) do
        if type(data) == "table" and type(data.cauldrons) == "table" then
            for _, c in ipairs(data.cauldrons) do
                if type(c) == "table" and c.expiresAt and c.expiresAt > nowEpoch then
                    cauldronActiveUntil = math.max(cauldronActiveUntil,
                        GetTime() + (c.expiresAt - nowEpoch))
                    activeDayKey = day
                end
            end
        end
    end

    self:RegisterEvent("UNIT_SPELLCAST_START", "HandleCauldronSpellCast")
    self:RegisterEvent("CHAT_MSG_LOOT", "HandleCauldronLoot")
end

-- ===== UI =====

local cauldronFrame
local cauldronRowPool = {}

local function hideCauldronRows()
    for _, row in ipairs(cauldronRowPool) do
        row:Hide()
    end
end

local function getCauldronRow(parent, index)
    local row = cauldronRowPool[index]
    if row then
        return row
    end

    row = CreateFrame("Frame", nil, parent)
    row:SetHeight(20)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.name:SetPoint("RIGHT", row, "CENTER", 0, 0)
    row.name:SetJustifyH("LEFT")

    row.count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.count:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    row.count:SetJustifyH("RIGHT")

    cauldronRowPool[index] = row
    return row
end

local function ensureCauldronFrame()
    if cauldronFrame then
        return cauldronFrame
    end

    local parent = HiddenLodge and HiddenLodge.mainWindow or UIParent
    local c = HiddenLodge and HiddenLodge.GetUIConstants and HiddenLodge:GetUIConstants() or nil
    local outerInset = (c and (c.CONTENT_PADDING + 6)) or 22
    local innerInset = (c and c.INNER_PADDING) or 12
    local verticalGap = (c and c.VERTICAL_GAP) or 12
    local buttonHeight = (c and c.BUTTON_HEIGHT) or 24
    local frameWidth = 340
    local frameHeight = (c and c.WINDOW_HEIGHT) or 470

    cauldronFrame = CreateFrame("Frame", "HiddenLodgeCauldronFrame", parent, "BackdropTemplate")
    cauldronFrame:SetSize(frameWidth, frameHeight)
    if parent and parent ~= UIParent then
        cauldronFrame:SetPoint("CENTER", parent, "CENTER", 0, 0)
        cauldronFrame:SetFrameStrata(parent:GetFrameStrata())
        cauldronFrame:SetFrameLevel(parent:GetFrameLevel() + 20)
    else
        cauldronFrame:SetPoint("CENTER")
        cauldronFrame:SetFrameStrata("DIALOG")
    end
    cauldronFrame:SetClampedToScreen(true)
    cauldronFrame:SetMovable(true)
    cauldronFrame:EnableMouse(true)
    cauldronFrame:RegisterForDrag("LeftButton")
    cauldronFrame:SetScript("OnDragStart", cauldronFrame.StartMoving)
    cauldronFrame:SetScript("OnDragStop", cauldronFrame.StopMovingOrSizing)
    cauldronFrame:SetToplevel(true)
    cauldronFrame:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8x8",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    if c then
        cauldronFrame:SetBackdropColor(unpack(c.COLOR_BG))
        cauldronFrame:SetBackdropBorderColor(unpack(c.COLOR_BORDER))
    else
        cauldronFrame:SetBackdropColor(0.02, 0.05, 0.09, 0.97)
        cauldronFrame:SetBackdropBorderColor(0.70, 0.57, 0.24, 0.95)
    end

    local headerBar = CreateFrame("Frame", nil, cauldronFrame, "BackdropTemplate")
    headerBar:SetPoint("TOPLEFT", cauldronFrame, "TOPLEFT", outerInset, -outerInset)
    headerBar:SetPoint("TOPRIGHT", cauldronFrame, "TOPRIGHT", -outerInset, -outerInset)
    headerBar:SetHeight((c and c.HEADER_HEIGHT) or 38)
    headerBar:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8x8",
        edgeFile = "Interface/Buttons/WHITE8x8",
        tile = true,
        tileSize = 8,
        edgeSize = 1,
    })
    if c then
        headerBar:SetBackdropColor(unpack(c.COLOR_HEADER_BG))
        headerBar:SetBackdropBorderColor(unpack(c.COLOR_PANEL_BORDER))
    else
        headerBar:SetBackdropColor(0.06, 0.10, 0.16, 0.98)
        headerBar:SetBackdropBorderColor(0.30, 0.24, 0.11, 0.95)
    end

    cauldronFrame.title = headerBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    cauldronFrame.title:SetPoint("LEFT", headerBar, "LEFT", 14, 0)
    cauldronFrame.title:SetPoint("RIGHT", headerBar, "RIGHT", -30, 0)
    cauldronFrame.title:SetJustifyH("LEFT")
    cauldronFrame.title:SetTextColor(0.95, 0.82, 0.44)
    cauldronFrame.title:SetText("Cauldron Tracker")

    cauldronFrame.closeButton = CreateFrame("Button", nil, cauldronFrame, "UIPanelCloseButton")
    cauldronFrame.closeButton:SetPoint("TOPRIGHT", cauldronFrame, "TOPRIGHT", 2, 2)

    local content = CreateFrame("Frame", nil, cauldronFrame, "BackdropTemplate")
    content:SetPoint("TOPLEFT", cauldronFrame, "TOPLEFT", outerInset, -(outerInset + ((c and c.HEADER_HEIGHT) or 38) + verticalGap))
    content:SetPoint("BOTTOMRIGHT", cauldronFrame, "BOTTOMRIGHT", -outerInset, outerInset)
    content:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8x8",
        edgeFile = "Interface/Buttons/WHITE8x8",
        tile = true,
        tileSize = 8,
        edgeSize = 1,
    })
    if c then
        content:SetBackdropColor(unpack(c.COLOR_PANEL_BG))
        content:SetBackdropBorderColor(unpack(c.COLOR_PANEL_BORDER))
    else
        content:SetBackdropColor(0.03, 0.07, 0.12, 0.95)
        content:SetBackdropBorderColor(0.30, 0.24, 0.11, 0.95)
    end
    cauldronFrame.contentPanel = content

    local resetBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    resetBtn:SetSize(80, buttonHeight)
    resetBtn:SetPoint("TOPLEFT", content, "TOPLEFT", innerInset, -innerInset)
    resetBtn:SetText("Reset")
    HiddenLodge:ApplySecondaryButtonStyle(resetBtn)
    resetBtn:SetScript("OnClick", function()
        HiddenLodge:ResetCauldronDay()
    end)
    cauldronFrame.resetBtn = resetBtn

    local shareBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    shareBtn:SetSize(80, buttonHeight)
    shareBtn:SetPoint("LEFT", resetBtn, "RIGHT", 8, 0)
    shareBtn:SetText("Share")
    HiddenLodge:ApplySecondaryButtonStyle(shareBtn)
    shareBtn:SetScript("OnClick", function()
        local ok, reason = HiddenLodge:ShareCauldronCounts()
        if ok then
            HiddenLodge:SetStatus("Shared cauldron counts to chat.", 0.35, 0.95, 0.50)
        elseif reason == "not-grouped" then
            HiddenLodge:SetStatus("Not in a group.", 0.95, 0.90, 0.35)
        else
            HiddenLodge:SetStatus("Nothing to share.", 0.95, 0.90, 0.35)
        end
    end)
    cauldronFrame.shareBtn = shareBtn

    local header = CreateFrame("Frame", nil, content)
    header:SetPoint("TOPLEFT", resetBtn, "BOTTOMLEFT", 0, -verticalGap)
    header:SetPoint("TOPRIGHT", content, "TOPRIGHT", -(innerInset + 10), -(innerInset + buttonHeight + verticalGap))
    header:SetHeight(20)

    local hName = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hName:SetPoint("LEFT", header, "LEFT", 0, 0)
    hName:SetJustifyH("LEFT")
    hName:SetText("Player")

    local hCount = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hCount:SetPoint("RIGHT", header, "RIGHT", -10, 0)
    hCount:SetJustifyH("RIGHT")
    hCount:SetText("Count")

    cauldronFrame.summary = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cauldronFrame.summary:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", innerInset, innerInset)
    cauldronFrame.summary:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -innerInset, innerInset)
    cauldronFrame.summary:SetJustifyH("LEFT")
    cauldronFrame.summary:SetTextColor(0.78, 0.84, 0.93)

    cauldronFrame.scroll = CreateFrame("ScrollFrame", nil, content, "UIPanelScrollFrameTemplate")
    cauldronFrame.scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    cauldronFrame.scroll:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -(innerInset + 18), innerInset + 18)

    cauldronFrame.content = CreateFrame("Frame", nil, cauldronFrame.scroll)
    cauldronFrame.content:SetSize(frameWidth - (outerInset * 2) - (innerInset * 2), 1)
    cauldronFrame.scroll:SetScrollChild(cauldronFrame.content)

    if type(UISpecialFrames) == "table" then
        tinsert(UISpecialFrames, "HiddenLodgeCauldronFrame")
    end

    cauldronFrame:SetScript("OnShow", function(self)
        local currentParent = HiddenLodge and HiddenLodge.mainWindow or UIParent
        if currentParent and self:GetParent() ~= currentParent then
            self:SetParent(currentParent)
        end
        if currentParent and currentParent ~= UIParent then
            self:SetFrameStrata(currentParent:GetFrameStrata())
            self:SetFrameLevel(currentParent:GetFrameLevel() + 20)
            if currentParent.closeButton and currentParent.closeButton.Hide then
                currentParent.closeButton:Hide()
            end
        end
    end)

    cauldronFrame:SetScript("OnHide", function()
        local parentFrame = HiddenLodge and HiddenLodge.mainWindow or nil
        if parentFrame and parentFrame.closeButton and parentFrame.closeButton.Show then
            parentFrame.closeButton:Show()
        end
    end)

    return cauldronFrame
end

function HiddenLodge:RefreshCauldronFrame()
    if not cauldronFrame then
        return
    end

    local day = self:GetCauldronDayKey()
    local sorted = self:GetCauldronSortedCounts(day)
    local allotment, numCauldrons = self:GetCauldronAllotment(day)

    if numCauldrons > 0 then
        local label = numCauldrons == 1 and "cauldron" or "cauldrons"
        cauldronFrame.title:SetText(string.format("Cauldron — %d each (%d %s)", allotment, numCauldrons, label))
    else
        cauldronFrame.title:SetText("Cauldron — " .. day)
    end

    hideCauldronRows()

    if #sorted == 0 then
        cauldronFrame.content:SetHeight(1)
        cauldronFrame.summary:SetText("No flasks/phials tracked today.")
        return
    end

    local rowHeight = 20
    local y = -2
    local total = 0
    for i, entry in ipairs(sorted) do
        local row = getCauldronRow(cauldronFrame.content, i)
        row:SetPoint("TOPLEFT", cauldronFrame.content, "TOPLEFT", 0, y)
        row:SetPoint("RIGHT", cauldronFrame.content, "RIGHT", 0, 0)

        if i % 2 == 0 then
            row.bg:SetColorTexture(0.15, 0.15, 0.15, 0.4)
        else
            row.bg:SetColorTexture(0, 0, 0, 0)
        end

        local cr, cg, cb = 0, 1, 0
        if allotment > 0 and entry.count > allotment then
            cr, cg, cb = 1, 0.33, 0.33
        elseif allotment == 0 and entry.count > 1 then
            cr, cg, cb = 1, 0.33, 0.33
        end

        row.name:SetText(entry.name)
        row.name:SetTextColor(cr, cg, cb)
        row.count:SetText(tostring(entry.count))
        row.count:SetTextColor(cr, cg, cb)

        row:Show()
        y = y - rowHeight
        total = total + entry.count
    end

    cauldronFrame.content:SetHeight(math.max(-y, 1))
    if numCauldrons > 0 then
        local available = numCauldrons * CAULDRON_CHARGES
        cauldronFrame.summary:SetText(string.format("Picked up: %d of %d charges, %d players", total, available, #sorted))
    else
        cauldronFrame.summary:SetText(string.format("Picked up: %d flasks, %d players", total, #sorted))
    end
end

function HiddenLodge:ShowCauldronFrame()
    ensureCauldronFrame()
    self:RefreshCauldronFrame()
    cauldronFrame:Show()
end

function HiddenLodge:ToggleCauldronFrame()
    ensureCauldronFrame()
    if cauldronFrame:IsShown() then
        cauldronFrame:Hide()
    else
        self:RefreshCauldronFrame()
        cauldronFrame:Show()
    end
end
