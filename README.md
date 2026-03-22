# HiddenLodge

Starter World of Warcraft addon scaffold for the Hidden Lodge guild.

## Files
- `HiddenLodge.toc`: Addon metadata and load order.
- `HiddenLodge.lua`: Ace3 bootstrap, saved variables setup, and slash command routing.
- `HiddenLodge_Style.lua`: Shared UI constants and style helpers.
- `HiddenLodge_UI.lua`: Main window construction and JSON import text area.

## Ace3 dependency
This addon currently expects Ace3 to be installed as a separate addon.

- Easiest path: install Ace3 from CurseForge/Wago like any normal addon.
- The `.toc` includes `OptionalDeps: Ace3, RCLootCouncil`, so load order works when those addons are present.

If Ace3 is missing, HiddenLodge prints a friendly chat warning instead of hard failing.

## Build and workflow
WoW addons are not usually "built" like web apps. The normal workflow is edit -> reload UI in game.

1. Keep this folder as your addon root (`HiddenLodge`).
2. Put or symlink this folder into your WoW AddOns directory:
	- `_retail_/Interface/AddOns/HiddenLodge`
3. Launch game, enable `HiddenLodge` and `Ace3` on character select.
4. In game, use `/reload` after code changes.
5. Use `/hl` to verify addon startup.

## Current panel behavior
The default panel is a dedicated JSON import view:
- Large multiline text field for website export payloads.
- Import button that parses the JSON and stores Preparedness Tier data.
- Status line that shows current text length and import results.
- Clear button to reset the field quickly.

Gem/enchant checks and roster inspection are currently removed from this addon UI.

## RCLootCouncil integration
When RCLootCouncil is installed and loaded, HiddenLodge injects a `Prep` column into the voting frame.

- The column displays `preparednessTier` from your imported JSON.
- Sorting is enabled on this column.
- Keys are matched by character + realm (with name-only fallback).

## In-game usage
- `/hl` or `/hl show`: Toggle/show the main window.
- `/hl hide`: Hide the main window.
- Paste website JSON into the field and click `Import`.
