#!/usr/bin/env bash
# Rebuild and redeploy exactly one commit, from a clean copy, so nothing uncommitted in the working tree ships.
# Use it after setting a Pages secret (secrets take effect only on the next deployment), for a rollback,
# or whenever the working tree holds unfinished work.
#
#   clean-redeploy.sh <commit> --project <pages-project> [--branch main] [--build "npm run build"]
#                     [--out dist] [--scratch <dir>] [--dry-run]
#
# Run from inside the repository. --dry-run archives and builds but does not deploy.
# The scratch copy is left in place (nothing is deleted); its path is printed.
set -euo pipefail

usage() { sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
[[ $# -ge 1 ]] || usage
COMMIT="$1"; shift
PROJECT="" BRANCH="main" BUILD="npm run build" OUT="dist" SCRATCH="" DRY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="$2"; shift 2;;
    --branch) BRANCH="$2"; shift 2;;
    --build) BUILD="$2"; shift 2;;
    --out) OUT="$2"; shift 2;;
    --scratch) SCRATCH="$2"; shift 2;;
    --dry-run) DRY=1; shift;;
    *) usage;;
  esac
done
[[ -n "$PROJECT" || $DRY -eq 1 ]] || { echo "--project is required (or use --dry-run)"; exit 2; }

ROOT="$(git rev-parse --show-toplevel)"
SHA="$(git -C "$ROOT" rev-parse --verify "${COMMIT}^{commit}")"
SHORT="${SHA:0:9}"
if [[ -z "$SCRATCH" ]]; then SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/clean-redeploy-${SHORT}-XXXX")"; fi
mkdir -p "$SCRATCH"
[[ -z "$(ls -A "$SCRATCH")" ]] || { echo "scratch folder is not empty: $SCRATCH"; exit 2; }

echo "commit   $SHA ($(git -C "$ROOT" log -1 --format=%s "$SHA" | cut -c1-80))"
echo "scratch  $SCRATCH"
git -C "$ROOT" archive --format=tar "$SHA" | tar -x -C "$SCRATCH"

# Reuse the project's installed dependencies rather than reinstalling.
if [[ -d "$ROOT/node_modules" && ! -e "$SCRATCH/node_modules" ]]; then
  ln -s "$ROOT/node_modules" "$SCRATCH/node_modules"
  echo "deps     linked $ROOT/node_modules"
fi
# Files outside Git that the build may need (gitignored large assets) are NOT copied: say so if the build fails.

echo "build    $BUILD"
( cd "$SCRATCH" && eval "$BUILD" )
[[ -d "$SCRATCH/$OUT" ]] || { echo "build produced no $OUT/"; exit 1; }
echo "built    $(du -sh "$SCRATCH/$OUT" | cut -f1) in $SCRATCH/$OUT"

if [[ $DRY -eq 1 ]]; then
  echo "dry run: not deploying. To deploy this build:"
  echo "  wrangler pages deploy \"$SCRATCH/$OUT\" --project-name ${PROJECT:-<project>} --branch $BRANCH --commit-hash $SHA"
  exit 0
fi

# Deploy from the scratch copy; wrangler reads the project's wrangler.toml there (it came with the commit).
( cd "$SCRATCH" && wrangler pages deploy "$OUT" --project-name "$PROJECT" --branch "$BRANCH" \
    --commit-hash "$SHA" --commit-message "Redeploy of $SHORT" --commit-dirty=false )
echo "done. Scratch copy kept at $SCRATCH (remove it yourself when no longer needed)."
