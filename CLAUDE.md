# PARDEX — Claude Code Instructions

PARDEX is a Godot 4.7 desktop game hub/launcher with a Node.js WebSocket backend.

## Cost / context policy

Work narrowly. Do not scan the whole repository before every task.

1. Read only the files directly relevant to the request.
2. Start with `docs/claude/PROJECT_MAP.md` only when file ownership/location is unclear.
3. Do not recursively read `assets/`, `.godot/`, `node_modules/`, generated `.import` files, build folders, or `server/data/`.
4. Prefer `Grep/Glob` to locate a symbol, then read the smallest useful file/range.
5. Do not re-read an unchanged file in the same task.
6. Do not create plans, audits, summaries, or refactors unless they help complete the requested task.
7. Make the smallest coherent change. Do not improve unrelated code.
8. Batch related edits and verification commands.
9. Keep user-facing replies concise: changed / verified / remaining.
10. Use Sonnet for normal implementation. Use Opus only when the user explicitly asks or the problem remains blocked after a focused attempt.

## Project rules

- Engine: Godot 4.7.x, GDScript.
- Main launcher scene: `scenes/main.tscn`.
- Main orchestration: `scripts/main.gd`.
- Shared UI factory/styles: `scripts/ui/pardex_ui.gd`.
- Dynamic pages: `scripts/pages/`.
- Online client: `scripts/online/`.
- Backend: `server/`.
- Game catalog: `scripts/data/pardex_catalog.gd`.
- UI art: `assets/ui/`.
- Do not edit `.godot/` or generated import cache.
- Never commit secrets, `.env`, recovery codes, identity keys, or production social data.
- Preserve the responsive resizable desktop shell unless the task explicitly changes it.
- UI should remain dark, premium, modern, cyan/blue PARDEX style and readable at 1366×768.
- Prefer real scene nodes/resources where the user needs editor control; avoid unnecessary runtime-only UI generation.

## Verification

For Godot/UI changes, run the smallest relevant validation first. If a local Godot binary is available, prefer the existing project validation/headless checks rather than opening every scene manually.

For server changes:

```bash
cd server && npm test
```

Do not run full server tests for client-only artwork/text changes unless shared online behavior changed.

## Skills

Use project skills only when relevant:
- `context-budget` — cheap repository/context workflow.
- `pardex-godot-ui` — scenes, responsive UI, textures, imports.
- `pardex-online` — WebSocket/social/room/server work.
- `pardex-verify` — targeted validation and release checks.

Current product direction lives in `docs/claude/CURRENT_FOCUS.md`; read it for navigation or major UI work, not for unrelated bug fixes.
