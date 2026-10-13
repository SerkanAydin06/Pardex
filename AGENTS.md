# PARDEX — ChatGPT / Claude Code

Godot 4.7.x desktop launcher; Node.js/WebSocket backend. Support only ChatGPT and Claude Code. The user's current request takes priority over repository preferences.

## Work efficiently
- Locate the exact symbol with `rg`; read only the relevant function and its direct dependencies. Use `docs/ai/PROJECT_MAP.md` only when the file is unknown.
- Do not rescan the repository or reread unchanged files. Exclude `.git/`, `.godot/`, dependencies, generated imports, build outputs and live data from routine searches. Inspect image files only for visual tasks.
- Make one coherent change, inspect the focused diff, then run the relevant checks once. Repeat only after changes or failures. Do not skip needed verification to save tokens.
- Do not create plans, reports, documentation, refactors or new dependencies unless needed for the request. Keep logs to failures and a short result.
- Do not start subagents, delegate to other AI tools, or switch models automatically. Use low effort for trivial edits, normal effort for code, higher effort only when a focused attempt is blocked.
- Read only the applicable `.claude/skills/pardex-{godot-ui,online,verify}/SKILL.md`; never preload every skill. Read `docs/ai/CURRENT_FOCUS.md` only for product/navigation decisions.

## Preserve the project
- Keep UI layouts in `scenes/pages/` and `scenes/ui/`; code supplies live data/actions. Preserve editor previews, resizing and 1366×768 usability.
- Never fabricate account, store or online capabilities. Current code is authoritative over stale notes.
- Do not expose or commit identity keys, recovery codes, tokens, `.env` or live account data. Do not edit import caches.
- Preserve unrelated changes. Check the remote head before publishing; use fast-forward/expected-head writes. Never force-push or deploy as a side effect. Reuse existing publication authorization.

## Speak briefly
Use Turkish, plain language and no unnecessary technical detail. For routine work, finish in 2–4 short sentences or at most 3 bullets: what changed, what actually passed, and a real blocker if any. Link the commit when published. Do not narrate tool calls, repeat the plan, dump logs or offer unnecessary next steps. Give more detail only when asked or needed to explain a decision. Never claim tests passed or work was published without evidence.
