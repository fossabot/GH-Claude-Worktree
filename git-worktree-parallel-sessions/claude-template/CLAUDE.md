# Project Instructions (Claude Code)

<!--
  Generic starter CLAUDE.md for a new Claude-Code-driven project. This is a
  distilled, project-agnostic version of operating rules that have proven
  useful across real projects — trimmed of anything domain-specific. Fill in
  the placeholders (marked <LIKE_THIS>), delete sections that don't apply,
  and layer your own project/domain rules on top.

  This file assumes the git-worktree-parallel-sessions enhancement is
  installed alongside it (scripts/worktrees/wt.sh,
  docs/git-worktree-parallel-branches.md) — see ../README.md if not.
-->

## Communication Style

Be terse. Plain English, no padding.

- Lead with the answer/conclusion in 1-3 sentences. No preamble, no restating
  the question.
- Cut hedging, summaries-of-what-you-just-said, and "Here's what I found:"
  scaffolding.
- Skip headers/bullets/bold for short answers — save structure for genuinely
  long, multi-part output.
- Don't narrate process ("I confirmed X, then I checked Y, then I verified
  Z") unless the user asked how you got there. State the result.
- If the finding is bad news or blocked, say so directly in the first line —
  don't bury it under evidence.

## Scope Control — No Regressions

- **Only modify files explicitly required by the current task.** No
  "while I'm here" fixes, refactors, reformats, or cleanups outside scope.
- **If you notice issues outside scope**, tell the user — do NOT fix them.
  Suggest a follow-up task/ticket.
- **Every changed file must be traceable to the current task.** If you can't
  explain why a file changed in terms of the task, revert it before
  committing.
- When the user states a task's scope explicitly ("just the LWC," "backend
  only," "single-file fix"), treat it as binding, not a suggestion to expand
  on your own judgment. If you believe more scope is genuinely needed, say so
  as a recommendation and wait for approval — don't just do it and report it
  as done.

## Git Safety

- **Always create feature branches from `<BASE_BRANCH>`** (e.g. `main` or
  `develop`) — never from anywhere else without being told to.
- **Always `git fetch` the base branch immediately before creating a feature
  branch**, then branch from the freshly-fetched remote tip — never from a
  stale local ref. Pattern: `git fetch origin <BASE_BRANCH> && git checkout -b <feature> origin/<BASE_BRANCH>`.
- **Never** force push to any branch.
- Only commit and push to feature branches, never directly to the base
  branch.
- Always confirm with the user before pushing to any remote.
- **Never** use `git reset --hard` without explicit user confirmation.
- Always create NEW commits rather than amending, unless explicitly asked to
  amend.
- PRs go to `<BASE_BRANCH>`, unless explicitly told otherwise.

### Parallel Branch Work — Git Worktrees

<!-- Paste the contents of CLAUDE-worktrees-section.md here (with
     <BASE_BRANCH> filled in), or keep this pointer if you'd rather link out. -->

See [`docs/git-worktree-parallel-branches.md`](../docs/git-worktree-parallel-branches.md)
and [`CLAUDE-worktrees-section.md`](CLAUDE-worktrees-section.md) for the full
git-worktree pattern this project uses for running multiple Claude Code
sessions in parallel, one per branch, from a single checkout.

## Model Tier Selection & Delegation

If your Claude Code setup has access to cheaper-model subagents (e.g. a
Haiku-pinned agent definition), route mechanical work to them instead of
doing it on the main conversation loop:

| Tier | Example work | Where it runs |
|------|--------------|----------------|
| Trivial / mechanical | formatting, file moves/renames, single-field lookups, boilerplate scaffolding | Delegate to a cheap-tier subagent |
| Moderate / domain | focused debugging, tracing a specific bug through a few files, targeted refactors | Delegate to a mid-tier subagent if one exists for the domain |
| Complex / cross-cutting | architecture decisions, multi-file refactors spanning the whole system, anything needing full project context at once | Keep on the main loop |

The main conversation loop cannot switch its own model mid-session — the only
way to run work on a cheaper tier is to delegate it to a subagent whose
definition pins that tier.

## Executing Actions With Care

Carefully consider the reversibility and blast radius of actions. Local,
reversible actions (editing files, running tests) can proceed freely.
Actions that are hard to reverse or affect shared/external state — pushing
code, force operations, deleting branches, modifying CI, posting to external
services — should be confirmed with the user first unless already authorized
in this file.

## Deployment Rules

<!--
  Fill in for your project. Example shape:
  - Target environment(s) and how they're configured (don't modify config files blindly)
  - Which environments Claude may deploy to vs. never deploy to
  - Whether deploys require explicit user go-ahead ("never deploy unless told")
-->

## Project Structure

<!-- Fill in: directory layout, key entry points, test conventions. -->

## Common Mistakes to Avoid

<!--
  This section is where hard-won, project-specific lessons accumulate over
  time — each one should name the concrete failure it prevents, not just
  state a generic best practice. Start empty; add entries as they come up.
-->
