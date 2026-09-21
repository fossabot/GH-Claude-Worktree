# Git Worktree Parallel Sessions

Run multiple Claude Code chat sessions against **one project, one VS Code
window setup, one repo checkout** — with each session on its own branch, and
none of them seeing another session's in-progress, uncommitted changes.

The mechanism is [git worktrees](https://git-scm.com/docs/git-worktree):
separate working directories that all share the same `.git` object store and
remotes. One branch = one worktree = one directory. Git itself refuses to
check out a branch that's already checked out elsewhere, so sessions can't
collide on the same branch by accident.

## What's in here

```
git-worktree-parallel-sessions/
├── README.md                              — this file
├── scripts/worktrees/wt.sh                — the worktree management script
├── docs/git-worktree-parallel-branches.md — full usage playbook
└── claude-template/
    ├── CLAUDE.md                          — generic starter CLAUDE.md for a brand-new project
    ├── CLAUDE-worktrees-section.md        — just the worktree section, to paste into an existing CLAUDE.md
    └── commands/setup-worktrees.md        — a Claude Code slash command that installs this into a project
```

## Installing into a project

**Option A — let Claude Code do it.** Copy `claude-template/commands/setup-worktrees.md`
into your project's `.claude/commands/`, then in that project run
`/setup-worktrees`. It walks through copying the script, merging the CLAUDE.md
section, and updating `.gitignore` (and test-runner ignore patterns, if
applicable).

**Option B — do it by hand:**

1. Copy `scripts/worktrees/wt.sh` into your project at the same relative
   path, keep it executable (`chmod +x`).
2. Copy `docs/git-worktree-parallel-branches.md` into your project's docs.
3. Either:
   - start a new project from `claude-template/CLAUDE.md` (fill in the
     `<BASE_BRANCH>` placeholder and the empty sections), or
   - append `claude-template/CLAUDE-worktrees-section.md` to an existing
     CLAUDE.md (fill in `<BASE_BRANCH>` first).
4. Add `.claude/worktrees/` to `.gitignore`.
5. If your project uses Jest (or any test runner that walks the whole repo
   tree by default), exclude `.claude/worktrees/` from its module/test path
   patterns — see the playbook doc for why.

## Quick usage once installed

```bash
./scripts/worktrees/wt.sh add my-branch          # create a worktree + branch
cd "$(./scripts/worktrees/wt.sh path my-branch)" && claude   # start a session there
./scripts/worktrees/wt.sh list                   # see every worktree: branch, drift, clean/dirty, path
./scripts/worktrees/wt.sh remove my-branch        # tear down (refuses if dirty/unpushed)
```

Full command reference, environment variables, and the reasoning behind each
design choice: [`docs/git-worktree-parallel-branches.md`](docs/git-worktree-parallel-branches.md).

## Why not just `git clone` per branch?

Separate clones duplicate the entire `.git` history per branch, drift out of
sync with each other, and are the single easiest way for stale/already-fixed
code to silently come back — an agent or a developer reads a file from an
out-of-date sibling clone and reintroduces a bug that was already fixed on
the branch they're actually working on. Worktrees share one `.git`, so
there's nothing to drift; every worktree always sees the same object store
and the same remote refs.

## Why not the Agent-tool / Task-tool subagent isolation feature instead?

That's a different, complementary mechanism — a subagent spawned inside one
Claude Code session, for one delegated piece of work within that session. It
answers "how do I hand off a sub-task safely," not "how do I run several
independent chat sessions on the same project." Don't use worktree isolation
as a substitute for scoping a subagent's instructions, and don't let a
subagent create its own worktree — see the "Worktrees vs. Agent-tool
subagents" section in the playbook doc.
