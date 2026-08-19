#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

clone_repo() {
  local name="$1"
  local target="$root/$name"

  if [[ -d "$target/.git" ]]; then
    echo "$name is already cloned"
    return
  fi

  if [[ -e "$target" ]]; then
    echo "error: $target exists but is not a Git repository" >&2
    exit 1
  fi

  git clone "git@github.com:GilmanLab/$name.git" "$target"
}

clone_repo networking
clone_repo aws
clone_repo sandbox
