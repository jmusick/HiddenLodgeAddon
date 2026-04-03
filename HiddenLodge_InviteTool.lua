---@diagnostic disable: inject-field, undefined-field, undefined-global
local addonName = ...
local HiddenLodge = LibStub("AceAddon-3.0"):GetAddon(addonName) --[[@as HiddenLodgeAddon]]

local INVITABLE_STATUSES = {
    ["coming"] = true,
    ["tentative"] = true,
    ["late"] = true,
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

local function getPlayerFullKey()
    local character, realm = UnitFullName("player")
    realm = realm or GetRealmName()
    return normalizedFullKey(character, realm)
end

local function getFullKeyFromCandidate(candidate)
    local character, realm = strsplit("-", tostring(candidate or ""), 2)
    if not realm or realm == "" then
        realm = GetRealmName()
    end
    return normalizedFullKey(character, realm)
end

local function isInGroupByCandidate(candidate)
    local target = getFullKeyFromCandidate(candidate)
    if target == "" then
        return false
    end

    if getPlayerFullKey() == target then
        return true
    end

    if IsInRaid() then
        local total = GetNumGroupMembers()
        for i = 1, total do
            local unit = "raid" .. i
            local character, realm = UnitFullName(unit)
            if character then
                realm = realm or GetRealmName()
                if normalizedFullKey(character, realm) == target then
                    return true
                end
            end
        end
        return false
    end

    local partyCount = GetNumSubgroupMembers()
    for i = 1, partyCount do
        local unit = "party" .. i
        local character, realm = UnitFullName(unit)
        if character then
            realm = realm or GetRealmName()
            if normalizedFullKey(character, realm) == target then
                return true
            end
        end
    end

    return false
end

local function canInviteToCurrentGroup()
    if C_PartyInfo and type(C_PartyInfo.CanInvite) == "function" then
        local ok, result = pcall(C_PartyInfo.CanInvite)
        if ok then
            return result and true or false
        end
    end

    if IsInRaid() then
        return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
    end
    if IsInGroup() then
        return UnitIsGroupLeader("player")
    end
    return true
end

function HiddenLodge:IsInvitableRaidSignupStatus(status)
    return INVITABLE_STATUSES[trim(status):lower()] and true or false
end

function HiddenLodge:CollectOnlineRaidSignupInviteRows()
    if not IsInGuild() then
        return {}, "You are not in a guild."
    end

    local store = self.db and self.db.raidSignup
    if type(store) ~= "table" or type(store.byFullStatus) ~= "table" then
        return {}, "Raid signup data is not synced yet."
    end

    if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    end

    local rows = {}
    local total = GetNumGuildMembers()
    for i = 1, total do
        local fullName, _, _, _, className, _, _, _, isOnline = GetGuildRosterInfo(i)
        if fullName and isOnline then
            local statusKey, statusLabel, signedAt = self:GetRaidSignupForCandidate(fullName)
            if self:IsInvitableRaidSignupStatus(statusKey) then
                local character = trim((fullName and fullName:match("^(.-)%-")) or fullName)
                rows[#rows + 1] = {
                    candidate = fullName,
                    name = character,
                    className = trim(className),
                    statusKey = statusKey,
                    statusLabel = statusLabel,
                    signedAt = signedAt,
                    inGroup = isInGroupByCandidate(fullName),
                }
            end
        end
    end

    table.sort(rows, function(a, b)
        local aRank = self:GetRaidSignupSortValue(a.statusKey)
        local bRank = self:GetRaidSignupSortValue(b.statusKey)
        if aRank ~= bRank then
            return aRank > bRank
        end
        return tostring(a.name or "") < tostring(b.name or "")
    end)

    return rows, nil
end

function HiddenLodge:InviteRaidSignupCandidate(candidate)
    if trim(candidate) == "" then
        return false, "invalid"
    end

    if not canInviteToCurrentGroup() then
        return false, "permission"
    end

    if isInGroupByCandidate(candidate) then
        return false, "already-grouped"
    end

    local ok = true
    if C_PartyInfo and type(C_PartyInfo.InviteUnit) == "function" then
        ok = pcall(C_PartyInfo.InviteUnit, candidate)
    else
        ok = pcall(InviteUnit, candidate)
    end

    if not ok then
        return false, "failed"
    end

    return true, nil
end

local inviteFrame
local inviteRowPool = {}

local function hideInviteRows()
    for _, row in ipairs(inviteRowPool) do
        row:Hide()
    end
end

local function getInviteRow(parent, index)
    local row = inviteRowPool[index]
    if row then
        return row
    end

    row = CreateFrame("Frame", nil, parent)
    row:SetHeight(22)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.name:SetWidth(180)
    row.name:SetJustifyH("LEFT")

    row.status = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.status:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
    row.status:SetWidth(110)
    row.status:SetJustifyH("LEFT")

    row.signedAt = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.signedAt:SetPoint("LEFT", row.status, "RIGHT", 8, 0)
    row.signedAt:SetWidth(90)
    row.signedAt:SetJustifyH("LEFT")

    row.group = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.group:SetPoint("LEFT", row.signedAt, "RIGHT", 8, 0)
    row.group:SetWidth(95)
    row.group:SetJustifyH("LEFT")

    row.inviteBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.inviteBtn:SetSize(70, 18)
    row.inviteBtn:SetPoint("LEFT", row.group, "RIGHT", 8, 0)
    row.inviteBtn:SetText("Invite")
    if HiddenLodge.ApplySecondaryButtonStyle then
        HiddenLodge:ApplySecondaryButtonStyle(row.inviteBtn)
    end

    inviteRowPool[index] = row
    return row
end

local function ensureInviteFrame()
    if inviteFrame then
        return inviteFrame
    end

    local parent = HiddenLodge and HiddenLodge.mainWindow or UIParent
    local c = HiddenLodge and HiddenLodge.GetUIConstants and HiddenLodge:GetUIConstants() or nil
    local outerInset = (c and (c.CONTENT_PADDING + 6)) or 22
    local innerInset = (c and c.INNER_PADDING) or 12
    local verticalGap = (c and c.VERTICAL_GAP) or 12
    local buttonHeight = (c and c.BUTTON_HEIGHT) or 24
    local frameWidth = (c and c.WINDOW_WIDTH) or 700
    local frameHeight = (c and c.WINDOW_HEIGHT) or 470

    inviteFrame = CreateFrame("Frame", "HiddenLodgeRaidInviteFrame", parent, "BackdropTemplate")
    inviteFrame:SetSize(frameWidth, frameHeight)
    if parent and parent ~= UIParent then
        inviteFrame:SetPoint("CENTER", parent, "CENTER", 0, 0)
        inviteFrame:SetFrameStrata(parent:GetFrameStrata())
        inviteFrame:SetFrameLevel(parent:GetFrameLevel() + 20)
    else
        inviteFrame:SetPoint("CENTER")
        inviteFrame:SetFrameStrata("DIALOG")
    end
    inviteFrame:SetClampedToScreen(true)
    inviteFrame:SetMovable(true)
    inviteFrame:EnableMouse(true)
    inviteFrame:RegisterForDrag("LeftButton")
    inviteFrame:SetScript("OnDragStart", inviteFrame.StartMoving)
    inviteFrame:SetScript("OnDragStop", inviteFrame.StopMovingOrSizing)
    inviteFrame:SetToplevel(true)
    inviteFrame:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8x8",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    if c then
        inviteFrame:SetBackdropColor(unpack(c.COLOR_BG))
        inviteFrame:SetBackdropBorderColor(unpack(c.COLOR_BORDER))
    else
        inviteFrame:SetBackdropColor(0.02, 0.05, 0.09, 0.97)
        inviteFrame:SetBackdropBorderColor(0.70, 0.57, 0.24, 0.95)
    end

    local headerBar = CreateFrame("Frame", nil, inviteFrame, "BackdropTemplate")
    headerBar:SetPoint("TOPLEFT", inviteFrame, "TOPLEFT", outerInset, -outerInset)
    headerBar:SetPoint("TOPRIGHT", inviteFrame, "TOPRIGHT", -outerInset, -outerInset)
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

    inviteFrame.title = headerBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    inviteFrame.title:SetPoint("LEFT", headerBar, "LEFT", 14, 0)
    inviteFrame.title:SetTextColor(0.95, 0.82, 0.44)
    inviteFrame.title:SetText("Hidden Lodge Invite Utility")

    inviteFrame.closeButton = CreateFrame("Button", nil, inviteFrame, "UIPanelCloseButton")
    inviteFrame.closeButton:SetPoint("TOPRIGHT", inviteFrame, "TOPRIGHT", 2, 2)

    local content = CreateFrame("Frame", nil, inviteFrame, "BackdropTemplate")
    content:SetPoint("TOPLEFT", inviteFrame, "TOPLEFT", outerInset, -(outerInset + ((c and c.HEADER_HEIGHT) or 38) + verticalGap))
    content:SetPoint("BOTTOMRIGHT", inviteFrame, "BOTTOMRIGHT", -outerInset, outerInset)
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
    inviteFrame.contentPanel = content

    local raidNameText = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    raidNameText:SetPoint("TOPLEFT", content, "TOPLEFT", innerInset, -innerInset)
    raidNameText:SetPoint("RIGHT", content, "RIGHT", -innerInset, 0)
    raidNameText:SetJustifyH("LEFT")
    raidNameText:SetTextColor(0.78, 0.84, 0.93)
    inviteFrame.raidNameText = raidNameText

    local refreshBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    refreshBtn:SetSize(100, buttonHeight)
    refreshBtn:SetPoint("TOPRIGHT", content, "TOPRIGHT", -(innerInset + 160 + 8), -innerInset)
    refreshBtn:SetText("Refresh")
    HiddenLodge:ApplySecondaryButtonStyle(refreshBtn)
    inviteFrame.refreshBtn = refreshBtn

    local inviteAllBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    inviteAllBtn:SetSize(160, buttonHeight)
    inviteAllBtn:SetPoint("LEFT", refreshBtn, "RIGHT", 8, 0)
    inviteAllBtn:SetText("Invite All Online")
    HiddenLodge:ApplySecondaryButtonStyle(inviteAllBtn)
    inviteFrame.inviteAllBtn = inviteAllBtn

    local header = CreateFrame("Frame", nil, content)
    header:SetPoint("TOPLEFT", raidNameText, "BOTTOMLEFT", 0, -verticalGap)
    header:SetPoint("TOPRIGHT", content, "TOPRIGHT", -(innerInset + 10), -(innerInset + buttonHeight + verticalGap))
    header:SetHeight(20)

    local function makeHeader(label, anchor, width)
        local fs = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("LEFT", anchor, "LEFT", 0, 0)
        fs:SetWidth(width)
        fs:SetJustifyH("LEFT")
        fs:SetText(label)
        return fs
    end

    local hName = makeHeader("Character", header, 180)
    local hStatus = makeHeader("Status", hName, 110)
    hStatus:SetPoint("LEFT", hName, "RIGHT", 8, 0)
    local hSignedAt = makeHeader("Signed", hStatus, 90)
    hSignedAt:SetPoint("LEFT", hStatus, "RIGHT", 8, 0)
    local hGroup = makeHeader("In Group", hSignedAt, 95)
    hGroup:SetPoint("LEFT", hSignedAt, "RIGHT", 8, 0)

    inviteFrame.summary = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    inviteFrame.summary:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", innerInset, innerInset)
    inviteFrame.summary:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -innerInset, innerInset)
    inviteFrame.summary:SetJustifyH("LEFT")

    inviteFrame.scroll = CreateFrame("ScrollFrame", nil, content, "UIPanelScrollFrameTemplate")
    inviteFrame.scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    inviteFrame.scroll:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -(innerInset + 18), innerInset + 18)

    inviteFrame.content = CreateFrame("Frame", nil, inviteFrame.scroll)
    inviteFrame.content:SetSize(frameWidth - (outerInset * 2) - (innerInset * 2), 1)
    inviteFrame.scroll:SetScrollChild(inviteFrame.content)

    if type(UISpecialFrames) == "table" then
        tinsert(UISpecialFrames, "HiddenLodgeRaidInviteFrame")
    end

    inviteFrame:SetScript("OnShow", function(self)
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

    inviteFrame:SetScript("OnHide", function()
        local parentFrame = HiddenLodge and HiddenLodge.mainWindow or nil
        if parentFrame and parentFrame.closeButton and parentFrame.closeButton.Show then
            parentFrame.closeButton:Show()
        end
    end)

    return inviteFrame
end

function HiddenLodge:RefreshRaidInviteFrame()
    local frame = ensureInviteFrame()
    local store = self.db and self.db.raidSignup and self.db.raidSignup.sync or nil
    local raidName = (store and trim(store.raidName)) or ""
    if raidName ~= "" then
        frame.raidNameText:SetText("Raid: " .. raidName)
    else
        frame.raidNameText:SetText("Raid: (not provided by latest sync)")
    end

    hideInviteRows()
    local rows, err = self:CollectOnlineRaidSignupInviteRows()
    frame.rows = rows

    if err then
        frame.summary:SetText(err)
        self:SetStatus(err, 0.95, 0.45, 0.35)
        frame.content:SetHeight(1)
        return
    end

    local rowHeight = 22
    local y = -2
    for i, rowData in ipairs(rows) do
        local row = getInviteRow(frame.content, i)
        row:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, y)
        row:SetPoint("RIGHT", frame.content, "RIGHT", 0, 0)

        if rowData.inGroup then
            row.bg:SetColorTexture(0.18, 0.33, 0.12, 0.32)
        else
            row.bg:SetColorTexture(0, 0, 0, 0)
        end

        row.name:SetText(rowData.name ~= "" and rowData.name or "-")
        row.signedAt:SetText(self:FormatRaidSignupSignedAt(rowData.signedAt))
        row.group:SetText(rowData.inGroup and "Yes" or "No")

        local sr, sg, sb = self:GetRaidSignupColor(rowData.statusKey)
        row.status:SetText(rowData.statusLabel or "-")
        row.status:SetTextColor(sr, sg, sb)

        row.inviteBtn:SetEnabled(not rowData.inGroup)
        row.inviteBtn:SetScript("OnClick", function()
            local invited, reason = self:InviteRaidSignupCandidate(rowData.candidate)
            if invited then
                self:SetStatus("Invited " .. tostring(rowData.name or rowData.candidate) .. ".", 0.35, 0.95, 0.50)
            elseif reason == "already-grouped" then
                self:SetStatus(tostring(rowData.name or rowData.candidate) .. " is already in your group.", 0.95, 0.90, 0.35)
            elseif reason == "permission" then
                self:SetStatus("You do not have permission to invite to this group.", 0.95, 0.45, 0.35)
            else
                self:SetStatus("Invite failed for " .. tostring(rowData.name or rowData.candidate) .. ".", 0.95, 0.45, 0.35)
            end
            self:RefreshRaidInviteFrame()
        end)

        row:Show()
        y = y - rowHeight
    end

    frame.content:SetHeight(math.max(#rows * rowHeight + 6, 1))
    frame.summary:SetText(string.format("Online signed-up members: %d", #rows))
    if #rows > 0 then
        self:SetStatus(string.format("Loaded %d online signed-up members.", #rows), 0.35, 0.95, 0.50)
    else
        self:SetStatus("No online signed-up guild members found.", 0.95, 0.90, 0.35)
    end
end

function HiddenLodge:InviteAllOnlineRaidSignupMembers()
    local rows, err = self:CollectOnlineRaidSignupInviteRows()
    if err then
        self:SetStatus(err, 0.95, 0.45, 0.35)
        return
    end

    if #rows == 0 then
        self:SetStatus("No online signed-up guild members to invite.", 0.95, 0.90, 0.35)
        return
    end

    if not canInviteToCurrentGroup() then
        self:SetStatus("You do not have permission to invite to this group.", 0.95, 0.45, 0.35)
        return
    end

    local invited = 0
    local alreadyGrouped = 0
    local failed = 0

    for _, row in ipairs(rows) do
        local ok, reason = self:InviteRaidSignupCandidate(row.candidate)
        if ok then
            invited = invited + 1
        elseif reason == "already-grouped" then
            alreadyGrouped = alreadyGrouped + 1
        else
            failed = failed + 1
        end
    end

    self:SetStatus(
        string.format("Raid invites: invited %d, already grouped %d, failed %d.", invited, alreadyGrouped, failed),
        failed > 0 and 0.95 or 0.35,
        failed > 0 and 0.45 or 0.95,
        failed > 0 and 0.35 or 0.50
    )
    self:RefreshRaidInviteFrame()
end

function HiddenLodge:ShowRaidInviteFrame()
    local frame = ensureInviteFrame()
    self:RefreshRaidInviteFrame()

    frame.refreshBtn:SetScript("OnClick", function()
        self:RefreshRaidInviteFrame()
    end)
    frame.inviteAllBtn:SetScript("OnClick", function()
        self:InviteAllOnlineRaidSignupMembers()
    end)

    frame:Show()
end
