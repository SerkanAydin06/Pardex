# PARDEX file map — read only when needed

| Task | Files |
|---|---|
| Shell/navigation/window | `scenes/main.tscn`, `scripts/main.gd`, `scripts/ui/pardex_window_frame.gd` |
| Page layouts | `scenes/pages/{store,library,friends,messages,profile,settings}_page.tscn` |
| Page data/actions | `scripts/pages/{store,library,social,messages,profile}_page.gd` |
| Repeated cards/rows | `scenes/ui/` |
| Theme/shared UI | `themes/pardex_theme.tres`, `scripts/ui/pardex_ui.gd` |
| Editor preview | `scripts/tools/pardex_editor_preview.gd`; user instructions: `docs/EDITOR_UI.md` |
| Logo effects | `assets/shaders/pardex_logo.gdshader`, `themes/pardex_logo_material.tres`, `scripts/ui/pardex_logo_effect.gd` |
| Catalog/local activity | `scripts/data/pardex_catalog.gd` |
| Client protocol/chat/avatar | `scripts/online/pardex_online.gd` |
| Secure handoff/launch | `scripts/online/pardex_online_secure_handoff.gd`, `scripts/online/pardex_game_launcher.gd` |
| Identity/recovery/notifications | `scripts/online/pardex_identity_guard.gd`, `scripts/screens/account_recovery.gd`, `scripts/online/pardex_notifications.gd` |
| Server protocol/persistence | `server/server_core.js`, `server/social_store.js` |
| Server entry/control | `server/server.js`, `server/production_server.js` |
| PC server/tunnels | `host/pardex_host.js`, `host/README.md` |
| Packaging | `tools/package_windows.ps1`, `WINDOWS_PACKAGE.md`, `export_presets.cfg` |
| Checks | `scripts/ci/`, `server/*-smoke-test.js`, `.github/workflows/` |

These are location hints, not files to read together. For a path group, open only the matching member. Find exact node/signal names before expanding context.
