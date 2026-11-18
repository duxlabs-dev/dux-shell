#!/usr/bin/env bash
# run.sh BINARY SHELL_DIR OUT_DIR [--stock COLORS_JSON] [dms matugen generate flags...]
#
# Runs `dms matugen generate` so that nothing reaches the live session:
#   - its own PID namespace, so terminal reload signals (SIGUSR1/2 to kitty/ghostty)
#     find no real processes;
#   - D-Bus pointed at a missing socket, so gsettings / fcitx5 calls fail harmlessly;
#   - HOME and every XDG dir inside OUT_DIR, where all template outputs land.
# OUT_DIR must be new, empty, or an earlier run.sh output; it is wiped first.
# Exit status is dms's. Outputs: OUT_DIR/{config,data,cache,state}; log on stdout/stderr.
set -euo pipefail

usage() { sed -n '2,10p' "$0" >&2; exit 2; }
[[ $# -ge 3 ]] || usage
bin=$(realpath -e "$1") shell=$(realpath -e "$2") out=$(realpath -m "$3")
shift 3

# OUT_DIR is wiped, so only a directory this script made (it leaves a marker) or an empty/new one.
marker="$out/.dms-sandbox"
if [[ -e "$out" && ! -f "$marker" ]] && [[ -n "$(ls -A "$out" 2>/dev/null)" || ! -d "$out" ]]; then
  echo "run.sh: refusing to wipe $out: not empty and not made by run.sh" >&2; exit 2
fi
[[ -f "$shell/shell.qml" || -d "$shell/matugen" ]] || { echo "run.sh: $shell is not a quickshell dir" >&2; exit 2; }

extra=()
if [[ ${1:-} == --stock ]]; then
  [[ $# -ge 2 ]] || usage
  extra+=(--stock-colors "$(cat "$2")")
  shift 2
fi

rm -rf "$out"
mkdir -p "$out"/{home,config,data,cache,state}
: > "$marker"

exec unshare --map-current-user --pid --fork --mount-proc \
  env -i PATH="$PATH" HOME="$out/home" \
  XDG_CONFIG_HOME="$out/config" XDG_DATA_HOME="$out/data" XDG_CACHE_HOME="$out/cache" \
  XDG_RUNTIME_DIR="$out/home" DBUS_SESSION_BUS_ADDRESS=unix:path=/nonexistent \
  "$bin" matugen generate --state-dir "$out/state" --shell-dir "$shell" --config-dir "$out/config" \
  "${extra[@]}" "$@"
