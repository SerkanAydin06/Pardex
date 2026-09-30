# PARDEX Project Map

Read this file instead of scanning the repository when you only need to know where a concern lives.

## Launcher / Godot

| Concern | Primary files |
|---|---|
| App shell, navigation, page switching, window state | `scenes/main.tscn`, `scripts/main.gd` |
| Shared colors, panels, buttons, image helpers | `scripts/ui/pardex_ui.gd` |
| Window frame / borderless resize | `scripts/ui/pardex_window_frame.gd`, `scenes/ui/window_chrome.tscn` |
| UI asset binding | `scripts/ui/pardex_asset_binding.gd` |
| Text fitting | `scripts/ui/pardex_text_fit.gd` |
| Home/current landing page | `scripts/pages/home_page.gd` |
| Discover/store-like page | `scripts/pages/discover_page.gd` |
| Friends/social/chat UI | `scripts/pages/social_page.gd` |
| Profile UI | `scripts/pages/profile_page.gd` |
| Rooms | `scenes/screens/rooms.tscn` + `scripts/main.gd` wiring |
| Settings | `scenes/screens/settings.tscn` + `scripts/main.gd` wiring |
| Game list / cover & banner paths / local activity | `scripts/data/pardex_catalog.gd` |
| Brand and launcher artwork | `assets/ui/` |
| App icon | `assets/icon.png` |
| Project/autoload/window config | `project.godot` |

## Online client

| Concern | Primary files |
|---|---|
| WebSocket/session/social/room client | `scripts/online/pardex_online.gd` |
| Secure handoff wrapper | `scripts/online/pardex_online_secure_handoff.gd` |
| Identity validation | `scripts/online/pardex_identity_guard.gd` |
| Game launch/handoff | `scripts/online/pardex_game_launcher.gd` |
| Notification center | `scripts/online/pardex_notifications.gd` |
| Voice placeholder/relay client | `scripts/online/pardex_voice.gd` |

## Server

| Concern | Primary files |
|---|---|
| Entry / server composition | `server/server.js`, `server/production_server.js` |
| Core WebSocket logic | `server/server_core.js` |
| Persistent social/account store | `server/social_store.js` |
| Railway/Docker deployment | `server/Dockerfile`, `server/DEPLOYMENT.md` |
| Tests | `server/*-smoke-test.js`, `server/package.json` |

## Godot CI

- Resource validation: `scripts/ci/validate_project.gd`
- Headless boot: `scripts/ci/boot_smoke.gd`
- Workflows: `.github/workflows/`

## Search strategy

When locating code, search exact node/signal/function names before opening whole files. Typical order:

1. `Grep` exact symbol.
2. Read the matching function plus nearby context.
3. Read a second file only if the call crosses boundaries.
4. Avoid reading binary assets; use filenames/import metadata unless visual inspection is explicitly needed.
