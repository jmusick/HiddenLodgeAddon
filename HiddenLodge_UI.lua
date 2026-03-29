---@diagnostic disable: inject-field, undefined-field, undefined-global, deprecated
local addonName = ...
---@type HiddenLodgeAddon
local HiddenLodge = LibStub("AceAddon-3.0"):GetAddon(addonName)

local function saveWindowPoint(self, frame)
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    self.db.ui.windowPoint = {
        point = point,
        relativePoint = relativePoint,
        x = x,
        y = y,
    }
end

local function applySavedWindowPoint(self, frame)
    local pos = self.db.ui.windowPoint
    if not pos then
        frame:SetPoint("CENTER")
        return
    end

    frame:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
end

function HiddenLodge:SetStatus(message, r, g, b)
    if not self.mainWindow or not self.mainWindow.statusText then
        return
    end

    self.mainWindow.statusText:SetText(message or "")
    self.mainWindow.statusText:SetTextColor(r or 1, g or 0.82, b or 0)
end

function HiddenLodge:RefreshPreparednessStatusUI()
    if not self.mainWindow or not self.mainWindow.syncInfoText then
        return ""
    end

    local syncText, r, g, b = self:GetPreparednessSyncStatusText()
    self.mainWindow.syncInfoText:SetText(syncText)
    self.mainWindow.syncInfoText:SetTextColor(r, g, b)
end

function HiddenLodge:CreateMainWindow()
    if self.mainWindow then
        return
    end

    local c = self:GetUIConstants()
    local outerInset = c.CONTENT_PADDING + 6
    local innerInset = c.INNER_PADDING

    local frame = CreateFrame("Frame", "HiddenLodgeMainFrame", UIParent, "BackdropTemplate")
    frame:SetSize(c.WINDOW_WIDTH, c.WINDOW_HEIGHT)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetFrameStrata("DIALOG")

    frame:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8x8",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(unpack(c.COLOR_BG))
    frame:SetBackdropBorderColor(unpack(c.COLOR_BORDER))

    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(movableFrame)
        movableFrame:StopMovingOrSizing()
        saveWindowPoint(self, movableFrame)
    end)

    applySavedWindowPoint(self, frame)

    local header = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", outerInset, -outerInset)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -outerInset, -outerInset)
    header:SetHeight(c.HEADER_HEIGHT)
    header:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8x8",
        edgeFile = "Interface/Buttons/WHITE8x8",
        tile = true,
        tileSize = 8,
        edgeSize = 1,
    })
    header:SetBackdropColor(unpack(c.COLOR_HEADER_BG))
    header:SetBackdropBorderColor(unpack(c.COLOR_PANEL_BORDER))
    frame.header = header

    frame.title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("LEFT", header, "LEFT", 14, 0)
    frame.title:SetTextColor(0.95, 0.82, 0.44)
    frame.title:SetText("The Hidden Lodge")

    frame.closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 2, 2)

    local content = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    content:SetPoint("TOPLEFT", frame, "TOPLEFT", outerInset, -(outerInset + c.HEADER_HEIGHT + c.VERTICAL_GAP))
    content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -outerInset, outerInset)
    content:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8x8",
        edgeFile = "Interface/Buttons/WHITE8x8",
        tile = true,
        tileSize = 8,
        edgeSize = 1,
    })
    content:SetBackdropColor(unpack(c.COLOR_PANEL_BG))
    content:SetBackdropBorderColor(unpack(c.COLOR_PANEL_BORDER))
    frame.content = content

    frame.subtitle = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.subtitle:SetPoint("TOPLEFT", content, "TOPLEFT", innerInset, -innerInset)
    frame.subtitle:SetPoint("RIGHT", content, "RIGHT", -innerInset, 0)
    frame.subtitle:SetJustifyH("LEFT")
    frame.subtitle:SetTextColor(0.78, 0.84, 0.93)
    frame.subtitle:SetText("Guild data is now pushed from the HiddenLodge Desktop app.")

    local syncPanel = CreateFrame("Frame", nil, content, "BackdropTemplate")
    syncPanel:SetPoint("TOPLEFT", frame.subtitle, "BOTTOMLEFT", 0, -c.VERTICAL_GAP)
    syncPanel:SetPoint("TOPRIGHT", content, "TOPRIGHT", -innerInset, -(innerInset + 18 + c.VERTICAL_GAP))
    syncPanel:SetPoint("BOTTOM", content, "BOTTOM", 0, innerInset + c.BUTTON_HEIGHT + c.VERTICAL_GAP + 6)
    syncPanel:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8x8",
        edgeFile = "Interface/Buttons/WHITE8x8",
        tile = true,
        tileSize = 8,
        edgeSize = 1,
    })
    syncPanel:SetBackdropColor(unpack(c.COLOR_INPUT_BG))
    syncPanel:SetBackdropBorderColor(unpack(c.COLOR_INPUT_BORDER))

    local syncInfoText = syncPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    syncInfoText:SetPoint("TOPLEFT", syncPanel, "TOPLEFT", 10, -10)
    syncInfoText:SetPoint("TOPRIGHT", syncPanel, "TOPRIGHT", -10, -10)
    syncInfoText:SetJustifyH("LEFT")
    syncInfoText:SetJustifyV("TOP")
    syncInfoText:SetSpacing(4)
    syncInfoText:SetText("Loading sync status...")

    local syncHint = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    syncHint:SetPoint("TOPLEFT", syncPanel, "BOTTOMLEFT", 2, -8)
    syncHint:SetPoint("RIGHT", content, "RIGHT", -innerInset, 0)
    syncHint:SetJustifyH("LEFT")
    syncHint:SetTextColor(0.64, 0.71, 0.82)
        syncHint:SetText("Use the desktop app to sync latest data, then run /reload in WoW to update this panel.")

    frame.statusText = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.statusText:SetPoint("LEFT", content, "LEFT", innerInset, innerInset + 1)
        frame.statusText:SetPoint("RIGHT", content, "RIGHT", -innerInset, innerInset + 1)
    frame.statusText:SetJustifyH("LEFT")
    frame.statusText:SetTextColor(0.93, 0.79, 0.40)
    frame.statusText:SetText("Data sync status available.")


    frame.syncInfoText = syncInfoText
    frame.syncPanel = syncPanel
    self:RefreshPreparednessStatusUI()

    frame:Hide()
    self.mainWindow = frame

    if type(UISpecialFrames) == "table" then
        tinsert(UISpecialFrames, "HiddenLodgeMainFrame")
    end
end

function HiddenLodge:ShowMainWindow()
    self:CreateMainWindow()
    self.mainWindow:Show()
    self:RefreshPreparednessStatusUI()
end

function HiddenLodge:HideMainWindow()
    if self.mainWindow then
        self.mainWindow:Hide()
    end
end

function HiddenLodge:ToggleMainWindow()
    self:CreateMainWindow()

    if self.mainWindow:IsShown() then
        self.mainWindow:Hide()
    else
        self.mainWindow:Show()
        self:RefreshPreparednessStatusUI()
    end
end
