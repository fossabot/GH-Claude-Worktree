<!--
  Drop-in section for a project's CLAUDE.md. Paste this whole block into your
  project's CLAUDE.md (adjust the two placeholders below), and copy
  scripts/worktrees/wt.sh + docs/git-worktree-parallel-branches.md alongside
  it. See ../README.md for the full install steps, or run the
  /setup-worktrees command if this project already has Claude Code skills.
-->

## Parallel Branch Work — Git Worktrees

To run multiple Claude Code sessions at once, one per branch, use **git
worktrees** — never separate `git clone`s (duplicated history, drift) and
never two sessions in one directory.

Tooling: [`scripts/worktrees/wt.sh`](scripts/worktrees/wt.sh). Full playbook:
[`docs/git-worktree-parallel-branches.md`](docs/git-worktree-parallel-branches.md).

```bash
./scripts/worktrees/wt.sh add my-branch                  # one worktree, branch cut from <BASE_BRANCH>
./scripts/worktrees/wt.sh add-many my-branch other-branch ...   # many at once
./scripts/worktrees/wt.sh list                            # branch, drift vs <BASE_BRANCH>, clean/dirty, path
cd "$(./scripts/worktrees/wt.sh path my-branch)" && claude # start a session
./scripts/worktrees/wt.sh remove my-branch                # refuses if dirty or unpushed
```

Worktrees land **inside this project folder**, in the gitignored
`.claude/worktrees/<branch>/` — never as a second top-level folder beside your
other projects. The script cuts new branches from `origin/<BASE_BRANCH>` with
the upstream unset, and wires up the things a bare `git worktree add` leaves
broken (dependency symlinks, `.claude` settings). One worktree per VS Code
window — never a multi-root workspace.

### No Repo Clones or Cross-Checkout Code Sourcing

NEVER create a `git clone` or an ad-hoc second checkout of this repo, and
NEVER read, import, copy, `git show`, diff-against, or `cd` into another
checkout to source code from it. Stale checkouts are the prime vector for OLD
code being re-introduced (a session lifts a file from an out-of-date sibling
and drags a previously-fixed bug back in). Existing clone directories on disk
are OFF-LIMITS as a source — treat them as if they don't exist; do not delete
them without the developer's go-ahead (they may hold un-pushed work).

**The one sanctioned exception is the developer's own parallel sessions.**
Worktrees created by `scripts/worktrees/wt.sh` under `.claude/worktrees/` are
supported and expected. They share one `.git`, so they do not carry the
staleness risk a clone does, and git itself refuses to check out one branch
in two worktrees. The rule above still applies *inside* each of them: one
session works in its own directory and never reaches sideways into another.

### Subagent Dispatch Inside a Worktree Session — Same Checkout Only

Subagents dispatched via an Agent/Task tool run in the **same physical
working directory** as the session that spawned them — including inside a
worktree. They do not get their own worktree automatically, and should not:
a subagent that creates its own worktree or clone to "get isolation" is
exactly the failure mode this whole pattern exists to prevent, just one
level deeper.

**Rules for the orchestrating session, when dispatching any subagent that
will run Bash/git commands:**

1. **Never pass a worktree/clone-isolation option to a subagent dispatch**,
   and never let a subagent create its own worktree, clone, or second
   checkout. If a task genuinely seems to need isolation beyond the current
   worktree, stop and create that worktree yourself first, then point the
   subagent at its explicit path.
2. **State explicitly, in every dispatch prompt that will run Bash/git**:
   *"Do not run `git checkout`, `git merge`, `git rebase`, `git reset`,
   `git stash`, or `git push` against any branch other than the one we're
   working on. Do not create a git worktree and do not `cd` outside this
   directory. Do not read, copy, or lift code from any sibling
   clone/worktree. If you finish and want it committed, stop and report
   back — I commit and push, not you."*
3. **Trust but verify — especially git state.** After any subagent claims a
   file is unchanged or scope was respected, run your own `git diff`/
   `git status`/`git log` before believing it.
4. If a subagent DID touch git state it shouldn't have (branch switches,
   merges, commits, pushes, a new worktree/clone), stop dispatching
   immediately, assess with direct `git` commands yourself, and surface it to
   the user before doing anything else — don't quietly clean it up.

<!--
  Placeholders to fill in for your project:
    <BASE_BRANCH> — the branch new worktrees are cut from (main, develop, ...)
  If your project enforces a branch-naming convention (e.g. a Jira-key
  pattern), set WT_BRANCH_PATTERN as documented in `wt.sh help` and mention
  the convention here too.
-->
