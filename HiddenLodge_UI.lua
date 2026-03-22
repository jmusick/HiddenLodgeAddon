---@diagnostic disable: inject-field, undefined-field
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

function HiddenLodge:GetImportText()
    if not self.mainWindow or not self.mainWindow.importEditBox then
        return ""
    end

    return self.mainWindow.importEditBox:GetText() or ""
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
    frame.subtitle:SetText("Paste JSON export from the guild website below.")

    local importPanel = CreateFrame("Frame", nil, content, "BackdropTemplate")
    importPanel:SetPoint("TOPLEFT", frame.subtitle, "BOTTOMLEFT", 0, -c.VERTICAL_GAP)
    importPanel:SetPoint("TOPRIGHT", content, "TOPRIGHT", -innerInset, -(innerInset + 18 + c.VERTICAL_GAP))
    importPanel:SetPoint("BOTTOM", content, "BOTTOM", 0, innerInset + c.BUTTON_HEIGHT + c.VERTICAL_GAP + 6)
    importPanel:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8x8",
        edgeFile = "Interface/Buttons/WHITE8x8",
        tile = true,
        tileSize = 8,
        edgeSize = 1,
    })
    importPanel:SetBackdropColor(unpack(c.COLOR_INPUT_BG))
    importPanel:SetBackdropBorderColor(unpack(c.COLOR_INPUT_BORDER))

    local importHint = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    importHint:SetPoint("TOPLEFT", importPanel, "BOTTOMLEFT", 2, -8)
    importHint:SetPoint("RIGHT", content, "RIGHT", -innerInset, 0)
    importHint:SetJustifyH("LEFT")
    importHint:SetTextColor(0.64, 0.71, 0.82)
    importHint:SetText("Use Ctrl+V in this field. Parsing/validation will be added next.")

    local scrollFrame = CreateFrame("ScrollFrame", "HiddenLodgeImportScrollFrame", importPanel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", importPanel, "TOPLEFT", 6, -6)
    scrollFrame:SetPoint("BOTTOMRIGHT", importPanel, "BOTTOMRIGHT", -30, 6)

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetAutoFocus(false)
    editBox:SetMultiLine(true)
    editBox:SetFontObject("ChatFontNormal")
    editBox:SetTextInsets(4, 4, 4, 4)
    editBox:SetWidth(c.WINDOW_WIDTH - (outerInset * 2 + innerInset * 2 + 30))
    editBox:SetScript("OnCursorChanged", function(box, _, y)
        scrollFrame:SetVerticalScroll(y)
    end)
    editBox:SetScript("OnTextChanged", function(box)
        local text = box:GetText() or ""
        self:SetStatus("Import payload length: " .. #text .. " characters", 0.78, 0.84, 0.93)
    end)

    scrollFrame:SetScrollChild(editBox)

    frame.statusText = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.statusText:SetPoint("LEFT", content, "LEFT", innerInset, innerInset + 1)
    frame.statusText:SetPoint("RIGHT", content, "RIGHT", -innerInset - (c.BUTTON_WIDTH * 2) - 18, innerInset + 1)
    frame.statusText:SetJustifyH("LEFT")
    frame.statusText:SetTextColor(0.93, 0.79, 0.40)
    frame.statusText:SetText("Ready for website JSON import.")

    local importButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    importButton:SetSize(c.BUTTON_WIDTH, c.BUTTON_HEIGHT)
    importButton:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -(innerInset + c.BUTTON_WIDTH + 8), innerInset)
    importButton:SetText("Import")
    self:ApplyPrimaryButtonStyle(importButton)
    importButton:SetScript("OnClick", function()
        local ok, result = self:ImportPreparednessJSON(self:GetImportText())
        if not ok then
            self:SetStatus(result, 0.95, 0.40, 0.35)
            return
        end

        local hooked, reason = self:EnsureRCLootCouncilColumn()
        if hooked then
            self:SetStatus("Imported " .. result .. " character entries. RCLootCouncil column updated.", 0.35, 0.95, 0.5)
        else
            self:SetStatus("Imported " .. result .. " entries. " .. reason, 0.95, 0.80, 0.40)
        end
    end)

    local clearButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    clearButton:SetSize(c.BUTTON_WIDTH, c.BUTTON_HEIGHT)
    clearButton:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -innerInset, innerInset)
    clearButton:SetText("Clear")
    self:ApplySecondaryButtonStyle(clearButton)
    clearButton:SetScript("OnClick", function()
        editBox:SetText("")
        self:SetStatus("Import text cleared.", 0.93, 0.79, 0.40)
        editBox:SetFocus()
    end)

    frame.importScroll = scrollFrame
    frame.importEditBox = editBox

    frame:Hide()
    self.mainWindow = frame

    if type(UISpecialFrames) == "table" then
        tinsert(UISpecialFrames, "HiddenLodgeMainFrame")
    end
end

function HiddenLodge:ShowMainWindow()
    self:CreateMainWindow()
    self.mainWindow:Show()
    self.mainWindow.importEditBox:SetFocus()
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
        self.mainWindow.importEditBox:SetFocus()
    end
end
