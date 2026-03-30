# HiddenLodge

Starter World of Warcraft addon scaffold for the Hidden Lodge guild.

## Files
- `HiddenLodge.toc`: Addon metadata and load order.
- `HiddenLodge.lua`: Ace3 bootstrap, saved variables setup, slash command routing, and integration registry.
- `HiddenLodge_Style.lua`: Shared UI constants and style helpers.
- `HiddenLodge_Preparedness.lua`: Preparedness data import/parsing and lookup logic.
- `HiddenLodge_GreatVault.lua`: Great Vault score lookup and display color helpers.
- `HiddenLodge_Integration_RCLootCouncil.lua`: RCLootCouncil integration module that injects the voting-frame column.
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
When RCLootCouncil is installed and loaded, HiddenLodge injects `Prep` and `GV` columns into the voting frame.

- `Prep` displays preparedness tier from desktop-synced data.
- `GV` displays Great Vault score (0-100) from desktop-synced data.
- Sorting is enabled on both columns.
- Keys are matched by character + realm (with name-only fallback).

## In-game usage
- `/hl` or `/hl show`: Toggle/show the main window.
- `/hl hide`: Hide the main window.
- Open the panel to view current desktop sync status.

## CurseForge release automation
This repo includes tag-based release automation in `.github/workflows/release.yml` using `BigWigsMods/packager`.

Required one-time setup:
1. Create a CurseForge API token and add it to GitHub repository secrets as `CURSEFORGE_API_TOKEN`.
2. Set your CurseForge project id in `.pkgmeta` by uncommenting and editing:
	- `curseforge:`
	- `project-id: <your_project_id>`
3. Push a tag like `v1.0.0`.

On tag push, GitHub Actions will package the addon and publish the release.
