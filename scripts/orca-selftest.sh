#!/bin/bash
# Selftest do orca-setup (CI): worktree temp + compose real + teardown.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WT="$(mktemp -d)"
BRANCH="selftest/orca-$$"
cleanup() {
  if [ -d "$WT" ]; then
    (cd "$WT" && bash scripts/orca-setup.sh --teardown) 2>/dev/null || true
  fi
  git -C "$ROOT" worktree remove "$WT" --force 2>/dev/null || true
  git -C "$ROOT" branch -D "$BRANCH" >/dev/null 2>&1 || true
  rm -f "$ROOT/.git/orca-slots.tsv" "$ROOT/.git/orca-slots.lock" 2>/dev/null || true
}
trap cleanup EXIT

bash -n "$ROOT/scripts/orca-setup.sh"

echo "== slot 0 =="
(cd "$ROOT" && bash scripts/orca-setup.sh) | tee /tmp/zsh-orca-primary.txt
grep -q 'slot 0' /tmp/zsh-orca-primary.txt

echo "== worktree setup =="
git -C "$ROOT" worktree add -b "$BRANCH" "$WT" HEAD
cp "$ROOT/scripts/orca-setup.sh" "$WT/scripts/"
cp "$ROOT/docker/Dockerfile" "$ROOT/docker/compose.yml" "$WT/docker/"
(cd "$WT" && bash scripts/orca-setup.sh) | tee /tmp/zsh-orca-setup.txt
grep -q 'slot 1' /tmp/zsh-orca-setup.txt
test -f "$WT/.orca/env"
grep -q '^ORCA_SLOT=1$' "$WT/.orca/env"

echo "== status =="
(cd "$ROOT" && bash scripts/orca-setup.sh --status) | grep -q 'Slot 1'

echo "== teardown =="
(cd "$WT" && bash scripts/orca-setup.sh --teardown) | tee /tmp/zsh-orca-td.txt
grep -q 'liberado' /tmp/zsh-orca-td.txt

echo "orca-selftest OK"
