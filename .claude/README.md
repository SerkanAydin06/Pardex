# PARDEX Claude Code Profile

This repository ships a lean Claude Code setup. Pulling the repo is enough for project instructions, skills, agents and project settings to become available in Claude Code.

## Defaults

- Main model: `sonnet`
- Default effort: `medium`
- Subagents: `haiku`
- Response output cap: 6000 tokens
- Large/generated/private folders denied from routine reads
- No external MCP/plugin bundle enabled by default

The last point is intentional: every always-on plugin/MCP can add tool descriptions and context. Enable an external plugin only for a task that actually needs it.

## Cheap daily workflow

Start Claude Code from the PARDEX repository root:

```bash
claude
```

For a small edit, say exactly what should change and where if known. Example:

```text
Kütüphane kart başlıklarını 2 px büyüt. Sadece ilgili UI dosyasını değiştir ve Godot validation çalıştır.
```

Useful controls:

- `/context` — inspect what is consuming context.
- `/effort low` — trivial text/path/style fixes.
- `/effort medium` — normal PARDEX implementation (default).
- `/effort high` — cross-system bugs only.
- `/model sonnet` — normal development.
- Use Opus only for genuinely blocked architecture/security problems.
- `/compact` after a long coherent task if continuing the same subject.
- `/clear` when switching to an unrelated feature; this is often cheaper than carrying old context.

## Project skills

Claude activates these when relevant, and they can also be requested by name:

- `context-budget`
- `pardex-godot-ui`
- `pardex-online`
- `pardex-verify`
- `pardex-git`

## Cheap subagents

- `repo-locator`: Haiku, read-only. Finds the minimum relevant files.
- `cheap-reviewer`: Haiku, read-only. Reviews only the changed surface.

Do not launch both for every trivial task. Subagents are useful when they replace expensive exploration by the main model, not when used ceremonially.

## External plugins

None are required for normal PARDEX development. Add them temporarily when a real need appears (for example, documentation retrieval for a new external SDK). Avoid installing large general-purpose packs just because they contain many commands: unused tools still make the environment harder to reason about and can increase context overhead.

## Keep this setup cheap

Keep `CLAUDE.md` short. Put new domain knowledge in a targeted skill/reference file instead of growing the always-loaded root instructions.
