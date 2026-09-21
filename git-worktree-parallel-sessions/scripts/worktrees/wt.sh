#!/usr/bin/env bash
#
# wt.sh — parallel branch development via git worktrees
#
# One branch = one worktree = one working directory. Every worktree shares the
# main repo's .git object store and remotes, so there is no duplicated history
# and no drift the way separate `git clone`s cause.
#
# This lets multiple Claude Code sessions work on the same repo at the same
# time — each session cd's into its own worktree folder and operates on its
# own branch — without any session seeing another session's in-progress,
# uncommitted changes. That isolation is the whole point: it is what makes it
# safe to run several agents against one project concurrently.
#
# Usage:
#   scripts/worktrees/wt.sh add my-branch [options]
#   scripts/worktrees/wt.sh add-many my-branch other-branch ...
#   scripts/worktrees/wt.sh list
#   scripts/worktrees/wt.sh path my-branch
#   scripts/worktrees/wt.sh repair [my-branch]
#   scripts/worktrees/wt.sh remove my-branch [--force]
#   scripts/worktrees/wt.sh prune
#
# Run `scripts/worktrees/wt.sh help` for full option documentation.

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults (override with env vars or per-command flags)
# ---------------------------------------------------------------------------

DEFAULT_BASE="${WT_BASE:-main}"
DEFAULT_REMOTE="${WT_REMOTE:-origin}"
DEFAULT_MODULES="${WT_MODULES:-auto}"   # auto | symlink | install | skip
# Optional: enforce branch names against a pattern (e.g. a Jira-key convention
# like '^PROJ-[0-9]+(-[a-z0-9][a-z0-9.-]*)?$'). Empty = no enforcement.
BRANCH_PATTERN="${WT_BRANCH_PATTERN:-}"

# ---------------------------------------------------------------------------
# Locate the MAIN worktree, so this script behaves identically no matter which
# worktree it is invoked from. --git-common-dir always points at the real .git.
# ---------------------------------------------------------------------------

if ! GIT_COMMON_DIR="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; then
  echo "error: not inside a git repository" >&2
  exit 1
fi
MAIN_ROOT="$(cd "$(dirname "$GIT_COMMON_DIR")" && pwd)"
REPO_NAME="$(basename "$MAIN_ROOT")"
WT_ROOT="${WT_ROOT_DIR:-$MAIN_ROOT/.claude/worktrees}"

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

if [ -t 1 ]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'
else
  C_RESET=""; C_BOLD=""; C_DIM=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""
fi

step()  { printf '%s==>%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
ok()    { printf '%s  ok%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn()  { printf '%swarn%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die()   { printf '%serror%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

wt_dir_for() { printf '%s/%s' "$WT_ROOT" "$1"; }

branch_exists_local()  { git -C "$MAIN_ROOT" show-ref --verify --quiet "refs/heads/$1"; }
branch_exists_remote() { git -C "$MAIN_ROOT" show-ref --verify --quiet "refs/remotes/$DEFAULT_REMOTE/$1"; }

validate_branch_name() {
  local branch="$1" force="$2"
  [ -n "$BRANCH_PATTERN" ] || return 0
  if [ "$force" = "yes" ]; then
    return 0
  fi
  if ! printf '%s' "$branch" | grep -Eq "$BRANCH_PATTERN"; then
    die "branch name '$branch' does not match WT_BRANCH_PATTERN ('$BRANCH_PATTERN').
      Set WT_BRANCH_PATTERN to your project's branch-naming convention (or leave
      it unset to disable this check). Use --force-name to bypass once, deliberately."
  fi
}

# .gitignore's "node_modules/" (with the trailing slash) matches a directory but
# NOT the symlink we create, so a worktree cut from a branch that predates a
# .gitignore fix would show "?? node_modules". info/exclude lives in the
# shared .git dir, is never committed, and applies to every worktree at once.
ensure_modules_excluded() {
  local exclude; exclude="$MAIN_ROOT/.git/info/exclude"
  [ -f "$exclude" ] || { mkdir -p "$(dirname "$exclude")"; : > "$exclude"; }
  grep -qxF 'node_modules' "$exclude" 2>/dev/null || \
    printf '\n# wt.sh: node_modules is a symlink in worktrees\nnode_modules\n' >> "$exclude"
}

# node_modules is the one thing git worktrees do not carry over that a Node
# project actually needs: it's gitignored, can be huge, and most tooling
# (test runners, linters, formatters) won't run without it. Symlinking to the
# main checkout's copy is the default, so N worktrees cost 0 bytes and 0
# install time. `auto` no-ops for non-Node projects (no package.json).
setup_modules() {
  local dir="$1" mode="$2"

  if [ "$mode" = "auto" ]; then
    if [ -f "$MAIN_ROOT/package.json" ]; then
      mode="symlink"
    else
      mode="skip"
    fi
  fi

  case "$mode" in
    symlink)
      if [ ! -d "$MAIN_ROOT/node_modules" ]; then
        warn "no node_modules in $MAIN_ROOT — run your package manager's install there, then 'wt.sh repair'"
        return 0
      fi
      [ -e "$dir/node_modules" ] || ln -s "$MAIN_ROOT/node_modules" "$dir/node_modules"
      ensure_modules_excluded
      ;;
    install)
      ( cd "$dir" && npm install --no-audit --no-fund )
      ;;
    skip) : ;;
    *) die "unknown --modules mode '$mode' (expected auto|symlink|install|skip)" ;;
  esac
}

# .claude/settings.json and settings.local.json are gitignored per-developer
# files (tool permissions etc). Copy them in so a Claude Code session in the
# worktree behaves like one in the main checkout instead of re-prompting.
seed_claude_settings() {
  local dir="$1" f
  mkdir -p "$dir/.claude"
  for f in settings.json settings.local.json; do
    if [ -f "$MAIN_ROOT/.claude/$f" ] && [ ! -e "$dir/.claude/$f" ]; then
      cp "$MAIN_ROOT/.claude/$f" "$dir/.claude/$f"
    fi
  done
}

# ---------------------------------------------------------------------------
# add
# ---------------------------------------------------------------------------

cmd_add() {
  local branch="" base="$DEFAULT_BASE" modules="$DEFAULT_MODULES"
  local force_name="no" quiet="no"

  while [ $# -gt 0 ]; do
    case "$1" in
      --base)        base="${2:?--base needs a value}"; shift 2 ;;
      --modules)     modules="${2:?--modules needs a value}"; shift 2 ;;
      --force-name)  force_name="yes"; shift ;;
      --quiet)       quiet="yes"; shift ;;
      -*)            die "unknown option '$1' for 'add'" ;;
      *)             [ -z "$branch" ] || die "add takes one branch name (got '$branch' and '$1')"
                     branch="$1"; shift ;;
    esac
  done

  [ -n "$branch" ] || die "usage: wt.sh add <branch> [--base $DEFAULT_BASE] [--modules auto|symlink|install|skip]"
  validate_branch_name "$branch" "$force_name"

  local dir; dir="$(wt_dir_for "$branch")"
  [ -e "$dir" ] && die "$dir already exists — use 'wt.sh remove $branch' first, or pick another name"

  mkdir -p "$WT_ROOT"

  step "fetching $DEFAULT_REMOTE"
  git -C "$MAIN_ROOT" fetch "$DEFAULT_REMOTE" "$base" --quiet || warn "fetch of $base failed — continuing with local refs"
  git -C "$MAIN_ROOT" fetch "$DEFAULT_REMOTE" --quiet 2>/dev/null || true

  local created_from_base="no"
  if branch_exists_local "$branch"; then
    step "attaching existing local branch $branch"
    git -C "$MAIN_ROOT" worktree add "$dir" "$branch"
  elif branch_exists_remote "$branch"; then
    step "checking out $DEFAULT_REMOTE/$branch"
    git -C "$MAIN_ROOT" worktree add --track -b "$branch" "$dir" "$DEFAULT_REMOTE/$branch"
  else
    branch_exists_remote "$base" || die "base branch '$DEFAULT_REMOTE/$base' not found"
    step "creating $branch from $DEFAULT_REMOTE/$base"
    git -C "$MAIN_ROOT" worktree add -b "$branch" "$dir" "$DEFAULT_REMOTE/$base"
    created_from_base="yes"
  fi

  # A branch cut from the base branch inherits it as its upstream, which makes
  # a bare `git push` target the base branch by accident. Detach it.
  if [ "$created_from_base" = "yes" ]; then
    git -C "$dir" branch --unset-upstream "$branch" 2>/dev/null || true
  fi

  step "wiring dependencies ($modules)"
  setup_modules "$dir" "$modules"

  seed_claude_settings "$dir"

  ok "$branch -> $dir"
  if [ "$quiet" = "no" ]; then
    printf '\n%sStart a session:%s\n  cd %s && claude\n\n' "$C_BOLD" "$C_RESET" "$dir"
    printf '%sOr open it visually:%s VS Code > File > Open Folder > %s\n' "$C_DIM" "$C_RESET" "$dir"
    printf '%s(one worktree per window — never a multi-root workspace)%s\n' "$C_DIM" "$C_RESET"
  fi
}

# ---------------------------------------------------------------------------
# add-many
# ---------------------------------------------------------------------------

cmd_add_many() {
  local branches=() passthru=() file=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --file)      file="${2:?--file needs a path}"; shift 2 ;;
      --base|--modules) passthru+=("$1" "${2:?$1 needs a value}"); shift 2 ;;
      --force-name) passthru+=("$1"); shift ;;
      -*)          die "unknown option '$1' for 'add-many'" ;;
      *)           branches+=("$1"); shift ;;
    esac
  done

  if [ -n "$file" ]; then
    [ -f "$file" ] || die "no such file: $file"
    while IFS= read -r line; do
      line="${line%%#*}"; line="$(printf '%s' "$line" | tr -d '[:space:]')"
      [ -n "$line" ] && branches+=("$line")
    done < "$file"
  fi

  [ "${#branches[@]}" -gt 0 ] || die "usage: wt.sh add-many branch-a branch-b ... | --file branches.txt"

  local failed=() b
  for b in "${branches[@]}"; do
    printf '\n%s--- %s ---%s\n' "$C_BOLD" "$b" "$C_RESET"
    if ! cmd_add "$b" --quiet "${passthru[@]+"${passthru[@]}"}"; then
      failed+=("$b")
    fi
  done

  printf '\n%sCreated %d of %d worktrees under %s%s\n' \
    "$C_BOLD" "$(( ${#branches[@]} - ${#failed[@]} ))" "${#branches[@]}" "$WT_ROOT" "$C_RESET"
  if [ "${#failed[@]}" -gt 0 ]; then
    warn "failed: ${failed[*]}"
    return 1
  fi
  printf '\nOpen one terminal tab per worktree and run:\n'
  for b in "${branches[@]}"; do
    printf '  cd %s && claude\n' "$(wt_dir_for "$b")"
  done
}

# ---------------------------------------------------------------------------
# list
# ---------------------------------------------------------------------------

cmd_list() {
  printf '%s%-36s %-16s %-8s %s%s\n' \
    "$C_BOLD" "BRANCH" "VS $DEFAULT_BASE" "STATE" "PATH" "$C_RESET"

  local dir branch state counts ahead behind
  while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    branch="$(git -C "$dir" branch --show-current 2>/dev/null || echo '(detached)')"

    if [ -n "$(git -C "$dir" status --porcelain 2>/dev/null)" ]; then
      state="${C_YELLOW}dirty${C_RESET}"
    else
      state="${C_GREEN}clean${C_RESET}"
    fi

    counts="-"
    if git -C "$dir" rev-parse --verify --quiet "$DEFAULT_REMOTE/$DEFAULT_BASE" >/dev/null; then
      read -r behind ahead <<< "$(git -C "$dir" rev-list --left-right --count "$DEFAULT_REMOTE/$DEFAULT_BASE...HEAD" 2>/dev/null || echo '0 0')"
      counts="+${ahead}/-${behind}"
    fi

    printf '%-36s %-16s %-8b %s\n' "$branch" "$counts" "$state" "$dir"
  done < <(git -C "$MAIN_ROOT" worktree list --porcelain | sed -n 's/^worktree //p')
}

# ---------------------------------------------------------------------------
# path / repair / remove / prune
# ---------------------------------------------------------------------------

cmd_path() {
  local branch="${1:?usage: wt.sh path <branch>}"
  local dir; dir="$(wt_dir_for "$branch")"
  [ -d "$dir" ] || die "no worktree at $dir"
  printf '%s\n' "$dir"
}

cmd_repair() {
  local targets=() dir
  if [ $# -gt 0 ]; then
    for dir in "$@"; do targets+=("$(wt_dir_for "$dir")"); done
  else
    while IFS= read -r dir; do
      [ "$dir" = "$MAIN_ROOT" ] || targets+=("$dir")
    done < <(git -C "$MAIN_ROOT" worktree list --porcelain | sed -n 's/^worktree //p')
  fi

  for dir in "${targets[@]+"${targets[@]}"}"; do
    [ -d "$dir" ] || { warn "skipping missing $dir"; continue; }
    step "repairing $(basename "$dir")"
    if [ ! -e "$dir/node_modules" ]; then setup_modules "$dir" "$DEFAULT_MODULES"; ok "dependencies"; fi
    ensure_modules_excluded
    seed_claude_settings "$dir"
  done
  git -C "$MAIN_ROOT" worktree prune
  ok "repair complete"
}

cmd_remove() {
  local branch="" force="no" delete_branch="no"
  while [ $# -gt 0 ]; do
    case "$1" in
      --force)         force="yes"; shift ;;
      --delete-branch) delete_branch="yes"; shift ;;
      -*)              die "unknown option '$1' for 'remove'" ;;
      *)               branch="$1"; shift ;;
    esac
  done
  [ -n "$branch" ] || die "usage: wt.sh remove <branch> [--force] [--delete-branch]"

  local dir; dir="$(wt_dir_for "$branch")"
  [ -d "$dir" ] || die "no worktree at $dir"

  if [ "$force" = "no" ]; then
    [ -z "$(git -C "$dir" status --porcelain)" ] || \
      die "$branch has uncommitted changes. Commit them, or re-run with --force to discard."
    if git -C "$dir" rev-parse --verify --quiet "$DEFAULT_REMOTE/$branch" >/dev/null; then
      [ "$(git -C "$dir" rev-list --count "$DEFAULT_REMOTE/$branch..HEAD")" -eq 0 ] || \
        die "$branch has commits not pushed to $DEFAULT_REMOTE. Push them, or re-run with --force."
    else
      die "$branch has never been pushed — its commits exist only here. Push it, or re-run with --force."
    fi
  fi

  # node_modules is a symlink to the main checkout; remove the link (never the
  # target) before git touches the directory.
  [ -L "$dir/node_modules" ] && rm "$dir/node_modules"

  if [ "$force" = "yes" ]; then
    git -C "$MAIN_ROOT" worktree remove --force "$dir"
  else
    git -C "$MAIN_ROOT" worktree remove "$dir"
  fi
  ok "removed worktree $dir"

  if [ "$delete_branch" = "yes" ]; then
    git -C "$MAIN_ROOT" branch -D "$branch"
    ok "deleted local branch $branch"
  fi
}

cmd_prune() {
  git -C "$MAIN_ROOT" worktree prune -v
  ok "pruned stale worktree records"
}

# ---------------------------------------------------------------------------
# help
# ---------------------------------------------------------------------------

cmd_help() {
  cat <<EOF
${C_BOLD}wt.sh${C_RESET} — parallel branch development via git worktrees

  One branch = one worktree = one working directory. Never point two active
  Claude Code sessions at the same directory.

${C_BOLD}COMMANDS${C_RESET}
  add <branch> [opts]          Create a worktree (and the branch, if new)
  add-many <branch>... [opts]  Create several at once
  add-many --file list.txt     ...or read branch names from a file
  list                         Show every worktree: branch, drift, state, path
  path <branch>                Print a worktree's absolute path
  repair [<branch>...]         Re-link dependencies / .claude settings
  remove <branch> [--force]    Remove a worktree (refuses if dirty/unpushed)
                  [--delete-branch]
  prune                        Drop records of manually deleted worktrees

${C_BOLD}OPTIONS (add / add-many)${C_RESET}
  --base <ref>        Branch point for new branches   (default: $DEFAULT_BASE)
  --modules <mode>    auto | symlink | install | skip  (default: $DEFAULT_MODULES)
  --force-name        Bypass WT_BRANCH_PATTERN, if one is set

${C_BOLD}ENVIRONMENT${C_RESET}
  WT_ROOT_DIR       Where worktrees live       (default: <repo>/.claude/worktrees)
  WT_BASE           Default base branch        (default: $DEFAULT_BASE)
  WT_MODULES        Default modules mode       (default: $DEFAULT_MODULES)
  WT_REMOTE         Remote name                (default: $DEFAULT_REMOTE)
  WT_BRANCH_PATTERN Enforce a branch-name regex (default: unset, no enforcement)

${C_BOLD}CURRENT PATHS${C_RESET}
  main repo   $MAIN_ROOT
  worktrees   $WT_ROOT

${C_BOLD}EXAMPLES${C_RESET}
  # Stand up several sessions at once
  scripts/worktrees/wt.sh add-many feature-a feature-b feature-c

  # Branch from something other than the default base
  scripts/worktrees/wt.sh add hotfix-1 --base release/2.0

  # Jump into one
  cd "\$(scripts/worktrees/wt.sh path feature-a)" && claude
EOF
}

# ---------------------------------------------------------------------------

main() {
  local cmd="${1:-help}"; shift || true
  case "$cmd" in
    add)        cmd_add "$@" ;;
    add-many)   cmd_add_many "$@" ;;
    list|ls)    cmd_list "$@" ;;
    path)       cmd_path "$@" ;;
    repair)     cmd_repair "$@" ;;
    remove|rm)  cmd_remove "$@" ;;
    prune)      cmd_prune "$@" ;;
    help|-h|--help) cmd_help ;;
    *)          die "unknown command '$cmd' (try: wt.sh help)" ;;
  esac
}

main "$@"
