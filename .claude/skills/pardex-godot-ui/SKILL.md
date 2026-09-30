---
name: pardex-godot-ui
description: Use for PARDEX Godot scenes, navigation, responsive desktop layout, textures, imports, typography, buttons, panels, or launcher visuals.
version: 1.0.0
effort: medium
---

# PARDEX Godot UI

Read only the UI files relevant to the requested screen. Use `docs/claude/PROJECT_MAP.md` if ownership is unclear and `docs/claude/CURRENT_FOCUS.md` for major navigation/page redesigns.

## Rules

- Godot 4.7.x / GDScript syntax only.
- Preserve responsive resizing. Minimum target: usable at 1366×768.
- Prefer Containers and size flags over fixed positions.
- Do not solve responsive layout by globally shrinking text.
- Keep readable typography and consistent PARDEX dark/cyan visual language.
- Use `scripts/ui/pardex_ui.gd` for shared styles/components before adding another styling system.
- When the user needs editor control, prefer scene-authored nodes/resources instead of runtime-created visual nodes.
- Runtime-created rows/data are fine for dynamic lists.
- Do not introduce fake account/store/social state to match a visual mockup.

## Images

- AI/cinematic artwork is not pixel art: use linear filtering; mipmaps are appropriate when large textures are displayed much smaller.
- `Nearest` is for pixel-art/intentional hard pixels only.
- Avoid reading binary PNG contents during ordinary code tasks; inspect filenames/dimensions/import settings first.
- Keep `assets/ui` naming semantic and stable.
- Never edit `.godot/imported/` directly.

## Typical verification

- Parse/load changed scene/scripts.
- Run existing `scripts/ci/validate_project.gd` / boot smoke when local Godot is available.
- For layout changes, check narrow + normal desktop widths rather than only 1920×1080.
