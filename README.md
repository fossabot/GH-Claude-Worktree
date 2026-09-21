# Agent Enhancements

Reusable Claude Code enhancements — instructions, tooling, and agent
skills/commands — meant to be dropped into other Claude-Code-driven projects
rather than rebuilt from scratch each time.

Each enhancement lives in its own top-level folder with a README covering
what it does and how to install it.

## Enhancements

- [`git-worktree-parallel-sessions/`](git-worktree-parallel-sessions/) — run
  multiple Claude Code chat sessions against one project at once, each on its
  own branch, via git worktrees, from a single shared checkout.
