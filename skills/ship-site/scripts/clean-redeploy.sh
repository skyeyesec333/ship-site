#!/usr/bin/env bash
# Rebuild and redeploy exactly one commit, from a clean copy, so nothing uncommitted in the working tree ships.
# Use it after setting a Pages secret (secrets take effect only on the next deployment), for a rollback,
# or whenever the working tree holds unfinished work.
#
#   clean-redeploy.sh <commit> --project <pages-project> [--branch <production-branch>] [--build "npm run build"]
#                     [--out dist] [--scratch <dir>] [--dry-run]
#
# Run from inside the repository. --dry-run archives and builds but does not deploy.
# --project, --branch, --build and --out default to "project", "branch", "build" and "out" in ship.config.json
# at the repository root. The branch must be the one Pages treats as production, or the deploy is a preview.
# The scratch copy is left in place (nothing is deleted); its path is printed.
set -euo pipefail

usage() { sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
[[ $# -ge 1 ]] || usage
COMMIT="$1"; shift
ROOT="$(git rev-parse --show-toplevel)"
# Defaults from ship.config.json, if present.
cfg() { [[ -f "$ROOT/ship.config.json" ]] && node -e 'const c=require(process.argv[1]); const v=c[process.argv[2]]; if (typeof v==="string") process.stdout.write(v)' "$ROOT/ship.config.json" "$1" 2>/dev/null || true; }
PROJECT="$(cfg project)" BRANCH="$(cfg branch)" BUILD="$(cfg build)" OUT="$(cfg out)" SCRATCH="" DRY=0
BUILD="${BUILD:-npm run build}" OUT="${OUT:-dist}"
BRANCH_FROM="ship.config.json"; [[ -n "$BRANCH" ]] || BRANCH_FROM=""
BUILD_FROM=""; [[ -n "$(cfg build)" ]] && BUILD_FROM="ship.config.json"
need() { [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || { echo "$1 needs a value"; exit 2; }; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) need "$@"; PROJECT="$2"; shift 2;;
    --branch) need "$@"; BRANCH="$2"; BRANCH_FROM="--branch"; shift 2;;
    --build) need "$@"; BUILD="$2"; BUILD_FROM="--build"; shift 2;;
    --out) need "$@"; OUT="$2"; shift 2;;
    --scratch) need "$@"; SCRATCH="$2"; shift 2;;
    --dry-run) DRY=1; shift;;
    *) echo "unknown option: $1"; usage;;
  esac
done
[[ -n "$PROJECT" || $DRY -eq 1 ]] || { echo "--project is required (or set \"project\" in ship.config.json, or use --dry-run)"; exit 2; }
# Values may come from ship.config.json in the repo: check their shape before they reach wrangler or a path.
[[ -z "$PROJECT" || "$PROJECT" =~ ^[a-z0-9][a-z0-9-]{0,62}$ ]] || { echo "project name '$PROJECT' is not a Pages project name (a-z, 0-9, -)"; exit 2; }
[[ -z "$BRANCH" ]] || git check-ref-format --branch "$BRANCH" >/dev/null 2>&1 || { echo "branch '$BRANCH' is not a valid branch name"; exit 2; }
[[ "$OUT" != /* && "$OUT" != *..* && "$OUT" =~ ^[A-Za-z0-9._][A-Za-z0-9._/-]*$ ]] || { echo "output folder '$OUT' must be a plain relative path inside the repo"; exit 2; }
if [[ -z "$BRANCH" ]]; then
  [[ $DRY -eq 1 ]] || { echo "--branch is required: the branch Pages treats as production (or set \"branch\" in ship.config.json). A wrong one deploys a preview."; exit 2; }
  BRANCH="<production-branch>"
fi

# git archive copies only tracked files. Refuse what it cannot reproduce; warn about what it leaves out.
if [[ -f "$ROOT/.gitmodules" ]]; then
  echo "refusing: this repo uses submodules, which git archive does not include. Deploy from a full checkout instead."; exit 2
fi
if git -C "$ROOT" ls-files -z | xargs -0 git -C "$ROOT" check-attr filter -- 2>/dev/null | grep -q ': filter: lfs$'; then
  echo "refusing: this repo stores files in Git LFS, which git archive writes as pointer files. Deploy from a full checkout instead."; exit 2
fi
envs=""
for e in "$ROOT"/.env "$ROOT"/.env.*; do
  [[ -f "$e" ]] || continue
  case "$e" in *.example|*.sample) continue;; esac
  git -C "$ROOT" ls-files --error-unmatch "${e#"$ROOT"/}" >/dev/null 2>&1 && continue   # tracked: it is in the archive
  envs+="${e#"$ROOT"/} "
done
if [[ -n "$envs" ]]; then
  echo "warning: ${envs}is not in the commit, so this build will not see it. If the build reads"
  echo "         VITE_* (or other) values from it, the result will differ from a normal build."
fi
SHA="$(git -C "$ROOT" rev-parse --verify "${COMMIT}^{commit}")"
SHORT="${SHA:0:9}"
if [[ -z "$SCRATCH" ]]; then SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/clean-redeploy-${SHORT}-XXXX")"; fi
mkdir -p "$SCRATCH"
[[ -z "$(ls -A "$SCRATCH")" ]] || { echo "scratch folder is not empty: $SCRATCH"; exit 2; }

echo "commit   $SHA ($(git -C "$ROOT" log -1 --format=%s "$SHA" | cut -c1-80))"
echo "branch   $BRANCH${BRANCH_FROM:+ (from $BRANCH_FROM)}"
echo "scratch  $SCRATCH"
git -C "$ROOT" archive --format=tar "$SHA" | tar -x -C "$SCRATCH"

# Reuse the project's installed dependencies rather than reinstalling.
if [[ -d "$ROOT/node_modules" && ! -e "$SCRATCH/node_modules" ]]; then
  ln -s "$ROOT/node_modules" "$SCRATCH/node_modules"
  echo "deps     linked $ROOT/node_modules"
fi
# Files outside Git that the build may need (gitignored large assets) are NOT copied: say so if the build fails.

# The build command runs as written, like an npm script: ship.config.json is part of the project and trusted
# the same way package.json is. It is printed first, so the deploy log shows exactly what ran.
echo "build    $BUILD${BUILD_FROM:+ (from $BUILD_FROM)}"
( cd "$SCRATCH" && eval "$BUILD" )
[[ -d "$SCRATCH/$OUT" ]] || { echo "build produced no $OUT/"; exit 1; }
echo "built    $(du -sh "$SCRATCH/$OUT" | cut -f1) in $SCRATCH/$OUT"

if [[ $DRY -eq 1 ]]; then
  echo "dry run: not deploying. To deploy this build:"
  echo "  wrangler pages deploy \"$SCRATCH/$OUT\" --project-name ${PROJECT:-<project>} --branch $BRANCH --commit-hash $SHA"
  exit 0
fi

# Deploy from the scratch copy; wrangler reads the project's wrangler.toml there (it came with the commit).
( cd "$SCRATCH" && wrangler pages deploy "./$OUT" --project-name "$PROJECT" --branch "$BRANCH" \
    --commit-hash "$SHA" --commit-message "Redeploy of $SHORT" --commit-dirty=false )
echo "done. Scratch copy kept at $SCRATCH (remove it yourself when no longer needed)."
