---
name: pardex-godot-ui
description: Edit PARDEX Godot scenes, page layouts, themes, artwork bindings, logo shaders or editor previews.
---

- Open only the affected scene/script/resource; use the file map only if its location is unknown.
- Preserve Container-based resizing, 1366×768 readability and dark cyan/chrome styling. Do not shrink all text to fix layout.
- Edit fixed layouts in scenes and styling in resources. Keep dynamic data/actions in scripts; do not restore runtime page builders or overwrite manual scene edits.
- Use `scenes/ui/` templates for repeated rows/cards. Keep node paths, unique names and signals consistent.
- Inspect image dimensions and filtering before pixels; use linear filtering for smooth artwork. Do not edit generated imports or add fake account/store data.
- For checks, consult only `pardex-verify`. Report visual inspection only if it actually happened.
