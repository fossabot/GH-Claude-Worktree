# Parallel Branch Work via Git Worktrees

**Tooling:** [`scripts/worktrees/wt.sh`](../scripts/worktrees/wt.sh)

## Goal

Run independent Claude Code sessions on many branches at once, using **git
worktrees**: separate working directories that share one `.git` object store
and remote set. This is what lets you keep a single VS Code project / single
repo checkout open while multiple Claude Code chat sessions each work their
own branch simultaneously — with no session's in-progress, uncommitted
changes visible to any other session.

Do not use a single shared working directory for more than one active
session — two sessions editing the same files on the same branch will step on
each other, and a `git checkout` in one session changes what every other
session sees.

Do **not** solve this with separate `git clone`s or separate VS Code
"projects" per branch — that duplicates `.git` history and causes drift and
merge issues; a stale clone is also the easiest way for old, already-fixed
code to silently come back (someone reads or copies a file from an
out-of-date sibling checkout).

---

## Core rule

> One branch = one git worktree = one working directory.
> Never point two active sessions at the same working directory.
> All worktrees share the same commit history/remotes as the main repo — no
> duplication, no separate clones.

Git enforces half of this for you: it refuses to check out a branch that is
already checked out in another worktree.

---

## Quick start

```bash
# Stand up several sessions at once
./scripts/worktrees/wt.sh add-many feature-a feature-b feature-c

# ...or keep the list in a file, one branch per line (# comments allowed)
./scripts/worktrees/wt.sh add-many --file my-branches.txt

# See what's running
./scripts/worktrees/wt.sh list

# Jump into one
cd "$(./scripts/worktrees/wt.sh path feature-a)" && claude
```

Worktrees are created **inside the project folder**, under
`.claude/worktrees/<branch>/` — one directory per branch, all in one place,
and never a second top-level folder next to your other projects. The path
should be gitignored, so worktrees never show up in `git status` on the main
checkout. Override the root with `WT_ROOT_DIR`.

An optional shell alias makes it shorter:

```bash
# ~/.zshrc
alias wt='/path/to/your/repo/scripts/worktrees/wt.sh'
```

`wt.sh` works identically from inside any worktree — it resolves the main
checkout via `git rev-parse --git-common-dir`, so you never have to `cd` back.

---

## What the script does that `git worktree add` does not

A bare `git worktree add` gives you a fresh checkout and nothing else. A few
things then break, and `wt.sh` handles each:

| Gap | What `wt.sh` does |
|-----|-------------------|
| Gitignored install artifacts (e.g. `node_modules`) don't exist in a new worktree — tests, linters and formatters all fail | Symlinks `node_modules` to the main checkout when the project is Node-based (`--modules install` if a worktree genuinely needs its own copy, `--modules skip` to opt out); no-ops for non-Node projects |
| `node_modules/` in `.gitignore` has a trailing slash, which matches a directory but not our symlink → `?? node_modules` in every worktree | Adds a bare `node_modules` line to `.git/info/exclude` (shared across worktrees, never committed) |
| `.claude/settings.json` and `settings.local.json` are gitignored per-developer files, so a session in a new worktree re-prompts for every tool permission | Copies both from the main checkout |

Because the worktrees live inside the repo, add `.claude/worktrees/` to
`.gitignore` once so the main checkout doesn't trip over it. If your test
runner walks the whole project tree by default (Jest, for example), also
exclude `.claude/worktrees/` from its module/test path patterns — otherwise a
`test` run in the main checkout will pick up every open worktree's copy of
the same test files too (duplicate-module / haste-map collisions in Jest's
case).

`wt.sh` can also enforce a branch-naming convention if your project has one
(e.g. a Jira-key pattern) — set `WT_BRANCH_PATTERN` to a regex; leave it unset
for no enforcement. See `wt.sh help` for the full environment variable list.

---

## Commands

| Command | What it does |
|---------|--------------|
| `add <branch>` | Create one worktree (and the branch, if new) |
| `add-many <branch>...` | Create several; `--file list.txt` reads them from a file |
| `list` | Every worktree: branch, ahead/behind the base branch, clean/dirty, path |
| `path <branch>` | Print a worktree's absolute path (for `cd "$(...)"`) |
| `repair [<branch>...]` | Re-link dependencies / settings on existing worktrees |
| `remove <branch>` | Remove a worktree — **refuses** if it is dirty or has unpushed commits |
| `prune` | Drop git's records of worktrees deleted by hand |

Options for `add` / `add-many`: `--base <ref>`, `--modules auto|symlink|install|skip`,
`--force-name`. Environment defaults: `WT_ROOT_DIR`, `WT_BASE`, `WT_MODULES`,
`WT_REMOTE`, `WT_BRANCH_PATTERN`. `wt.sh help` prints all of it.

---

## Visual editing (optional)

To browse or edit a branch's files in VS Code, use `File > Open Folder` and
point it at that worktree's folder — a normal folder open, not a new project.
It is still the same repository underneath.

Keep each VS Code window scoped to **one** worktree folder. Do not combine
multiple worktrees into a single multi-root VS Code workspace — the Claude
Code extension pins to the first folder only and does not reliably read
config or index files from the others.

---

## Cleanup

```bash
./scripts/worktrees/wt.sh remove feature-a                  # safe: refuses if dirty/unpushed
./scripts/worktrees/wt.sh remove feature-a --force          # discard uncommitted work
./scripts/worktrees/wt.sh remove feature-a --delete-branch  # also drop the local branch
./scripts/worktrees/wt.sh prune                             # after deleting folders by hand
```

`remove` deletes the `node_modules` **symlink**, never the main checkout's
real `node_modules`.

---

## Things worktrees do NOT isolate

Worktrees isolate files, not runtime state. These are still shared across
every parallel session:

- Anything bound to a fixed local port
- `~/.claude` state and any global CLI configuration outside the repo
- The shared `.git` object store — a `git gc` or a destructive ref operation
  in one worktree affects all of them

Plan around these manually (for example, run each worktree's dev server on a
different port) if multiple sessions need to run something simultaneously.

---

## Worktrees vs. Agent-tool subagents — different mechanisms, don't mix them

This pattern is for **developer-driven parallel sessions**: you, the human,
open a separate Claude Code session per worktree and drive each one.

It is a different thing from a `Task`/`Agent`-tool subagent spawned *within*
one session. Subagents dispatched that way run in the **same physical working
directory** as the session that spawned them — they do not get their own
worktree automatically. Do not pass a worktree-isolation option to a subagent
dispatch as a substitute for reading this doc; if a subagent's task
genuinely needs an isolated checkout, create the worktree yourself first (as
the developer or orchestrating session) and dispatch the subagent to work
inside that specific worktree's directory, stating the path explicitly.

A subagent given a shared working directory can still collide with other
in-flight work if it runs `git checkout`, `git merge`, `git reset`, or
`git push` against branches it wasn't asked to touch. If you dispatch a
subagent that will run git commands, tell it explicitly which branch/worktree
directory it's scoped to and instruct it not to touch git state outside that
scope — see [`claude-template/CLAUDE-worktrees-section.md`](../claude-template/CLAUDE-worktrees-section.md)
for ready-to-use wording.

---

## Practical concurrency note

Running many concurrent sessions is fine mechanically, but a human can
usually only actively supervise 2–3 at a time. Running more is fine — just
expect to context-switch between terminals rather than watching them all live,
and lean on `wt.sh list` to see which worktrees have moved.
