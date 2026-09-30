---
name: pardex-verify
description: Use after PARDEX code changes to choose the smallest sufficient validation, or before a PR/release when deciding which checks are necessary.
version: 1.0.0
effort: low
---

# PARDEX Verification

Do not run every test for every edit.

## Choose by change type

### Text / artwork path / simple styling only
- Confirm referenced resources exist.
- Parse/load changed Godot script/scene if possible.
- No server tests.

### Godot UI / navigation / scene structure
- Run project resource validation.
- Run headless boot smoke if the shell/navigation changed.
- Check one narrow and one normal desktop size for layout-sensitive changes.

### Online client only, protocol unchanged
- Validate changed GDScript + boot.
- No server deploy/test unless packets or server expectations changed.

### Server/protocol/social/room changes
```bash
cd server && npm test
```
Then run any focused smoke test relevant to the changed feature if full output is ambiguous.

### Packaging / release
Read `WINDOWS_PACKAGE.md`, `export_presets.cfg`, and only the relevant workflow/deployment docs.

## Output

Report only:
- `verified:` checks that actually ran and passed
- `not run:` checks unavailable or intentionally skipped
- `remaining:` only real unresolved items

Never claim visual/manual verification unless it actually happened.
