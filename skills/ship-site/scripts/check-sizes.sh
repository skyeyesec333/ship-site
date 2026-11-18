#!/usr/bin/env bash
# List files in a build folder that Cloudflare Pages will refuse (over 25 MiB) or that come close (over 20 MiB),
# and binary files Cloudflare will serve uncompressed (application/octet-stream types) above 512 KiB.
#
#   check-sizes.sh [dist]
set -euo pipefail
DIR="${1:-dist}"
[[ -d "$DIR" ]] || { echo "no folder $DIR"; exit 2; }
LIMIT=$((25 * 1024 * 1024)); NEAR=$((20 * 1024 * 1024)); BIG=$((512 * 1024))
fail=0
size() { if stat -f %z "$1" >/dev/null 2>&1; then stat -f %z "$1"; else stat -c %s "$1"; fi; }
while IFS= read -r -d '' f; do
  s=$(size "$f")
  if (( s > LIMIT )); then echo "TOO BIG  $(( s / 1048576 )) MiB  $f  (Pages limit is 25 MiB: move it to R2)"; fail=1
  elif (( s > NEAR )); then echo "near     $(( s / 1048576 )) MiB  $f"
  fi
  case "$f" in
    *.bin|*.vrm|*.glb|*.ktx2|*.take|*.dat|*.data|*.wasm) ;;
    *) continue;;
  esac
  case "$f" in *.glb|*.ktx2|*.wasm) continue;; esac   # Cloudflare knows these types (or they are already compressed)
  if (( s > BIG )); then echo "raw      $(( s / 1024 )) KiB  $f  (served as octet-stream, uncompressed: consider gzipping at build)"; fi
done < <(find "$DIR" -type f -print0)
(( fail == 0 )) && echo "sizes ok"
exit $fail
