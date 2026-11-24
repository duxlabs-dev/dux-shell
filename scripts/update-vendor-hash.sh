#!/usr/bin/env bash
set -euo pipefail

command -v nix >/dev/null 2>&1 || { printf '%s\n' "nix is required to update the vendorHash" >&2; exit 1; }

# a cached vendor derivation with the old hash passes the plain build without checking go.sum,
# so a passing build is verified with --rebuild (which refuses to run on a never-built derivation)
if output=$(nix build --no-link .#dms-shell.goModules 2>&1) \
    && output=$(nix build --no-link --rebuild .#dms-shell.goModules 2>&1); then
    exit 0
fi

new_hash=$(grep -m1 -oP 'got:\s+\K\S+' <<<"$output" || true)
[ -n "$new_hash" ] || { printf '%s\n' "Could not extract new vendorHash" >&2; printf '%s\n' "$output" >&2; exit 1; }

current_hash=$(grep -m1 -oP 'vendorHash = "\K[^"]+' flake.nix)
[ "$current_hash" = "$new_hash" ] && exit 0

sed -i "s|vendorHash = \"$current_hash\"|vendorHash = \"$new_hash\"|" flake.nix
if [ "${1:-}" = "--stage" ]; then
    git add flake.nix
fi
nix build --no-link .#dms-shell.goModules
