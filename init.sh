#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
target="$root/networking"

if [[ -d "$target/.git" ]]; then
  echo "networking is already cloned"
  exit 0
fi

if [[ -e "$target" ]]; then
  echo "error: $target exists but is not a Git repository" >&2
  exit 1
fi

git clone git@github.com:GilmanLab/networking.git "$target"
