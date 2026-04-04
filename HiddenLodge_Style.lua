---@diagnostic disable: inject-field, undefined-field
local addonName = ...
---@type HiddenLodgeAddon
local HiddenLodge = LibStub("AceAddon-3.0"):GetAddon(addonName) --[[@as HiddenLodgeAddon]]

HiddenLodge.Constants = {
    WINDOW_WIDTH = 700,
    WINDOW_HEIGHT = 470,
    HEADER_HEIGHT = 38,
    CONTENT_PADDING = 16,
    INNER_PADDING = 12,
    VERTICAL_GAP = 12,
    BUTTON_HEIGHT = 24,
    BUTTON_WIDTH = 130,

    COLOR_BG = { 0.02, 0.05, 0.09, 0.97 },
    COLOR_BORDER = { 0.70, 0.57, 0.24, 0.95 },
    COLOR_HEADER_BG = { 0.06, 0.10, 0.16, 0.98 },
    COLOR_PANEL_BG = { 0.03, 0.07, 0.12, 0.95 },
    COLOR_PANEL_BORDER = { 0.30, 0.24, 0.11, 0.95 },
    COLOR_INPUT_BG = { 0.01, 0.03, 0.06, 0.95 },
    COLOR_INPUT_BORDER = { 0.23, 0.31, 0.41, 0.95 },
}

function HiddenLodge:GetUIConstants()
    return self.Constants
end

function HiddenLodge:ApplyPrimaryButtonStyle(button)
    button:SetNormalFontObject("GameFontNormal")
    button:SetHighlightFontObject("GameFontHighlight")
end

function HiddenLodge:ApplySecondaryButtonStyle(button)
    button:SetNormalFontObject("GameFontHighlightSmall")
    button:SetHighlightFontObject("GameFontNormalSmall")
end
