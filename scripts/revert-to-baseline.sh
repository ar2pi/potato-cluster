#!/bin/bash
# Restore $BRANCH's tree to a known baseline commit via a merge commit, no force-push.
#
# Equivalent to:
#   git checkout -b baseline-side $TARGET_COMMIT
#   git checkout $BRANCH && git merge baseline-side   # but taking baseline-side's tree
#
# Since $TARGET_COMMIT is already an ancestor of $BRANCH, a normal merge is a no-op
# ("already up to date"). We build the merge commit by hand with commit-tree so the
# result is a descendant of current $BRANCH (fast-forward push) whose tree matches
# the baseline.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_COMMIT="65156eb294f55c274a1d079e39a3d76ffb9a1602"
BRANCH="${BRANCH:-main}"

cd "$REPO_DIR"

git fetch --quiet origin "$BRANCH"
git checkout "$BRANCH"
git pull --ff-only --quiet origin "$BRANCH"

CURRENT_TREE="$(git rev-parse "HEAD^{tree}")"
TARGET_TREE="$(git rev-parse "${TARGET_COMMIT}^{tree}")"

if [ "$CURRENT_TREE" = "$TARGET_TREE" ]; then
  exit 0
fi

SHORT="$(git rev-parse --short "$TARGET_COMMIT")"
echo "Drift detected on $BRANCH — merging baseline $SHORT to restore tree"

# tree    = baseline tree (this is what restores the files)
# parent1 = current HEAD (so the new commit is a fast-forward of $BRANCH)
# parent2 = baseline commit (records the merge in history)
MERGE_COMMIT="$(git commit-tree "$TARGET_TREE" \
  -p HEAD \
  -p "$TARGET_COMMIT" \
  -m "revert: merge baseline $SHORT to restore tree on $BRANCH")"

git update-ref "refs/heads/$BRANCH" "$MERGE_COMMIT" HEAD
git checkout --quiet "$BRANCH"
git push origin "$BRANCH"
