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
TARGET_COMMIT="cc0c4e6650855a0a6bf25ba20a359cd32848c30b"
BRANCH="${BRANCH:-main}"

cd "$REPO_DIR"

git fetch --quiet origin "$BRANCH"
git checkout "$BRANCH"
git pull --ff-only --quiet origin "$BRANCH"

# Drift check ignores scripts/ — we don't want to revert chaos automation itself.
if git diff --quiet "$TARGET_COMMIT" HEAD -- . ':(exclude)scripts'; then
  exit 0
fi

SHORT="$(git rev-parse --short "$TARGET_COMMIT")"
TARGET_TREE="$(git rev-parse "${TARGET_COMMIT}^{tree}")"
echo "Drift detected on $BRANCH (outside scripts/) — merging baseline $SHORT to restore tree"

# Build a tree that = baseline tree, except scripts/ is taken from current HEAD.
# Done by reading the baseline into a scratch index, dropping scripts/, then
# overlaying HEAD's scripts/ at that prefix.
TMP_INDEX="$(mktemp)"
trap 'rm -f "$TMP_INDEX"' EXIT
GIT_INDEX_FILE="$TMP_INDEX" git read-tree "$TARGET_TREE"
GIT_INDEX_FILE="$TMP_INDEX" git rm --cached -r --quiet --ignore-unmatch -- scripts
GIT_INDEX_FILE="$TMP_INDEX" git read-tree --prefix=scripts/ HEAD:scripts
NEW_TREE="$(GIT_INDEX_FILE="$TMP_INDEX" git write-tree)"

# tree    = baseline tree with current scripts/ preserved
# parent1 = current HEAD (so the new commit is a fast-forward of $BRANCH)
# parent2 = baseline commit (records the merge in history)
MERGE_COMMIT="$(git commit-tree "$NEW_TREE" \
  -p HEAD \
  -p "$TARGET_COMMIT" \
  -m "revert: merge baseline $SHORT to restore tree on $BRANCH (scripts/ preserved)")"

git update-ref "refs/heads/$BRANCH" "$MERGE_COMMIT" HEAD
git checkout --quiet "$BRANCH"
git push origin "$BRANCH"

git reset HEAD^
git pull
