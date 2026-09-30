---
name: context-budget
description: Use when a PARDEX task could trigger broad repository exploration, when locating files, or when context/token usage is becoming large. Keeps reads and tool calls narrow.
version: 1.0.0
effort: low
---

# Context Budget

Goal: finish the task with the smallest sufficient context.

## Workflow

1. Restate the concrete change in one sentence internally.
2. If file location is known from `CLAUDE.md`, open that file directly.
3. If unknown, read `docs/claude/PROJECT_MAP.md` or use the `repo-locator` subagent.
4. Search exact symbols with Grep/Glob before opening files.
5. Read only the function/section needed; expand only when dependencies require it.
6. Never recursively inspect `assets/`, `.godot/`, `node_modules/`, `.git/`, generated imports, or server data.
7. Batch related edits. Avoid repeated micro-edits to the same file.
8. Run the smallest relevant check once after the coherent edit.
9. Stop when requested behavior is implemented and verified.

## Avoid

- Whole-repo audits for a local UI change.
- Reading every page script to change one page.
- Re-reading unchanged files.
- Launching multiple subagents for a simple task.
- Long prose plans before implementation.
- Generating documentation unless requested or necessary for future context.

## Escalation

Use a larger model/effort only when a focused Sonnet attempt is blocked by architecture, concurrency, security, or a cross-system bug.
