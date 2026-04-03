---@diagnostic disable: inject-field, undefined-field, undefined-global
local addonName = ...
local HiddenLodge = LibStub("AceAddon-3.0"):GetAddon(addonName) --[[@as HiddenLodgeAddon]]

local function trim(value)
    return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function normalize(value)
    return trim(value):lower()
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

local function canEditPublicNotes()
    if type(CanEditPublicNote) == "function" then
        local ok, result = pcall(CanEditPublicNote)
        if ok then
            return result and true or false
        end
    end

    if C_GuildInfo and type(C_GuildInfo.CanEditPublicNote) == "function" then
        local ok, result = pcall(C_GuildInfo.CanEditPublicNote)
        if ok then
            return result and true or false
        end
    end

    return false
end

local function getDesiredNote(db, fullName)
    if not db then
        return nil
    end

    local byName = db.preferredByName or {}
    local normalizedFull = normalize(fullName)
    local simpleName = normalize((fullName and fullName:match("^(.-)%-")) or fullName)

    local function cleanDesired(value)
        local desired = trim(value)
        if desired == "" then
            return nil
        end
        if simpleName ~= "" and normalize(desired) == simpleName then
            return nil
        end
        return desired
    end

    if simpleName ~= "" and byName[simpleName] ~= nil then
        local desired = cleanDesired(byName[simpleName])
        if desired then
            return desired
        end
    end

    if normalizedFull ~= "" and byName[normalizedFull] ~= nil then
        local desired = cleanDesired(byName[normalizedFull])
        if desired then
            return desired
        end
    end

    return nil
end

local function collectGuildNoteRows(db)
    local rows = {}
    local managed = 0
    local mismatchCount = 0

    local mainByName = (db and db.mainByName) or {}
    local nicknameByName = (db and db.nicknameByName) or {}

    local total = GetNumGuildMembers()
    for i = 1, total do
        local fullName, _, _, _, _, _, publicNote = GetGuildRosterInfo(i)
        if fullName then
            local desired = getDesiredNote(db, fullName)
            if desired ~= nil then
                managed = managed + 1
                local character = trim((fullName and fullName:match("^(.-)%-")) or fullName)
                local key = normalize(character)
                local main = trim(mainByName[key])
                local nickname = trim(nicknameByName[key])
                local current = trim(publicNote)
                local isMismatch = normalize(current) ~= normalize(desired)

                if isMismatch then
                    mismatchCount = mismatchCount + 1
                end

                rows[#rows + 1] = {
                    index = i,
                    fullName = fullName,
                    name = character,
                    main = main,
                    nickname = nickname,
                    desired = desired,
                    current = current,
                    mismatch = isMismatch,
                }
            end
        end
    end

    table.sort(rows, function(a, b)
        return tostring(a.name or "") < tostring(b.name or "")
    end)

    return rows, managed, mismatchCount
end

local function collectGuildNoteDiffs(db)
    local rows, managed = collectGuildNoteRows(db)
    local diffs = {}
    for _, row in ipairs(rows) do
        if row.mismatch then
            diffs[#diffs + 1] = row
        end
    end
    return diffs, managed
end

StaticPopupDialogs["HIDDENLODGE_COPY_NOTE"] = {
    text = "Ctrl+C to copy, then close.",
    button1 = "Close",
    hasEditBox = true,
    editBoxWidth = 320,
    maxLetters = 0,
    OnShow = function(self, data)
        local editBox = self.EditBox
        editBox:SetMultiLine(false)
        editBox:SetWidth(320)
        editBox:SetHeight(28)
        editBox:SetText(data or "")
        editBox:SetFocus()
        editBox:HighlightText()
    end,
    EditBoxOnEnterPressed = function(self)
        self:GetParent():Hide()
    end,
    EditBoxOnEscapePressed = function(self)
        self:GetParent():Hide()
    end,
    OnButton1 = function(self)
        self:Hide()
    end,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local reportFrame
local reportRowPool = {}

local function getReportRow(parent, index)
    local row = reportRowPool[index]
    if row then
        return row
    end

    row = CreateFrame("Frame", nil, parent)
    row:SetHeight(22)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.name:SetWidth(145)
    row.name:SetJustifyH("LEFT")

    row.main = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.main:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
    row.main:SetWidth(145)
    row.main:SetJustifyH("LEFT")

    row.nickname = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.nickname:SetPoint("LEFT", row.main, "RIGHT", 8, 0)
    row.nickname:SetWidth(120)
    row.nickname:SetJustifyH("LEFT")

    row.desired = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.desired:SetPoint("LEFT", row.nickname, "RIGHT", 8, 0)
    row.desired:SetWidth(130)
    row.desired:SetJustifyH("LEFT")

    row.current = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.current:SetPoint("LEFT", row.desired, "RIGHT", 8, 0)
    row.current:SetWidth(130)
    row.current:SetJustifyH("LEFT")

    row.copyBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.copyBtn:SetSize(50, 18)
    row.copyBtn:SetPoint("LEFT", row.current, "RIGHT", 8, 0)
    row.copyBtn:SetText("Copy")
    if HiddenLodge.ApplySecondaryButtonStyle then
        HiddenLodge:ApplySecondaryButtonStyle(row.copyBtn)
    end

    reportRowPool[index] = row
    return row
end

local function hideReportRows()
    for _, row in ipairs(reportRowPool) do
        row:Hide()
    end
end

local function ensureReportFrame()
    if reportFrame then
        return reportFrame
    end

    local parent = HiddenLodge and HiddenLodge.mainWindow or UIParent
    local c = HiddenLodge and HiddenLodge.GetUIConstants and HiddenLodge:GetUIConstants() or nil
    local outerInset = (c and (c.CONTENT_PADDING + 6)) or 22
    local innerInset = (c and c.INNER_PADDING) or 12
    local verticalGap = (c and c.VERTICAL_GAP) or 12
    local headerHeight = (c and c.HEADER_HEIGHT) or 38

    reportFrame = CreateFrame("Frame", "HiddenLodgeMismatchReportFrame", parent, "BackdropTemplate")
    reportFrame:SetSize(860, 500)
    if parent and parent ~= UIParent then
        reportFrame:SetPoint("CENTER", parent, "CENTER", 0, 0)
        reportFrame:SetFrameStrata(parent:GetFrameStrata())
        reportFrame:SetFrameLevel(parent:GetFrameLevel() + 20)
    else
        reportFrame:SetPoint("CENTER")
        reportFrame:SetFrameStrata("DIALOG")
    end
    reportFrame:SetClampedToScreen(true)
    reportFrame:SetMovable(true)
    reportFrame:EnableMouse(true)
    reportFrame:RegisterForDrag("LeftButton")
    reportFrame:SetScript("OnDragStart", reportFrame.StartMoving)
    reportFrame:SetScript("OnDragStop", reportFrame.StopMovingOrSizing)
    reportFrame:SetToplevel(true)
    reportFrame:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8x8",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    if c then
        reportFrame:SetBackdropColor(unpack(c.COLOR_BG))
        reportFrame:SetBackdropBorderColor(unpack(c.COLOR_BORDER))
    else
        reportFrame:SetBackdropColor(0.02, 0.05, 0.09, 0.97)
        reportFrame:SetBackdropBorderColor(0.70, 0.57, 0.24, 0.95)
    end

    local headerBar = CreateFrame("Frame", nil, reportFrame, "BackdropTemplate")
    headerBar:SetPoint("TOPLEFT", reportFrame, "TOPLEFT", outerInset, -outerInset)
    headerBar:SetPoint("TOPRIGHT", reportFrame, "TOPRIGHT", -outerInset, -outerInset)
    headerBar:SetHeight(headerHeight)
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
    reportFrame.headerBar = headerBar

    reportFrame.title = headerBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    reportFrame.title:SetPoint("LEFT", headerBar, "LEFT", 14, 0)
    reportFrame.title:SetTextColor(0.95, 0.82, 0.44)
    reportFrame.title:SetText("Hidden Lodge Mismatched Notes Utility")

    reportFrame.closeButton = CreateFrame("Button", nil, reportFrame, "UIPanelCloseButton")
    reportFrame.closeButton:SetPoint("TOPRIGHT", reportFrame, "TOPRIGHT", 2, 2)

    local content = CreateFrame("Frame", nil, reportFrame, "BackdropTemplate")
    content:SetPoint("TOPLEFT", reportFrame, "TOPLEFT", outerInset, -(outerInset + headerHeight + verticalGap))
    content:SetPoint("BOTTOMRIGHT", reportFrame, "BOTTOMRIGHT", -outerInset, outerInset)
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
    reportFrame.contentPanel = content

    local header = CreateFrame("Frame", nil, content)
    header:SetPoint("TOPLEFT", content, "TOPLEFT", innerInset, -innerInset)
    header:SetPoint("TOPRIGHT", content, "TOPRIGHT", -(innerInset + 10), -innerInset)
    header:SetHeight(20)

    local function makeHeader(label, anchor, width)
        local fs = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("LEFT", anchor, "LEFT", 0, 0)
        fs:SetWidth(width)
        fs:SetJustifyH("LEFT")
        fs:SetText(label)
        return fs
    end

    local hName = makeHeader("Character", header, 145)
    local hMain = makeHeader("Main", hName, 145)
    hMain:SetPoint("LEFT", hName, "RIGHT", 8, 0)
    local hNick = makeHeader("Nickname", hMain, 120)
    hNick:SetPoint("LEFT", hMain, "RIGHT", 8, 0)
    local hDesired = makeHeader("Desired Note", hNick, 130)
    hDesired:SetPoint("LEFT", hNick, "RIGHT", 8, 0)
    local hCurrent = makeHeader("Current Note", hDesired, 130)
    hCurrent:SetPoint("LEFT", hDesired, "RIGHT", 8, 0)

    reportFrame.summary = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    reportFrame.summary:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", innerInset, innerInset)
    reportFrame.summary:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -innerInset, innerInset)
    reportFrame.summary:SetJustifyH("LEFT")

    reportFrame.scroll = CreateFrame("ScrollFrame", nil, content, "UIPanelScrollFrameTemplate")
    reportFrame.scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    reportFrame.scroll:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -(innerInset + 18), innerInset + 18)

    reportFrame.content = CreateFrame("Frame", nil, reportFrame.scroll)
    reportFrame.content:SetSize(800, 1)
    reportFrame.scroll:SetScrollChild(reportFrame.content)

    if type(UISpecialFrames) == "table" then
        tinsert(UISpecialFrames, "HiddenLodgeMismatchReportFrame")
    end

    reportFrame:SetScript("OnShow", function(self)
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

    reportFrame:SetScript("OnHide", function()
        local parentFrame = HiddenLodge and HiddenLodge.mainWindow or nil
        if parentFrame and parentFrame.closeButton and parentFrame.closeButton.Show then
            parentFrame.closeButton:Show()
        end
    end)

    return reportFrame
end

function HiddenLodge:ShowAltNoteMismatches()
    if not IsInGuild() then
        self:SetStatus("You are not in a guild.", 0.95, 0.45, 0.35)
        return
    end

    local store = self.db and self.db.altNoteSync
    if type(store) ~= "table" then
        self:SetStatus("Alt-note sync data not found.", 0.95, 0.45, 0.35)
        return
    end

    if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    end

    local rows, managed, mismatchCount = collectGuildNoteRows(store)
    if managed <= 0 then
        self:SetStatus("No guild members are managed by synced alt-note data.", 0.95, 0.70, 0.35)
        return
    end

    local frame = ensureReportFrame()
    hideReportRows()

    local rowHeight = 22
    local y = -2
    for i, rowData in ipairs(rows) do
        local row = getReportRow(frame.content, i)
        row:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, y)
        row:SetPoint("RIGHT", frame.content, "RIGHT", 0, 0)

        local isMismatch = rowData.mismatch
        if isMismatch then
            row.bg:SetColorTexture(0.65, 0.12, 0.12, 0.35)
        else
            row.bg:SetColorTexture(0, 0, 0, 0)
        end

        row.name:SetText(rowData.name ~= "" and rowData.name or "-")
        row.main:SetText(rowData.main ~= "" and rowData.main or "-")
        row.nickname:SetText(rowData.nickname ~= "" and rowData.nickname or "-")
        row.desired:SetText(rowData.desired ~= "" and rowData.desired or "-")
        row.current:SetText(rowData.current ~= "" and rowData.current or "-")

        local tr, tg, tb = 0.92, 0.92, 0.92
        if isMismatch then
            tr, tg, tb = 1.0, 0.72, 0.72
        end
        row.name:SetTextColor(tr, tg, tb)
        row.main:SetTextColor(tr, tg, tb)
        row.nickname:SetTextColor(tr, tg, tb)
        row.desired:SetTextColor(tr, tg, tb)
        row.current:SetTextColor(tr, tg, tb)

        row.copyBtn:SetScript("OnClick", function()
            StaticPopup_Show("HIDDENLODGE_COPY_NOTE", nil, nil, rowData.desired or "")
        end)

        row:Show()
        y = y - rowHeight
    end

    frame.content:SetHeight(math.max(#rows * rowHeight + 6, 1))
    frame.summary:SetText(string.format(
        "Managed characters: %d   |   Mismatched notes: %d (red rows)",
        managed,
        mismatchCount
    ))
    frame:Show()

    if mismatchCount > 0 then
        self:SetStatus(string.format("Found %d mismatched notes.", mismatchCount), 0.95, 0.82, 0.40)
    else
        self:SetStatus("All managed guild notes are in sync.", 0.35, 0.95, 0.50)
    end
end

function HiddenLodge:TryAutoApplyAltNotes()
    if self._altNoteSyncApplying then
        return
    end
    if not IsInGuild() then
        return
    end

    local store = self.db and self.db.altNoteSync
    if type(store) ~= "table" then
        return
    end

    local sync = store.sync or {}
    local syncedAt = tonumber(sync.syncedAt) or 0
    local entries = tonumber(sync.entries) or 0
    if syncedAt <= 0 or entries <= 0 then
        return
    end

    local lastApplied = tonumber(store.lastAppliedSyncedAt) or 0
    if syncedAt <= lastApplied then
        return
    end

    if not canEditPublicNotes() then
        return
    end

    if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    end

    local diffs, managed = collectGuildNoteDiffs(store)
    if #diffs == 0 then
        store.lastAppliedSyncedAt = syncedAt
        if managed > 0 then
            self:Print("Alt-note sync: guild notes already up to date.")
        end
        return
    end

    self._altNoteSyncApplying = true
    local applied = 0
    for _, row in ipairs(diffs) do
        local ok = pcall(GuildRosterSetPublicNote, row.index, row.desired)
        if ok then
            applied = applied + 1
        end
    end
    self._altNoteSyncApplying = false

    store.lastAppliedSyncedAt = syncedAt
    self:Print(string.format("Alt-note sync applied: %d updated (%d managed).", applied, managed))
end

function HiddenLodge:HandleAltNoteSyncGuildEvent()
    self:TryAutoApplyAltNotes()
end

function HiddenLodge:OnEnableAltNoteSync()
    self:RegisterEvent("GUILD_ROSTER_UPDATE", "HandleAltNoteSyncGuildEvent")
    self:RegisterEvent("PLAYER_GUILD_UPDATE", "HandleAltNoteSyncGuildEvent")

    if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    end
    self:TryAutoApplyAltNotes()
end

function HiddenLodge:GetAltNoteSyncStatus()
    local store = self.db and self.db.altNoteSync or {}
    local sync = (store and store.sync) or {}

    local source = trim(sync.source)
    if source == "" then
        source = "Unknown"
    end

    local entries = tonumber(sync.entries)
    if not entries or entries <= 0 then
        entries = countEntries(store.preferredByName)
    end

    if source == "Unknown" and entries > 0 then
        source = "HiddenLodgeDesktop (legacy)"
    end

    return {
        source = source,
        entries = entries,
        syncedAt = tonumber(sync.syncedAt) or 0,
        lastAppliedSyncedAt = tonumber(store.lastAppliedSyncedAt) or 0,
    }
end
