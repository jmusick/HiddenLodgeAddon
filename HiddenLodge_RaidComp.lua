---@diagnostic disable: inject-field, undefined-field, undefined-global
local addonName = ...
local HiddenLodge = LibStub("AceAddon-3.0"):GetAddon(addonName) --[[@as HiddenLodgeAddon]]

local EXPORT_TAG = "HLRC1"
local MAX_GROUP_SIZE = 5
local DOWNSIZE_INFO_URL = "https://hidden-lodge.com/raid-composition"

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

local function canOrganizeRaid()
    if not IsInRaid() then
        return false
    end
    return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
end

local function classColor(classToken)
    local info = classToken ~= "" and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken] or nil
    if info then
        return info.r, info.g, info.b
    end
    return 0.90, 0.90, 0.90
end

--------------------------------------------------------------------------
-- Parsing the website's export string
--------------------------------------------------------------------------

--- Format (produced by Raid Composition's "Export to Addon" button):
---   "HLRC1|Name-Realm:Group:CLASSTOKEN,Name2-Realm2:Group:CLASSTOKEN,..."
--- The website strips spaces/hyphens/apostrophes from realm names before
--- building the key, so "-" unambiguously separates character from realm. A
--- temp/PUG candidate has no realm at all (bare "Name:Group:CLASSTOKEN") and
--- is matched by name only, regardless of which realm that character is
--- actually on.
function HiddenLodge:ParseRaidCompImportString(rawText)
    local text = trim(rawText)
    if text == "" then
        return nil, "Paste the export string from the Raid Composition page first."
    end

    local tag, body = strsplit("|", text, 2)
    if trim(tag) ~= EXPORT_TAG or not body or trim(body) == "" then
        return nil, "That doesn't look like a Raid Comp export string."
    end

    local entries = {}
    local maxGroup = 0

    for chunk in body:gmatch("[^,]+") do
        local key, groupStr, classToken = strsplit(":", trim(chunk), 3)
        local group = tonumber(groupStr)
        if key and key ~= "" and group and group > 0 then
            local character, realm = strsplit("-", key, 2)
            character = trim(character)
            realm = realm and trim(realm) or ""
            if character ~= "" then
                entries[#entries + 1] = {
                    fullKey = normalizedFullKey(character, realm),
                    nameKey = normalizeName(character),
                    candidate = realm ~= "" and (character .. "-" .. realm) or character,
                    name = character,
                    group = group,
                    classToken = trim(classToken or ""),
                }
                if group > maxGroup then
                    maxGroup = group
                end
            end
        end
    end

    if #entries == 0 then
        return nil, "No raiders found in that export string."
    end

    return { entries = entries, groupCount = maxGroup }
end

function HiddenLodge:ImportRaidCompString(rawText)
    local parsed, err = self:ParseRaidCompImportString(rawText)
    if not parsed then
        return false, err
    end

    self.db.raidComp = {
        entries = parsed.entries,
        importedAt = time(),
        groupCount = parsed.groupCount,
    }

    return true, #parsed.entries, parsed.groupCount
end

--------------------------------------------------------------------------
-- Matching the imported comp against who's actually in the raid right now
--------------------------------------------------------------------------

local function currentGroupCounts()
    local counts = {}
    if not IsInRaid() then
        return counts
    end
    local total = GetNumGroupMembers()
    for i = 1, total do
        local _, _, subgroup = GetRaidRosterInfo(i)
        if subgroup then
            counts[subgroup] = (counts[subgroup] or 0) + 1
        end
    end
    return counts
end

function HiddenLodge:CollectRaidCompRows()
    local store = self.db and self.db.raidComp
    if not store or type(store.entries) ~= "table" or #store.entries == 0 then
        return {}, "No raid comp imported yet. Paste an export string from the Raid Composition page first."
    end

    local inRaidByFullKey = {}
    local inRaidByNameKey = {}
    if IsInRaid() then
        local total = GetNumGroupMembers()
        for i = 1, total do
            local character, realm = UnitFullName("raid" .. i)
            if character then
                realm = realm or GetRealmName()
                local _, _, subgroup = GetRaidRosterInfo(i)
                local info = { raidIndex = i, subgroup = subgroup }
                inRaidByFullKey[normalizedFullKey(character, realm)] = info
                local nameKey = normalizeName(character)
                if not inRaidByNameKey[nameKey] then
                    inRaidByNameKey[nameKey] = info
                end
            end
        end
    end

    local rows = {}
    for _, entry in ipairs(store.entries) do
        local info = inRaidByFullKey[entry.fullKey] or inRaidByNameKey[entry.nameKey]
        rows[#rows + 1] = {
            entry = entry,
            inRaid = info ~= nil,
            currentGroup = info and info.subgroup or nil,
            raidIndex = info and info.raidIndex or nil,
            correct = info ~= nil and info.subgroup == entry.group,
        }
    end

    table.sort(rows, function(a, b)
        if a.entry.group ~= b.entry.group then
            return a.entry.group < b.entry.group
        end
        return tostring(a.entry.name) < tostring(b.entry.name)
    end)

    return rows, nil
end

--------------------------------------------------------------------------
-- Invite
--------------------------------------------------------------------------

--- Reuses HiddenLodge:InviteRaidSignupCandidate (HiddenLodge_InviteTool.lua) —
--- it already handles the permission check, skipping anyone already grouped,
--- and the actual InviteUnit call, and none of that logic is specific to the
--- raid-signup flow it was written for.
function HiddenLodge:InviteMissingRaidCompMembers()
    local rows, err = self:CollectRaidCompRows()
    if err then
        self:SetStatus(err, 0.95, 0.45, 0.35)
        return
    end

    local pending = {}
    for _, row in ipairs(rows) do
        if not row.inRaid then
            pending[#pending + 1] = row
        end
    end

    if #pending == 0 then
        self:SetStatus("Everyone in the raid comp is already in your group.", 0.35, 0.95, 0.50)
        self:RefreshRaidCompFrame()
        return
    end

    local invited, alreadyGrouped, failed = 0, 0, 0
    for _, row in ipairs(pending) do
        local ok, reason = self:InviteRaidSignupCandidate(row.entry.candidate)
        if ok then
            invited = invited + 1
        elseif reason == "already-grouped" then
            alreadyGrouped = alreadyGrouped + 1
        else
            failed = failed + 1
        end
    end

    self:SetStatus(
        string.format("Raid Comp invites: invited %d, already grouped %d, failed %d.", invited, alreadyGrouped, failed),
        failed > 0 and 0.95 or 0.35,
        failed > 0 and 0.45 or 0.95,
        failed > 0 and 0.35 or 0.50
    )
    self:RefreshRaidCompFrame()
end

--------------------------------------------------------------------------
-- Downsize whispers
--------------------------------------------------------------------------

local function buildDownsizeMessage()
    return "Hey! We've downsized for this pull and you're not currently slotted in the comp"
        .. " — no worries, feel free to drop group. Check the website's Raid Composition tool"
        .. " for more info: " .. DOWNSIZE_INFO_URL
end

--- Raid members currently grouped whose character isn't among the imported
--- comp's entries (by full name-realm key, falling back to name-only the same
--- way CollectRaidCompRows does). Excludes the player themselves.
function HiddenLodge:CollectRaidCompCutRows()
    local store = self.db and self.db.raidComp
    if not store or type(store.entries) ~= "table" or #store.entries == 0 then
        return {}, "No raid comp imported yet. Paste an export string from the Raid Composition page first."
    end

    if not IsInRaid() then
        return {}, "You are not in a raid."
    end

    local entryFullKeys, entryNameKeys = {}, {}
    for _, entry in ipairs(store.entries) do
        if entry.fullKey ~= "" then
            entryFullKeys[entry.fullKey] = true
        end
        if entry.nameKey ~= "" then
            entryNameKeys[entry.nameKey] = true
        end
    end

    local rows = {}
    local total = GetNumGroupMembers()
    for i = 1, total do
        local unit = "raid" .. i
        if not UnitIsUnit(unit, "player") then
            local character, realm = UnitFullName(unit)
            if character then
                realm = realm or GetRealmName()
                local fullKey = normalizedFullKey(character, realm)
                local nameKey = normalizeName(character)
                if not entryFullKeys[fullKey] and not entryNameKeys[nameKey] then
                    rows[#rows + 1] = {
                        name = character,
                        candidate = realm ~= "" and (character .. "-" .. realm) or character,
                    }
                end
            end
        end
    end

    table.sort(rows, function(a, b)
        return tostring(a.name) < tostring(b.name)
    end)

    return rows, nil
end

StaticPopupDialogs["HIDDENLODGE_WHISPER_DOWNSIZE_CUTS"] = {
    text = "Whisper %d raider(s) not in the imported comp that they can drop group for downsizing?",
    button1 = "Whisper",
    button2 = "Cancel",
    OnAccept = function(self)
        local rows = self.data
        if type(rows) ~= "table" then
            return
        end

        local message = buildDownsizeMessage()
        local sent, failed = 0, 0
        for _, row in ipairs(rows) do
            local ok = pcall(C_ChatInfo.SendChatMessage, message, "WHISPER", nil, row.candidate)
            if ok then
                sent = sent + 1
            else
                failed = failed + 1
            end
        end

        HiddenLodge:SetStatus(
            string.format("Whispered %d raider(s) about downsizing%s.", sent, failed > 0 and (", " .. failed .. " failed") or ""),
            failed > 0 and 0.95 or 0.35,
            failed > 0 and 0.70 or 0.95,
            failed > 0 and 0.35 or 0.50
        )
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

--- Requires raid lead/assist, same as OrganizeRaidCompGroups — this messages
--- real players, so it's gated the same way and confirmed before sending.
function HiddenLodge:WhisperDownsizedRaidCompMembers()
    if not canOrganizeRaid() then
        self:SetStatus("You must be raid leader or an assistant to whisper downsize notices.", 0.95, 0.45, 0.35)
        return
    end

    local rows, err = self:CollectRaidCompCutRows()
    if err then
        self:SetStatus(err, 0.95, 0.45, 0.35)
        return
    end

    if #rows == 0 then
        self:SetStatus("Everyone currently in the raid is part of the imported comp.", 0.35, 0.95, 0.50)
        return
    end

    StaticPopup_Show("HIDDENLODGE_WHISPER_DOWNSIZE_CUTS", #rows, nil, rows)
end

--------------------------------------------------------------------------
-- Organize
--------------------------------------------------------------------------

--- Moves everyone already in the raid into the subgroup the comp assigns
--- them. Runs once per click rather than looping/waiting: a subgroup change
--- is a request to the server, so the local roster only reflects it after a
--- round trip, and looping off a stale snapshot risks issuing conflicting
--- moves. Within a single snapshot this resolves every reciprocal pair (A
--- wants B's group, B wants A's — C_PartyInfo.SwapRaidSubgroup needs no free
--- slot on either side) plus anyone whose target group already has room.
--- Longer cycles (A -> B -> C -> A) or moves blocked on a full target group
--- are left in place and reported — best-effort, like Raid Comp's own
--- coverage pass on the website. Clicking Organize Groups again after the
--- first round of moves lands (a second or two) resolves those too, since
--- by then the snapshot reflects the moves already made.
function HiddenLodge:OrganizeRaidCompGroups()
    if not canOrganizeRaid() then
        self:SetStatus("You must be raid leader or an assistant to organize groups.", 0.95, 0.45, 0.35)
        return
    end

    local rows, err = self:CollectRaidCompRows()
    if err then
        self:SetStatus(err, 0.95, 0.45, 0.35)
        return
    end

    local misplaced = {}
    for _, row in ipairs(rows) do
        if row.inRaid and not row.correct then
            misplaced[#misplaced + 1] = row
        end
    end

    if #misplaced == 0 then
        self:SetStatus("Everyone in the raid is already in their assigned group.", 0.35, 0.95, 0.50)
        self:RefreshRaidCompFrame()
        return
    end

    local usedRaidIndex = {}
    local moved = 0

    for i = 1, #misplaced do
        local a = misplaced[i]
        if not usedRaidIndex[a.raidIndex] then
            for j = i + 1, #misplaced do
                local b = misplaced[j]
                if not usedRaidIndex[b.raidIndex] and a.entry.group == b.currentGroup and b.entry.group == a.currentGroup then
                    if pcall(C_PartyInfo.SwapRaidSubgroup, a.raidIndex, b.raidIndex) then
                        usedRaidIndex[a.raidIndex] = true
                        usedRaidIndex[b.raidIndex] = true
                        moved = moved + 2
                    end
                    break
                end
            end
        end
    end

    -- Anyone left moves into their target group if this snapshot shows room,
    -- adjusted for members this same pass already committed to leaving it.
    local counts = currentGroupCounts()
    for _, row in ipairs(misplaced) do
        if not usedRaidIndex[row.raidIndex] then
            local occupied = counts[row.entry.group] or 0
            if occupied < MAX_GROUP_SIZE then
                if pcall(SetRaidSubgroup, row.raidIndex, row.entry.group) then
                    usedRaidIndex[row.raidIndex] = true
                    counts[row.entry.group] = occupied + 1
                    if row.currentGroup then
                        counts[row.currentGroup] = math.max((counts[row.currentGroup] or 1) - 1, 0)
                    end
                    moved = moved + 1
                end
            end
        end
    end

    local remaining = #misplaced - moved
    if remaining > 0 then
        self:SetStatus(
            string.format("Raid Comp organize: moved %d, %d left short (target group full) — click Organize Groups again in a moment.", moved, remaining),
            0.95, 0.70, 0.35
        )
    else
        self:SetStatus(string.format("Raid Comp organize: moved %d raider%s into their assigned group.", moved, moved == 1 and "" or "s"), 0.35, 0.95, 0.50)
    end

    self:RefreshRaidCompFrame()
end

--------------------------------------------------------------------------
-- UI
--------------------------------------------------------------------------

local raidCompFrame
local raidCompRowPool = {}

local function hideRaidCompRows()
    for _, row in ipairs(raidCompRowPool) do
        row:Hide()
    end
end

local function getRaidCompRow(parent, index)
    local row = raidCompRowPool[index]
    if row then
        return row
    end

    row = CreateFrame("Frame", nil, parent)
    row:SetHeight(20)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.name:SetWidth(180)
    row.name:SetJustifyH("LEFT")

    row.group = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.group:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
    row.group:SetWidth(90)
    row.group:SetJustifyH("LEFT")

    row.status = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.status:SetPoint("LEFT", row.group, "RIGHT", 8, 0)
    row.status:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.status:SetJustifyH("LEFT")

    raidCompRowPool[index] = row
    return row
end

local function ensureRaidCompFrame()
    if raidCompFrame then
        return raidCompFrame
    end

    local parent = HiddenLodge and HiddenLodge.mainWindow or UIParent
    local c = HiddenLodge and HiddenLodge.GetUIConstants and HiddenLodge:GetUIConstants() or nil
    local outerInset = (c and (c.CONTENT_PADDING + 6)) or 22
    local innerInset = (c and c.INNER_PADDING) or 12
    local verticalGap = (c and c.VERTICAL_GAP) or 12
    local buttonHeight = (c and c.BUTTON_HEIGHT) or 24
    local frameWidth = (c and c.WINDOW_WIDTH) or 820
    local frameHeight = ((c and c.WINDOW_HEIGHT) or 470) + 140

    raidCompFrame = CreateFrame("Frame", "HiddenLodgeRaidCompFrame", parent, "BackdropTemplate")
    raidCompFrame:SetSize(frameWidth, frameHeight)
    if parent and parent ~= UIParent then
        raidCompFrame:SetPoint("CENTER", parent, "CENTER", 0, 0)
        raidCompFrame:SetFrameStrata(parent:GetFrameStrata())
        raidCompFrame:SetFrameLevel(parent:GetFrameLevel() + 20)
    else
        raidCompFrame:SetPoint("CENTER")
        raidCompFrame:SetFrameStrata("DIALOG")
    end
    raidCompFrame:SetClampedToScreen(true)
    raidCompFrame:SetMovable(true)
    raidCompFrame:EnableMouse(true)
    raidCompFrame:RegisterForDrag("LeftButton")
    raidCompFrame:SetScript("OnDragStart", raidCompFrame.StartMoving)
    raidCompFrame:SetScript("OnDragStop", raidCompFrame.StopMovingOrSizing)
    raidCompFrame:SetToplevel(true)
    raidCompFrame:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8x8",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    if c then
        raidCompFrame:SetBackdropColor(unpack(c.COLOR_BG))
        raidCompFrame:SetBackdropBorderColor(unpack(c.COLOR_BORDER))
    else
        raidCompFrame:SetBackdropColor(0.02, 0.05, 0.09, 0.97)
        raidCompFrame:SetBackdropBorderColor(0.70, 0.57, 0.24, 0.95)
    end

    local headerBar = CreateFrame("Frame", nil, raidCompFrame, "BackdropTemplate")
    headerBar:SetPoint("TOPLEFT", raidCompFrame, "TOPLEFT", outerInset, -outerInset)
    headerBar:SetPoint("TOPRIGHT", raidCompFrame, "TOPRIGHT", -outerInset, -outerInset)
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

    raidCompFrame.title = headerBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    raidCompFrame.title:SetPoint("LEFT", headerBar, "LEFT", 14, 0)
    raidCompFrame.title:SetTextColor(0.95, 0.82, 0.44)
    raidCompFrame.title:SetText("Hidden Lodge Raid Comp")

    raidCompFrame.closeButton = CreateFrame("Button", nil, raidCompFrame, "UIPanelCloseButton")
    raidCompFrame.closeButton:SetPoint("TOPRIGHT", raidCompFrame, "TOPRIGHT", 2, 2)

    local content = CreateFrame("Frame", nil, raidCompFrame, "BackdropTemplate")
    content:SetPoint("TOPLEFT", raidCompFrame, "TOPLEFT", outerInset, -(outerInset + ((c and c.HEADER_HEIGHT) or 38) + verticalGap))
    content:SetPoint("BOTTOMRIGHT", raidCompFrame, "BOTTOMRIGHT", -outerInset, outerInset)
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
    raidCompFrame.contentPanel = content

    -- Paste box
    local pasteLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pasteLabel:SetPoint("TOPLEFT", content, "TOPLEFT", innerInset, -innerInset)
    pasteLabel:SetJustifyH("LEFT")
    pasteLabel:SetTextColor(0.78, 0.84, 0.93)
    pasteLabel:SetText("Paste the export string from the Raid Composition page's \"Export to Addon\" button:")

    local pasteScroll = CreateFrame("ScrollFrame", nil, content, "UIPanelScrollFrameTemplate")
    pasteScroll:SetPoint("TOPLEFT", pasteLabel, "BOTTOMLEFT", 0, -6)
    pasteScroll:SetPoint("RIGHT", content, "RIGHT", -(innerInset + 18), 0)
    pasteScroll:SetHeight(60)

    local pasteBg = CreateFrame("Frame", nil, content, "BackdropTemplate")
    pasteBg:SetPoint("TOPLEFT", pasteScroll, "TOPLEFT", -4, 4)
    pasteBg:SetPoint("BOTTOMRIGHT", pasteScroll, "BOTTOMRIGHT", 22, -4)
    pasteBg:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8x8",
        edgeFile = "Interface/Buttons/WHITE8x8",
        tile = true,
        tileSize = 8,
        edgeSize = 1,
    })
    if c then
        pasteBg:SetBackdropColor(unpack(c.COLOR_INPUT_BG))
        pasteBg:SetBackdropBorderColor(unpack(c.COLOR_INPUT_BORDER))
    else
        pasteBg:SetBackdropColor(0.01, 0.03, 0.06, 0.95)
        pasteBg:SetBackdropBorderColor(0.23, 0.31, 0.41, 0.95)
    end
    pasteBg:SetFrameLevel(math.max(pasteScroll:GetFrameLevel() - 1, 0))

    local pasteBox = CreateFrame("EditBox", nil, pasteScroll)
    pasteBox:SetMultiLine(true)
    pasteBox:SetAutoFocus(false)
    pasteBox:SetFontObject("ChatFontNormal")
    pasteBox:SetWidth(1)
    pasteBox:SetHeight(1)
    pasteBox:SetScript("OnEscapePressed", pasteBox.ClearFocus)
    pasteScroll:SetScrollChild(pasteBox)
    pasteScroll:SetScript("OnSizeChanged", function(self, width)
        pasteBox:SetWidth(width)
    end)
    raidCompFrame.pasteBox = pasteBox

    local importBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    importBtn:SetSize(100, buttonHeight)
    importBtn:SetPoint("TOPLEFT", pasteScroll, "BOTTOMLEFT", 0, -8)
    importBtn:SetText("Import")
    HiddenLodge:ApplySecondaryButtonStyle(importBtn)
    raidCompFrame.importBtn = importBtn

    local importStatusText = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    importStatusText:SetPoint("LEFT", importBtn, "RIGHT", 10, 0)
    importStatusText:SetPoint("RIGHT", content, "RIGHT", -innerInset, 0)
    importStatusText:SetJustifyH("LEFT")
    importStatusText:SetTextColor(0.78, 0.84, 0.93)
    raidCompFrame.importStatusText = importStatusText

    -- Row list
    local inviteBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    inviteBtn:SetSize(140, buttonHeight)
    inviteBtn:SetPoint("TOPLEFT", importBtn, "BOTTOMLEFT", 0, -(verticalGap + 8))
    inviteBtn:SetText("Invite Missing")
    HiddenLodge:ApplySecondaryButtonStyle(inviteBtn)
    raidCompFrame.inviteBtn = inviteBtn

    local organizeBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    organizeBtn:SetSize(140, buttonHeight)
    organizeBtn:SetPoint("LEFT", inviteBtn, "RIGHT", 8, 0)
    organizeBtn:SetText("Organize Groups")
    HiddenLodge:ApplySecondaryButtonStyle(organizeBtn)
    raidCompFrame.organizeBtn = organizeBtn

    local whisperCutsBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    whisperCutsBtn:SetSize(130, buttonHeight)
    whisperCutsBtn:SetPoint("LEFT", organizeBtn, "RIGHT", 8, 0)
    whisperCutsBtn:SetText("Whisper Cuts")
    HiddenLodge:ApplySecondaryButtonStyle(whisperCutsBtn)
    raidCompFrame.whisperCutsBtn = whisperCutsBtn

    local refreshBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    refreshBtn:SetSize(90, buttonHeight)
    refreshBtn:SetPoint("LEFT", whisperCutsBtn, "RIGHT", 8, 0)
    refreshBtn:SetText("Refresh")
    HiddenLodge:ApplySecondaryButtonStyle(refreshBtn)
    raidCompFrame.refreshBtn = refreshBtn

    local header = CreateFrame("Frame", nil, content)
    header:SetPoint("TOPLEFT", inviteBtn, "BOTTOMLEFT", 0, -verticalGap)
    header:SetPoint("TOPRIGHT", content, "TOPRIGHT", -(innerInset + 10), 0)
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
    local hGroup = makeHeader("Assigned Group", hName, 90)
    hGroup:SetPoint("LEFT", hName, "RIGHT", 8, 0)
    local hStatus = makeHeader("Status", hGroup, 200)
    hStatus:SetPoint("LEFT", hGroup, "RIGHT", 8, 0)

    raidCompFrame.summary = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    raidCompFrame.summary:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", innerInset, innerInset)
    raidCompFrame.summary:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -innerInset, innerInset)
    raidCompFrame.summary:SetJustifyH("LEFT")

    raidCompFrame.scroll = CreateFrame("ScrollFrame", nil, content, "UIPanelScrollFrameTemplate")
    raidCompFrame.scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    raidCompFrame.scroll:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -(innerInset + 18), innerInset + 18)

    raidCompFrame.content = CreateFrame("Frame", nil, raidCompFrame.scroll)
    raidCompFrame.content:SetSize(frameWidth - (outerInset * 2) - (innerInset * 2), 1)
    raidCompFrame.scroll:SetScrollChild(raidCompFrame.content)

    if type(UISpecialFrames) == "table" then
        tinsert(UISpecialFrames, "HiddenLodgeRaidCompFrame")
    end

    raidCompFrame:SetScript("OnShow", function(self)
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

    raidCompFrame:SetScript("OnHide", function()
        local parentFrame = HiddenLodge and HiddenLodge.mainWindow or nil
        if parentFrame and parentFrame.closeButton and parentFrame.closeButton.Show then
            parentFrame.closeButton:Show()
        end
    end)

    return raidCompFrame
end

function HiddenLodge:RefreshRaidCompFrame()
    local frame = ensureRaidCompFrame()
    local store = self.db and self.db.raidComp

    if not store or type(store.entries) ~= "table" or #store.entries == 0 then
        frame.importStatusText:SetText("No comp imported yet.")
    else
        local importedAt = tonumber(store.importedAt) or 0
        local ageText = importedAt > 0 and (" (" .. (time() - importedAt) .. "s ago)") or ""
        frame.importStatusText:SetText(string.format("Imported %d raider(s) across %d group(s)%s.", #store.entries, tonumber(store.groupCount) or 0, ageText))
    end

    hideRaidCompRows()
    local rows, err = self:CollectRaidCompRows()
    frame.rows = rows

    if err then
        frame.summary:SetText(err)
        frame.content:SetHeight(1)
        frame.inviteBtn:SetEnabled(false)
        frame.organizeBtn:SetEnabled(false)
        return
    end

    local rowHeight = 20
    local y = -2
    local missing, wrongGroup, correct = 0, 0, 0
    for i, rowData in ipairs(rows) do
        local row = getRaidCompRow(frame.content, i)
        row:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, y)
        row:SetPoint("RIGHT", frame.content, "RIGHT", 0, 0)

        if not rowData.inRaid then
            row.bg:SetColorTexture(0.35, 0.12, 0.12, 0.32)
            missing = missing + 1
        elseif not rowData.correct then
            row.bg:SetColorTexture(0.35, 0.30, 0.10, 0.32)
            wrongGroup = wrongGroup + 1
        else
            row.bg:SetColorTexture(0.18, 0.33, 0.12, 0.32)
            correct = correct + 1
        end

        local r, g, b = classColor(rowData.entry.classToken)
        row.name:SetText(rowData.entry.name)
        row.name:SetTextColor(r, g, b)
        row.group:SetText("Group " .. tostring(rowData.entry.group))

        if not rowData.inRaid then
            row.status:SetText("Not in raid")
            row.status:SetTextColor(0.95, 0.45, 0.35)
        elseif not rowData.correct then
            row.status:SetText("In Group " .. tostring(rowData.currentGroup) .. " — needs move")
            row.status:SetTextColor(0.95, 0.80, 0.35)
        else
            row.status:SetText("In assigned group")
            row.status:SetTextColor(0.45, 0.95, 0.45)
        end

        row:Show()
        y = y - rowHeight
    end

    frame.content:SetHeight(math.max(#rows * rowHeight + 6, 1))
    frame.summary:SetText(string.format("%d in assigned group · %d need moving · %d not yet in raid", correct, wrongGroup, missing))
    frame.inviteBtn:SetEnabled(missing > 0)
    frame.organizeBtn:SetEnabled(wrongGroup > 0)
end

function HiddenLodge:ShowRaidCompFrame()
    local frame = ensureRaidCompFrame()
    self:RefreshRaidCompFrame()

    frame.importBtn:SetScript("OnClick", function()
        local text = frame.pasteBox:GetText()
        local ok, countOrErr, groupCount = self:ImportRaidCompString(text)
        if ok then
            self:SetStatus(string.format("Imported %d raider(s) across %d group(s).", countOrErr, groupCount), 0.35, 0.95, 0.50)
            frame.pasteBox:SetText("")
            frame.pasteBox:ClearFocus()
        else
            self:SetStatus(countOrErr, 0.95, 0.45, 0.35)
        end
        self:RefreshRaidCompFrame()
    end)

    frame.refreshBtn:SetScript("OnClick", function()
        self:RefreshRaidCompFrame()
    end)
    frame.inviteBtn:SetScript("OnClick", function()
        self:InviteMissingRaidCompMembers()
    end)
    frame.organizeBtn:SetScript("OnClick", function()
        self:OrganizeRaidCompGroups()
    end)
    frame.whisperCutsBtn:SetScript("OnClick", function()
        self:WhisperDownsizedRaidCompMembers()
    end)

    frame:Show()
end
