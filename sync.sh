#!/usr/bin/env bash
#
# sync.sh — keep this repo and the deployed Claude/Codex copies in sync.
#
# This repo is the authoritative source; `push` deploys it, `pull` is for
# recovering edits made directly to the deployed copies.
#
# Deploy mapping (repo  <->  deployed):
#   agents/*.md                     <->  $CLAUDE_DIR/agents/*.md       (file-level, shared dir)
#   commands/*.md                   <->  $CLAUDE_DIR/commands/*.md     (file-level, shared dir)
#   skills/godot-gdscript-patterns  <->  $AGENTS_DIR/skills/godot-gdscript-patterns  (whole tree)
#
# The agents/ and commands/ deploy dirs also hold unrelated files, so this
# script only ever touches the files this repo owns and never deletes there.
# The skill lives in its own dedicated dir, so its tree is mirrored exactly.
# Claude Code reaches the skill via $CLAUDE_DIR/skills/godot-gdscript-patterns,
# which must be a symlink to $AGENTS_DIR/skills/godot-gdscript-patterns. `check`
# verifies the link (a real dir there is a stale copy Claude Code would read
# instead); `push` creates it when absent but never replaces what's there.
#
# Usage:
#   ./sync.sh check   # report drift, exit 1 if any (default)
#   ./sync.sh diff    # show the actual diffs
#   ./sync.sh push    # repo  -> deployed
#   ./sync.sh pull    # deployed -> repo
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
AGENTS_DIR="${AGENTS_DIR:-$HOME/.agents}"

# Build the manifest: "repo_path::deployed_path::kind"
manifest=()
for f in "$REPO_DIR"/agents/*.md; do
  manifest+=("$f::$CLAUDE_DIR/agents/$(basename "$f")::file")
done
for f in "$REPO_DIR"/commands/*.md; do
  manifest+=("$f::$CLAUDE_DIR/commands/$(basename "$f")::file")
done
manifest+=("$REPO_DIR/skills/godot-gdscript-patterns::$AGENTS_DIR/skills/godot-gdscript-patterns::tree")

SKILL_TARGET="$AGENTS_DIR/skills/godot-gdscript-patterns"
SKILL_LINK="$CLAUDE_DIR/skills/godot-gdscript-patterns"

mode="${1:-check}"
drift=0

tree_in_sync() { # $1=src $2=dst -> 0 if identical by content (ignores mtime)
  [[ -d "$2" ]] || return 1
  [[ -z "$(rsync -rcin --delete "$1"/ "$2"/ 2>/dev/null)" ]]
}

link_ok() { # 0 if SKILL_LINK is a symlink resolving to SKILL_TARGET
  [[ -L "$SKILL_LINK" && -d "$SKILL_TARGET" ]] || return 1
  [[ "$(cd "$SKILL_LINK" && pwd -P)" == "$(cd "$SKILL_TARGET" && pwd -P)" ]]
}

link_problem() { # describe why SKILL_LINK is wrong
  if [[ -L "$SKILL_LINK" ]]; then echo "symlink points to $(readlink "$SKILL_LINK"), not $SKILL_TARGET"
  elif [[ -e "$SKILL_LINK" ]]; then echo "is a real directory/file, not a symlink — Claude Code reads that stale copy"
  else echo "is missing"; fi
}

for entry in "${manifest[@]}"; do
  repo="${entry%%::*}"; rest="${entry#*::}"
  deployed="${rest%%::*}"; kind="${rest#*::}"
  label="${repo#"$REPO_DIR"/}"

  case "$mode" in
    check|diff)
      if [[ "$kind" == file ]]; then
        if [[ -f "$deployed" ]] && cmp -s "$repo" "$deployed"; then
          [[ "$mode" == check ]] && echo "OK    $label"
        else
          drift=1
          echo "DRIFT $label"
          [[ "$mode" == diff ]] && diff -u "$deployed" "$repo" || true
        fi
      else
        if tree_in_sync "$repo" "$deployed"; then
          [[ "$mode" == check ]] && echo "OK    $label/"
        else
          drift=1
          echo "DRIFT $label/"
          [[ "$mode" == diff ]] && rsync -rcin --delete "$repo"/ "$deployed"/ || true
        fi
      fi
      ;;
    push)
      if [[ "$kind" == file ]]; then
        cp "$repo" "$deployed" && echo "push  $label"
      else
        mkdir -p "$deployed"
        rsync -a --delete "$repo"/ "$deployed"/ && echo "push  $label/"
      fi
      ;;
    pull)
      if [[ "$kind" == file ]]; then
        cp "$deployed" "$repo" && echo "pull  $label"
      else
        rsync -a --delete "$deployed"/ "$repo"/ && echo "pull  $label/"
      fi
      ;;
    *)
      echo "usage: $0 {check|diff|push|pull}" >&2; exit 2;;
  esac
done

link_label="${SKILL_LINK/#$HOME/~}"
case "$mode" in
  check|diff)
    if link_ok; then
      [[ "$mode" == check ]] && echo "OK    $link_label -> skill"
    else
      drift=1
      echo "LINK  $link_label $(link_problem)"
    fi
    ;;
  push)
    if [[ ! -e "$SKILL_LINK" && ! -L "$SKILL_LINK" ]]; then
      mkdir -p "$(dirname "$SKILL_LINK")"
      ln -s "$SKILL_TARGET" "$SKILL_LINK" && echo "link  $link_label -> skill"
    elif ! link_ok; then
      echo "LINK  $link_label $(link_problem); not replacing it — move it aside, then re-run push" >&2
      exit 1
    fi
    ;;
esac

if [[ "$mode" == check || "$mode" == diff ]]; then
  if [[ "$drift" -eq 0 ]]; then echo "all in sync"; else echo "drift detected"; exit 1; fi
fi
