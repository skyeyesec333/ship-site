#!/usr/bin/env bash
# Check a build folder against Cloudflare Pages' limits before deploying
# (https://developers.cloudflare.com/pages/platform/limits/):
#   - a single file over 25 MiB is refused (and one over 20 MiB is close);
#   - a site may hold 20,000 files on the Free plan, 100,000 on paid plans;
#   - a _headers file may hold 100 rules.
# Also lists binary files Cloudflare will serve uncompressed (application/octet-stream types) above 512 KiB.
#
#   check-sizes.sh [dist]
#
# Env: PAGES_PLAN=free|paid (default free), PAGES_MAX_FILES=<n> overrides the plan's file limit (for testing).
set -euo pipefail
DIR="${1:-dist}"
[[ -d "$DIR" ]] || { echo "no folder $DIR"; exit 2; }
LIMIT=$((25 * 1024 * 1024)); NEAR=$((20 * 1024 * 1024)); BIG=$((512 * 1024))
case "${PAGES_PLAN:-free}" in
  free) MAXF=20000;; paid) MAXF=100000;;
  *) echo "PAGES_PLAN must be free or paid"; exit 2;;
esac
MAXF="${PAGES_MAX_FILES:-$MAXF}"
[[ "$MAXF" =~ ^[0-9]+$ ]] || { echo "PAGES_MAX_FILES must be a whole number"; exit 2; }
fail=0
count=0
while IFS= read -r -d '' f; do
  count=$((count + 1))
  s=$(wc -c < "$f" | tr -d ' ')   # portable: no BSD/GNU stat differences
  if (( s > LIMIT )); then echo "TOO BIG  $(( s / 1048576 )) MiB  $f  (Pages limit is 25 MiB: move it to R2)"; fail=1
  elif (( s > NEAR )); then echo "near     $(( s / 1048576 )) MiB  $f"
  fi
  case "$f" in
    *.bin|*.vrm|*.take|*.dat|*.data) ;;   # types Cloudflare serves as octet-stream and does not compress
    *) continue;;
  esac
  if (( s > BIG )); then echo "raw      $(( s / 1024 )) KiB  $f  (served as octet-stream, uncompressed: consider gzipping at build)"; fi
done < <(find "$DIR" -type f -print0)

if (( count > MAXF )); then echo "TOO MANY $count files (limit $MAXF on the ${PAGES_PLAN:-free} plan)"; fail=1
elif (( count * 10 > MAXF * 9 )); then echo "near     $count files (limit $MAXF on the ${PAGES_PLAN:-free} plan)"
else echo "files    $count (limit $MAXF)"
fi

# _headers: count rules (a path line not indented, not a comment) in the build's copy, else the source one.
for h in "$DIR/_headers" public/_headers; do
  [[ -f "$h" ]] || continue
  rules=$(grep -cE '^[^[:space:]#]' "$h" || true)
  if (( rules > 100 )); then echo "TOO MANY $rules rules in $h (Pages reads at most 100)"; fail=1
  else echo "headers  $rules rules in $h (limit 100)"; fi
  break
done

(( fail == 0 )) && echo "limits ok"
exit $fail
