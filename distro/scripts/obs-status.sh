#!/usr/bin/env bash
# Unified OBS status checker for dms packages
# Checks all platforms (Debian, OpenSUSE) and architectures (x86_64, aarch64)
# Only pulls logs if build failed
# Usage: ./distro/scripts/obs-status.sh [package-name]
#
# Examples:
#   ./distro/scripts/obs-status.sh              # Check all packages
#   ./distro/scripts/obs-status.sh dms          # Check specific package
#   OBS_BASE_PROJECT=home:duxlabs-dev ./distro/scripts/obs-status.sh   # Dux Labs projects (legacy is the default)

OBS_BASE_PROJECT="${OBS_BASE_PROJECT:-home:AvengeMedia}"
OBS_BASE="$HOME/.cache/osc-checkouts"

ALL_PACKAGES=(dms dms-git)

REPOS=("Debian_13" "openSUSE_Tumbleweed" "16.0")
ARCHES=("x86_64" "aarch64")

if [[ -n "$1" ]]; then
    PACKAGES=("$1")
else
    PACKAGES=("${ALL_PACKAGES[@]}")
fi

# Ensure cache directory exists
if [[ ! -d "$OBS_BASE" ]]; then
    echo "Creating OBS cache directory: $OBS_BASE"
    mkdir -p "$OBS_BASE"
fi

cd "$OBS_BASE" || {
    echo "ERROR: Failed to access OBS cache directory: $OBS_BASE"
    exit 1
}

for pkg in "${PACKAGES[@]}"; do
    case "$pkg" in
    dms)
        PROJECT="$OBS_BASE_PROJECT:dms"
        ;;
    dms-git)
        PROJECT="$OBS_BASE_PROJECT:dms-git"
        ;;
    *)
        echo "Error: Unknown package '$pkg'"
        continue
        ;;
    esac
    (

        echo "=========================================="
        echo "=== $pkg ==="
        echo "=========================================="

        # Checkout if needed
        if [[ ! -d "$PROJECT/$pkg" ]]; then
            osc co "$PROJECT/$pkg" 2>&1 | tail -1
        fi

        cd "$PROJECT/$pkg"

        ALL_RESULTS=$(osc results 2>&1)

        # Check each repository and architecture
        FAILED_BUILDS=()
        for repo in "${REPOS[@]}"; do
            for arch in "${ARCHES[@]}"; do
                STATUS=$(echo "$ALL_RESULTS" | grep "$repo.*$arch" | awk '{print $NF}' | head -1)

                if [[ -n "$STATUS" ]]; then
                    # Color code status
                    case "$STATUS" in
                    succeeded)
                        COLOR="\033[0;32m" # Green
                        SYMBOL="✅"
                        ;;
                    failed|broken|broken*)
                        COLOR="\033[0;31m" # Red
                        SYMBOL="❌"
                        FAILED_BUILDS+=("$repo $arch")
                        ;;
                    blocked)
                        COLOR="\033[0;33m" # Yellow
                        SYMBOL="⏸️"
                        ;;
                    unresolvable)
                        COLOR="\033[0;33m" # Yellow
                        SYMBOL="⚠️"
                        ;;
                    *)
                        COLOR="\033[0;37m" # White
                        SYMBOL="⏳"
                        ;;
                    esac
                    echo -e "  $SYMBOL $repo $arch: ${COLOR}$STATUS\033[0m"
                fi
            done
        done

        # Pull logs for failed builds
        if [[ ${#FAILED_BUILDS[@]} -gt 0 ]]; then
            echo ""
            echo "  📋 Fetching logs for failed builds..."
            for build in "${FAILED_BUILDS[@]}"; do
                read -r repo arch <<<"$build"
                echo ""
                echo "  ────────────────────────────────────────────"
                echo "  Build log: $repo $arch"
                echo "  ────────────────────────────────────────────"
                osc remotebuildlog "$PROJECT" "$pkg" "$repo" "$arch" 2>&1 | tail -100
            done
        fi

        echo ""
    )
done

echo "=========================================="
echo "Status check complete!"
