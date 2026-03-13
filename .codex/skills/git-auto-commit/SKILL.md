---
name: git-auto-commit
description: Inspect, summarize, stage, and commit changes for the current Git repository. Use when the user asks to "提交git", "提交代码", "commit", "提交到git", "帮我提交", or otherwise wants Codex to review uncommitted files, explain what changed, and create a Git commit automatically.
---

# Git Auto Commit

Inspect the current repository, summarize uncommitted work, stage the right files, and create a clear non-interactive Git commit. Work from the active project repo, not an unrelated parent repo, unless the user explicitly asks otherwise.

## Workflow

1. Detect the repository to operate on.
2. Review uncommitted changes before staging anything.
3. Summarize the change set in concise user-facing language.
4. Stage the relevant files.
5. Write a commit message grounded in the actual diff.
6. Create the commit.

## Detect The Target Repo

Prefer the Git repository rooted at the current project the user is working in.

If the workspace contains both a parent repo and a nested project repo, operate on the nested project repo that matches the active task unless the user explicitly asks to commit from the parent.

Use non-interactive commands only.

## Inspect Before Staging

Always inspect:

- `git status --short`
- `git diff --stat`
- `git diff --cached --stat`

If the diff is non-trivial, inspect changed files or focused hunks before committing so the summary and commit message reflect the real work.

Do not blindly stage everything if generated artifacts, caches, or unrelated files appear in the working tree.

Prefer to exclude files such as:

- `.DS_Store`
- build outputs such as `.build/`
- transient logs
- editor temp files
- unrelated user files outside the task at hand

## Summarize The Changes

Before committing, produce a concise summary for the user that covers:

- which files or areas changed
- the functional purpose of those changes
- any notable fixes, refactors, docs updates, or cleanups

Group the summary by change area rather than listing every file when the diff is large.

## Stage Carefully

After inspection, stage the intended files explicitly. Prefer path-based staging over reckless global staging when noise exists in the repo.

Use `git add -A` only when the working tree is clearly limited to the task at hand.

## Write The Commit Message

Write a commit message from the actual changes. Prefer conventional prefixes when they fit:

- `feat:` for user-facing behavior or new capability
- `fix:` for bug fixes or regressions
- `refactor:` for structural code changes without behavior intent
- `docs:` for documentation-only changes
- `chore:` for maintenance or housekeeping
- `perf:` for measurable performance work

Keep the subject line specific. Avoid generic messages such as `update files` or `fix issues`.

Add a body only when it materially helps explain multiple change groups.

## Commit

Create the commit after staging and summarizing.

Do not push unless the user explicitly asks to push.

If there is nothing to commit, say so clearly instead of forcing an empty commit.

## Default Trigger Behavior

When the user says a short instruction such as `提交git`, `提交代码`, or `commit一下`, do this workflow end-to-end without waiting for extra confirmation unless there is a real ambiguity about which repository or which subset of files should be committed.
