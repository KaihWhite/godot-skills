#!/usr/bin/env bash
#
# sync.sh — keep this repo and the deployed Claude/Codex copies in sync.
#
# Deploy mapping (repo  <->  deployed):
#   agents/*.md                     <->  $CLAUDE_DIR/agents/*.md       (file-level, shared dir)
#   commands/*.md                   <->  $CLAUDE_DIR/commands/*.md     (file-level, shared dir)
#   skills/godot-gdscript-patterns  <->  $AGENTS_DIR/skills/godot-gdscript-patterns  (whole tree)
#
# The agents/ and commands/ deploy dirs also hold unrelated files, so this
# script only ever touches the files this repo owns and never deletes there.
# The skill lives in its own dedicated dir, so its tree is mirrored exactly.
# (Claude Code reaches the skill via ~/.claude/skills/godot-gdscript-patterns,
#  a symlink to $AGENTS_DIR/skills/godot-gdscript-patterns — not synced here.)
#
# Usage:
#   ./sync.sh check   # report drift, exit 1 if any (default)
#   ./sync.sh diff    # show the actual diffs
#   ./sync.sh push    # repo  -> deployed
#   ./sync.sh pull    # deployed -> repo   (deployed is the authoritative source)
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

mode="${1:-check}"
drift=0

tree_in_sync() { # $1=src $2=dst -> 0 if identical by content (ignores mtime)
  [[ -d "$2" ]] || return 1
  [[ -z "$(rsync -rcin --delete "$1"/ "$2"/ 2>/dev/null)" ]]
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

if [[ "$mode" == check || "$mode" == diff ]]; then
  if [[ "$drift" -eq 0 ]]; then echo "all in sync"; else echo "drift detected"; exit 1; fi
fi
