#!/bin/sh
set -eu
if [ "$#" -ne 1 ]; then echo "usage: $0 <stable-tag>" >&2; exit 2; fi
target=$1
branch=$(git symbolic-ref --quiet --short HEAD) || { echo "detached HEAD; create a maintenance branch first" >&2; exit 2; }
if ! git diff --quiet || ! git diff --cached --quiet; then echo "working tree is dirty; commit or stash changes first" >&2; exit 2; fi
git rev-parse --verify "$target^{commit}" >/dev/null || { echo "target tag is unavailable: $target" >&2; exit 2; }
echo "Rebasing $branch onto $target"
git rebase "$target" || { echo "rebase stopped; resolve, git add, git rebase --continue (or --abort)" >&2; exit 1; }

