---
description: Install the git-worktree parallel-session pattern into this project
---

# /setup-worktrees

Bootstrap this project so multiple Claude Code sessions can run against it at
once, each on its own branch, via git worktrees — one shared checkout, no
clones, no cross-session file collisions.

Source material for everything this command installs lives in the
`git-worktree-parallel-sessions/` enhancement in the `AgentEnhancements` repo
(https://github.com/synaptic-josh/AgentEnhancements, branch
`Git-Worktree-Setup` or later `main`). If that repo isn't available locally,
ask the user for its path or a copy of the four source files listed below
before proceeding.

## Steps

1. **Confirm this project is a git repo** (`git rev-parse --is-inside-work-tree`).
   If not, stop and tell the user — worktrees require an existing repo.

2. **Identify the base branch** new worktrees should cut from (ask the user
   if it isn't obvious — check `git remote show origin` or the default branch
   on GitHub). Common answers: `main`, `develop`.

3. **Copy the tooling in**, from the `git-worktree-parallel-sessions/` folder:
   - `scripts/worktrees/wt.sh` → `<project>/scripts/worktrees/wt.sh` (keep it executable: `chmod +x`)
   - `docs/git-worktree-parallel-branches.md` → `<project>/docs/git-worktree-parallel-branches.md`
     (or wherever this project keeps its docs — ask if `docs/` doesn't exist)

4. **Merge the CLAUDE.md section.** Read
   `claude-template/CLAUDE-worktrees-section.md`, replace `<BASE_BRANCH>` with
   the branch identified in step 2, and append the whole section to the
   project's `CLAUDE.md` (create one if it doesn't exist). Do not overwrite
   existing CLAUDE.md content — this is an addition, not a replacement.

5. **Update `.gitignore`** — add `.claude/worktrees/` if it isn't already
   ignored.

6. **If this is a Node project with Jest**, check whether `jest.config.js` (or
   equivalent) walks the whole repo by default. If so, add
   `.claude/worktrees/` to `modulePathIgnorePatterns` and
   `testPathIgnorePatterns` — otherwise a test run from the main checkout will
   also collect every open worktree's copy of the same test files
   (duplicate-module collisions). Skip this step for other stacks; flag to
   the user that their own test runner may need an equivalent exclusion if it
   walks the full tree.

7. **Verify**: run `./scripts/worktrees/wt.sh help` from the project root and
   confirm it resolves the repo correctly (prints the right "main repo" path).
   Do not create a real worktree as part of setup unless the user asks for
   one — this command installs the tooling, it doesn't start using it.

8. **Report back** what was added/changed (new files, CLAUDE.md diff,
   .gitignore line, test-runner exclusion if any) and point the user at
   `docs/git-worktree-parallel-branches.md` for the full usage guide.

## Notes

- This command is idempotent-ish: re-running it should detect files that
  already exist (matching content) and skip them rather than duplicating the
  CLAUDE.md section or clobbering a customized `wt.sh`.
- Do not invent a branch-naming enforcement pattern (`WT_BRANCH_PATTERN`)
  unless the user states one — leave it unset by default.
- This command only installs tooling; it never pushes or opens a PR on its
  own without being asked.
