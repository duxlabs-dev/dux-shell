#!/usr/bin/env bash
# compare.sh REPO REF WORK_DIR [run.sh args after OUT_DIR...]
#
# Builds dms from git REF (via git archive, the clone is not touched) and from REPO's working
# tree, generates with identical args in the sandbox, and reports differences:
#   ref         = REF binary + REF shell       (baseline)
#   branch      = working-tree binary + shell
#   cross       = REF binary + working-tree shell  (a shell newer than the binary is supported)
# Example: compare.sh . master /tmp/cmp --stock bru.json --kind hex --value '#dbb32d' --mode dark
set -euo pipefail

[[ $# -ge 3 ]] || { sed -n '2,10p' "$0" >&2; exit 2; }
repo=$(realpath -e "$1") ref=$2 work=$(realpath -m "$3")
shift 3
here=$(dirname "$(realpath "$0")")
mkdir -p "$work"

sha=$(git -C "$repo" rev-parse --short "$ref")
refdir="$work/ref-$sha"
if [[ ! -x "$refdir/dms" ]]; then
  rm -rf "$refdir" && mkdir -p "$refdir/src"
  git -C "$repo" archive "$sha" core quickshell | tar -x -C "$refdir/src"
  (cd "$refdir/src/core" && go build -o "$refdir/dms" ./cmd/dms)
fi
(cd "$repo/core" && go build -o "$work/dms-branch" ./cmd/dms)

# run.sh's first extra arg may be --stock FILE; make the path absolute before cd changes.
args=("$@")
if [[ ${args[0]:-} == --stock ]]; then args[1]=$(realpath -e "${args[1]}"); fi

status=0
run() { local name=$1 bin=$2 shell=$3
  if "$here/run.sh" "$bin" "$shell" "$work/out-$name" "${args[@]}" > "$work/$name.log" 2>&1; then
    echo "$name: generate ok"
  else
    echo "$name: generate FAILED (see $work/$name.log)"; status=1
  fi; }
run ref "$refdir/dms" "$refdir/src/quickshell"
run branch "$work/dms-branch" "$repo/quickshell"
run cross "$refdir/dms" "$repo/quickshell"

for name in branch cross; do
  echo "--- ref vs $name (app configs)"
  if diff -rq "$work/out-ref" "$work/out-$name" -x matugen.lock -x home -x dms-colors.json; then echo "identical"; else status=1; fi
done

echo "--- dms-colors.json"
python3 -I - "$work/out-ref/state/dms-colors.json" "$work/out-branch/state/dms-colors.json" <<'PY'
import json, sys
try:
    ref, br = (json.load(open(p)) for p in sys.argv[1:3])
except OSError as e:
    sys.exit(f"missing: {e.filename}")
changed = [k for k in ref if ref[k] != br.get(k)]
print("sections changed:", changed or "none", "| added:", sorted(set(br) - set(ref)) or "none")
PY
exit $status
