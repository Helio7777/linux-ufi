#!/bin/sh
set -eu
base=$(git merge-base HEAD upstream/linux-6.12.y)
out=${1:-patches}
rm -rf "$out"
mkdir -p "$out"
git format-patch --output-directory "$out" "$base..HEAD"
printf "%s\n" "Exported $(git rev-list --count "$base..HEAD") commits to $out"

