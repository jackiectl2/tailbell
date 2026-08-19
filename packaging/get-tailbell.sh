#!/usr/bin/env bash
# One-line install:
#
#   curl -fsSL https://raw.githubusercontent.com/jackiectl/tailbell/main/packaging/get-tailbell.sh | bash
#
# You are about to pipe a script from the internet into a shell, which is worth
# a moment's thought every time. This one clones the repository into ~/tailbell
# and runs its installer, and you can do both by hand instead:
#
#   git clone https://github.com/jackiectl/tailbell.git ~/tailbell
#   bash ~/tailbell/install.sh
#
# That is the supported path and the one the tests exercise. This file exists
# because every comparable tool has a one-liner and its absence reads as
# immaturity — not because piping to a shell is a good habit.
set -euo pipefail

REPO_URL="${TAILBELL_REPO:-https://github.com/jackiectl/tailbell.git}"
DEST="${TAILBELL_DIR:-$HOME/tailbell}"
BRANCH="${TAILBELL_BRANCH:-main}"

command -v git >/dev/null 2>&1 || { echo "需要 git"; exit 1; }

if [ -d "$DEST/.git" ]; then
  echo "==> 已存在 $DEST,更新"
  git -C "$DEST" fetch --quiet origin "$BRANCH"
  git -C "$DEST" checkout --quiet "$BRANCH"
  git -C "$DEST" merge --quiet --ff-only "origin/$BRANCH"
else
  echo "==> 克隆到 $DEST"
  git clone --quiet --branch "$BRANCH" "$REPO_URL" "$DEST"
fi

# Which side this machine is decides which installer runs, and the machine
# already knows: the workstation is the one with a screen.
if [ "$(uname)" = "Darwin" ]; then
  bash "$DEST/mac/install.sh"
else
  bash "$DEST/install.sh"
fi
