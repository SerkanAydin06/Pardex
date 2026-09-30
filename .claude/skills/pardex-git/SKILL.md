---
name: pardex-git
description: Use when committing, branching, reviewing diffs, preparing a PR, or checking Git state for PARDEX. Keeps Git output small and avoids expensive broad history/diff reads.
version: 1.0.0
effort: low
---

# PARDEX Git Workflow

Use compact Git output.

## Start

```bash
git status --short
git diff --stat
```

Only inspect diffs for files relevant to the task:

```bash
git diff -- path/to/file
```

Avoid dumping full repository history or huge binary/stat diffs into context.

## Branching

- Use a focused feature/fix branch for substantial work.
- Do not force-push unless explicitly requested.
- Keep unrelated local changes intact.

## Before commit

1. Run the smallest relevant validation via `pardex-verify`.
2. Review `git status --short`.
3. Review targeted changed-file diffs, not every generated file.
4. Commit only task-related files.

## PR summary

Keep PR body compact:
- what changed
- why
- verification actually run
- known remaining issue, if any

Do not add long generated narratives or repeat the entire diff.
