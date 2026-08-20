#!/usr/bin/env bash
# One-line install:
#
#   curl -fsSL https://raw.githubusercontent.com/jackiectl2/tailbell/main/packaging/get-tailbell.sh | bash
#
# You are about to pipe a script from the internet into a shell, which is worth
# a moment's thought every time. This one clones the repository into ~/tailbell
# and runs its installer, and you can do both by hand instead:
#
#   git clone https://github.com/jackiectl2/tailbell.git ~/tailbell
#   bash ~/tailbell/install.sh
#
# That is the supported path and the one the tests exercise. This file exists
# because every comparable tool has a one-liner and its absence reads as
# immaturity — not because piping to a shell is a good habit.
set -euo pipefail

REPO_URL="${TAILBELL_REPO:-https://github.com/jackiectl2/tailbell.git}"
DEST="${TAILBELL_DIR:-$HOME/tailbell}"
BRANCH="${TAILBELL_BRANCH:-main}"

command -v git >/dev/null 2>&1 || { echo "需要 git"; exit 1; }

# Clone then check out, rather than `clone --branch`: that form takes only a
# branch or a tag, so pinning to a commit — which is what you want when you are
# reproducing somebody's setup, and what CI has when it checks out a PR — fails.
if [ -d "$DEST/.git" ]; then
  echo "==> 已存在 $DEST,更新"
  git -C "$DEST" fetch --quiet origin
  git -C "$DEST" checkout --quiet "$BRANCH"
  git -C "$DEST" merge --quiet --ff-only "origin/$BRANCH" 2>/dev/null || true
else
  echo "==> 克隆到 $DEST"
  git clone --quiet "$REPO_URL" "$DEST"
  git -C "$DEST" checkout --quiet "$BRANCH"
fi

# Which side this machine is decides which installer runs, and the machine
# already knows: the workstation is the one with a screen.
if [ "$(uname)" = "Darwin" ]; then
  bash "$DEST/mac/install.sh"
else
  bash "$DEST/install.sh"
fi
