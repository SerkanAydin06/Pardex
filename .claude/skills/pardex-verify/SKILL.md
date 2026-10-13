---
name: pardex-verify
description: Select focused checks for PARDEX edits; distinguish actual results from unavailable checks.
---

Run only checks justified by the change. Use the existing Godot version and test scripts; do not install a local engine if CI can perform the same required check.

| Change | Checks |
|---|---|
| AI instructions/docs/settings | Parse JSON/YAML; check imports, referenced paths and diffs. No Godot/server suite. |
| Text/artwork paths | Check paths; load affected resources. |
| Godot scripts/scenes | Resource import + `scripts/ci/validate_project.gd`; `boot_smoke.gd` for runtime/signal changes. |
| Navigation/layout | Above + `editor_preview_smoke.gd`; inspect narrow/normal layouts when changed. |
| Logo shader | Above + OpenGL `logo_render_smoke.gd` using Xvfb; headless loading does not prove rendering. |
| Client, protocol unchanged | Relevant Godot checks; no full server suite/deploy. |
| Server/protocol | Focused smoke test during edits; `cd server && npm test` before publishing. |
| Packaging | Existing package instructions and export presets; no unrelated backend tests. |

Read only the matching workflow when using GitHub Actions. Follow that exact check's run, not an unrelated green run. Distinguish passed, pending and unavailable. Never repeat passed checks without new changes or uncertainty. Keep the final reply short.
