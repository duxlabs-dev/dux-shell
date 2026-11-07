#!/bin/bash
# Unified OBS upload script for dms packages
# Handles Debian and OpenSUSE builds for both x86_64 and aarch64
# Usage: ./distro/scripts/obs-upload.sh [distro] <package-name> [commit-message|rebuild-number]
#
# Examples:
#   ./distro/scripts/obs-upload.sh dms "Update to v1.0.2"
#   ./distro/scripts/obs-upload.sh debian dms
#   ./distro/scripts/obs-upload.sh opensuse dms-git
#   ./distro/scripts/obs-upload.sh debian dms-git 2    # Rebuild with db2 suffix
#   ./distro/scripts/obs-upload.sh dms-git --rebuild=2 # Rebuild with db2 suffix (flag syntax)
#   OBS_BASE_PROJECT=home:duxlabs-dev ./distro/scripts/obs-upload.sh dms   # Dux Labs projects (legacy is the default)

set -e

UPLOAD_DEBIAN=true
UPLOAD_OPENSUSE=true
PACKAGE=""
MESSAGE=""
REBUILD_RELEASE="${REBUILD_RELEASE:-}"
POSITIONAL_ARGS=()

for arg in "$@"; do
    case "$arg" in
    debian)
        UPLOAD_DEBIAN=true
        UPLOAD_OPENSUSE=false
        ;;
    opensuse)
        UPLOAD_DEBIAN=false
        UPLOAD_OPENSUSE=true
        ;;
    --rebuild=*)
        REBUILD_RELEASE="${arg#*=}"
        ;;
    -r|--rebuild)
        REBUILD_NEXT=true
        ;;
    *)
        if [[ -n "${REBUILD_NEXT:-}" ]]; then
            REBUILD_RELEASE="$arg"
            REBUILD_NEXT=false
        else
            POSITIONAL_ARGS+=("$arg")
        fi
        ;;
    esac
done

# Check if last positional argument is a number (rebuild release)
if [[ ${#POSITIONAL_ARGS[@]} -gt 0 ]]; then
    LAST_INDEX=$((${#POSITIONAL_ARGS[@]} - 1))
    LAST_ARG="${POSITIONAL_ARGS[$LAST_INDEX]}"
    if [[ "$LAST_ARG" =~ ^[0-9]+$ ]] && [[ -z "$REBUILD_RELEASE" ]]; then
        # Last argument is a number and no --rebuild flag was used
        # Use it as rebuild release and remove from positional args
        REBUILD_RELEASE="$LAST_ARG"
        POSITIONAL_ARGS=("${POSITIONAL_ARGS[@]:0:$LAST_INDEX}")
    fi
fi

# Assign remaining positional args to PACKAGE and MESSAGE
if [[ ${#POSITIONAL_ARGS[@]} -gt 0 ]]; then
    PACKAGE="${POSITIONAL_ARGS[0]}"
    if [[ ${#POSITIONAL_ARGS[@]} -gt 1 ]]; then
        MESSAGE="${POSITIONAL_ARGS[1]}"
    fi
fi

OBS_BASE_PROJECT="${OBS_BASE_PROJECT:-home:AvengeMedia}"
OBS_BASE="$HOME/.cache/osc-checkouts"
AVAILABLE_PACKAGES=(dms dms-git)

if [[ -z "$PACKAGE" ]]; then
    echo "Available packages:"
    echo ""
    echo "  1. dms         - Stable DMS"
    echo "  2. dms-git     - Nightly DMS"
    echo "  a. all"
    echo ""
    read -r -p "Select package (1-${#AVAILABLE_PACKAGES[@]}, a): " selection

    if [[ "$selection" == "a" ]] || [[ "$selection" == "all" ]]; then
        PACKAGE="all"
    elif [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 ]] && [[ "$selection" -le ${#AVAILABLE_PACKAGES[@]} ]]; then
        PACKAGE="${AVAILABLE_PACKAGES[$((selection - 1))]}"
    else
        echo "Error: Invalid selection"
        exit 1
    fi

fi

if [[ -z "$MESSAGE" ]]; then
    MESSAGE="Update packaging"
fi

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

if [[ ! -d "distro/debian" ]]; then
    echo "Error: Run this script from the repository root"
    exit 1
fi

# Retry wrapper for osc commands (mitigates SSL "Connection reset by peer" from api.opensuse.org)
osc_retry() {
    local max=3 attempt=1
    while true; do
        if osc "$@"; then return 0; fi
        ((attempt >= max)) && return 1
        echo "Retrying in $((5*attempt))s (attempt $attempt/$max)..."
        sleep $((5*attempt))
        ((attempt++))
    done
}

# Bundled Go for dms-git OBS builds (offline VM); filenames must match distro/opensuse/dms-git.spec Source1/2.
GO_TOOLCHAIN_CACHE="${GO_TOOLCHAIN_CACHE:-$HOME/.cache/dms-obs-go-toolchain}"

dms_git_go_toolchain_version() {
    grep -m1 '^go ' "$REPO_ROOT/core/go.mod" 2>/dev/null | awk '{print $2}'
}

ensure_dms_git_go_tarballs() {
    local dest="$1"
    local ver arch url cached
    ver="$(dms_git_go_toolchain_version)"
    if [[ -z "$ver" ]]; then
        echo "ERROR: Could not read Go version from core/go.mod"
        exit 1
    fi
    mkdir -p "$GO_TOOLCHAIN_CACHE/$ver"
    for arch in amd64 arm64; do
        url="https://go.dev/dl/go${ver}.linux-${arch}.tar.gz"
        cached="$GO_TOOLCHAIN_CACHE/$ver/go${ver}.linux-${arch}.tar.gz"
        if [[ ! -f "$cached" ]]; then
            echo "    Downloading Go ${ver} (${arch})…"
            if wget -q -O "${cached}.tmp" "$url" 2>/dev/null || curl -L -f -s -o "${cached}.tmp" "$url"; then
                mv "${cached}.tmp" "$cached"
            else
                rm -f "${cached}.tmp"
                echo "ERROR: Failed to download $url"
                exit 1
            fi
        fi
        cp -f "$cached" "$dest/go${ver}.linux-${arch}.tar.gz"
        echo "    ✓ Go toolchain ready: $dest/go${ver}.linux-${arch}.tar.gz"
    done
}

# Parameters:
#   $1 = PROJECT
#   $2 = PACKAGE
#   $3 = VERSION
#   $4 = CHECK_MODE - Exact version match, "commit" = check commit hash (default)
check_obs_version_exists() {
    local PROJECT="$1"
    local PACKAGE="$2"
    local VERSION="$3"
    local CHECK_MODE="${4:-commit}"
    local OBS_SPEC=""

    # Use osc api command (works in both local and CI environments)
    if command -v osc &> /dev/null; then
        OBS_SPEC=$(osc api "/source/$PROJECT/$PACKAGE/${PACKAGE}.spec" 2>/dev/null || echo "")
    else
        echo "⚠️  osc command not found, skipping version check"
        return 1
    fi

    # Check if we got valid spec content
    if [[ -n "$OBS_SPEC" && "$OBS_SPEC" != *"error"* && "$OBS_SPEC" == *"Version:"* ]]; then
        OBS_VERSION=$(echo "$OBS_SPEC" | grep "^Version:" | awk '{print $2}' | xargs)
        # Commit hash check for -git packages
        if [[ "$CHECK_MODE" == "commit" ]] && [[ "$PACKAGE" == *"-git" ]]; then
            OBS_COMMIT=$(echo "$OBS_VERSION" | grep -oP '\.([a-f0-9]{8})(db[0-9]+)?$' | grep -oP '[a-f0-9]{8}' || echo "")
            NEW_COMMIT=$(echo "$VERSION" | grep -oP '\.([a-f0-9]{8})(db[0-9]+)?$' | grep -oP '[a-f0-9]{8}' || echo "")

            if [[ -n "$OBS_COMMIT" && -n "$NEW_COMMIT" && "$OBS_COMMIT" == "$NEW_COMMIT" ]]; then
                echo "⚠️  Commit $NEW_COMMIT already exists in OBS (current version: $OBS_VERSION)"
                return 0
            fi
        fi

        # Exact version match check
        if [[ "$OBS_VERSION" == "$VERSION" ]]; then
            echo "⚠️  Version $VERSION already exists in OBS"
            return 0
        fi
    else
        # Empty/invalid response: expected on first upload (no spec on server yet), or actual API failure
        if [[ -z "$OBS_SPEC" ]]; then
            echo "  No existing spec on OBS (first upload?) - proceeding"
        else
            echo "⚠️  Could not fetch OBS spec (API may be unavailable), proceeding anyway"
        fi
        return 1
    fi
    return 1
}

update_debian_dms_service() {
    local service_path="$1"
    if [[ -z "$service_path" || ! -f "$service_path" ]]; then
        return 0
    fi
    if [[ -z "$CHANGELOG_VERSION" ]]; then
        return 0
    fi

    # Extract base version (e.g., 1.2.3 from 1.2.3db3 or 1.2.3-1)
    local base_version
    base_version=$(echo "$CHANGELOG_VERSION" | sed -E 's/^([0-9]+(\.[0-9]+)*).*/\1/')
    if [[ -z "$base_version" ]]; then
        return 0
    fi

    sed -i "s|/releases/download/v[0-9][^\"]*/dms-source\.tar\.gz|/releases/download/v${base_version}/dms-source.tar.gz|" "$service_path"
    sed -i "s|/releases/download/v[0-9][^\"]*/dms-distropkg-amd64\.gz|/releases/download/v${base_version}/dms-distropkg-amd64.gz|" "$service_path"
    sed -i "s|/releases/download/v[0-9][^\"]*/dms-distropkg-arm64\.gz|/releases/download/v${base_version}/dms-distropkg-arm64.gz|" "$service_path"
}

update_opensuse_git_spec() {
    local spec_path="$1"
    local go_ver
    if [[ -z "$spec_path" || ! -f "$spec_path" ]]; then
        return 0
    fi
    go_ver="$(dms_git_go_toolchain_version)"
    if [[ -n "$go_ver" ]] && grep -q '^%global go_toolchain_version' "$spec_path"; then
        sed -i "s/^%global go_toolchain_version .*/%global go_toolchain_version ${go_ver}/" "$spec_path"
        echo "    Synced %global go_toolchain_version to ${go_ver} (core/go.mod)"
    fi
    if [[ -n "$CHANGELOG_VERSION" ]]; then
        echo "    Updating OpenSUSE spec to version $CHANGELOG_VERSION"
        sed -i "s/^Version:.*/Version:        $CHANGELOG_VERSION/" "$spec_path"

        # Update changelog in spec file
        DATE_STR=$(date "+%a %b %d %Y")
        LOCAL_SPEC_HEAD=$(sed -n '1,/%changelog/{ /%changelog/d; p }' "$spec_path")
        {
            echo "$LOCAL_SPEC_HEAD"
            echo "%changelog"
            echo "* $DATE_STR Avenge Media <AvengeMedia.US@gmail.com> - ${CHANGELOG_VERSION}-1"
            echo "- Git snapshot (commit $COMMIT_COUNT: $COMMIT_HASH)"
        } > "$spec_path"
    fi
}

# Handle "all" option
if [[ "$PACKAGE" == "all" ]]; then
    echo "==> Uploading all packages"
    DISTRO_ARG=""
    if [[ "$UPLOAD_DEBIAN" == true && "$UPLOAD_OPENSUSE" == false ]]; then
        DISTRO_ARG="debian"
    elif [[ "$UPLOAD_DEBIAN" == false && "$UPLOAD_OPENSUSE" == true ]]; then
        DISTRO_ARG="opensuse"
    fi
    echo ""
    FAILED=()
    for pkg in "${AVAILABLE_PACKAGES[@]}"; do
        if [[ -d "distro/debian/$pkg" ]]; then
            echo "=========================================="
            echo "Uploading $pkg..."
            echo "=========================================="
            if [[ -n "$DISTRO_ARG" ]]; then
                if bash "$0" "$DISTRO_ARG" "$pkg" "$MESSAGE"; then
                    echo "✅ $pkg uploaded successfully"
                else
                    echo "❌ $pkg failed to upload"
                    FAILED+=("$pkg")
                fi
            else
                if bash "$0" "$pkg" "$MESSAGE"; then
                    echo "✅ $pkg uploaded successfully"
                else
                    echo "❌ $pkg failed to upload"
                    FAILED+=("$pkg")
                fi
            fi
            echo ""
        else
            echo "⚠️  Skipping $pkg (not found in distro/debian/)"
        fi
    done

    if [[ ${#FAILED[@]} -eq 0 ]]; then
        echo "✅ All packages uploaded successfully!"
        exit 0
    else
        echo "❌ Some packages failed: ${FAILED[*]}"
        exit 1
    fi
fi

# Check if package exists
if [[ ! -d "distro/debian/$PACKAGE" ]]; then
    echo "Error: Package '$PACKAGE' not found in distro/debian/"
    exit 1
fi

case "$PACKAGE" in
dms)
    PROJECT="dms"
    ;;
dms-git)
    PROJECT="dms-git"
    ;;
*)
    echo "Error: Unknown package '$PACKAGE'"
    exit 1
    ;;
esac

OBS_PROJECT="${OBS_BASE_PROJECT}:${PROJECT}"

echo "==> Target: $OBS_PROJECT / $PACKAGE"

# Detect if this is a manual run or automated
IS_MANUAL=false
if [[ -n "${REBUILD_RELEASE:-}" ]]; then
    IS_MANUAL=true
    echo "==> Manual rebuild detected (REBUILD_RELEASE=$REBUILD_RELEASE)"
elif [[ -n "${FORCE_UPLOAD:-}" ]] && [[ "${FORCE_UPLOAD}" == "true" ]]; then
    IS_MANUAL=true
    echo "==> Force upload detected (FORCE_UPLOAD=true)"
elif [[ -z "${GITHUB_ACTIONS:-}" ]] && [[ -z "${CI:-}" ]]; then
    IS_MANUAL=true
    echo "==> Local/manual run detected (not in CI)"
fi

if [[ "$UPLOAD_DEBIAN" == true && "$UPLOAD_OPENSUSE" == true ]]; then
    echo "==> Distributions: Debian + OpenSUSE"
elif [[ "$UPLOAD_DEBIAN" == true ]]; then
    echo "==> Distribution: Debian only"
elif [[ "$UPLOAD_OPENSUSE" == true ]]; then
    echo "==> Distribution: OpenSUSE only"
fi

mkdir -p "$OBS_BASE"

if [[ ! -d "$OBS_BASE/$OBS_PROJECT/$PACKAGE" ]]; then
    echo "Checking out $OBS_PROJECT/$PACKAGE..."
    cd "$OBS_BASE"
    CHECKOUT_OK=false
    for attempt in 1 2 3; do
        if osc co "$OBS_PROJECT/$PACKAGE"; then
            CHECKOUT_OK=true
            break
        fi
        if [[ $attempt -lt 3 ]]; then
            echo "Checkout failed (attempt $attempt/3). Removing partial copy and retrying in $((5*attempt))s..."
            rm -rf "${OBS_BASE:?}/${OBS_PROJECT:?}"
            sleep $((5*attempt))
        fi
    done
    cd "$REPO_ROOT"
    if [[ "$CHECKOUT_OK" != "true" ]]; then
        echo "Error: Checkout failed after 3 attempts"
        exit 1
    fi
fi

WORK_DIR="$OBS_BASE/$OBS_PROJECT/$PACKAGE"

echo "==> Preparing $PACKAGE for OBS upload"

find "$WORK_DIR" -maxdepth 1 -type f \( -name "*.tar.gz" -o -name "*.tar.xz" -o -name "*.tar.bz2" -o -name "*.tar" -o -name "*.spec" -o -name "_service" -o -name "*.dsc" \) -delete 2>/dev/null || true

if [[ -f "distro/debian/$PACKAGE/_service" ]]; then
    echo "  - Copying _service (for binary downloads)"
    cp "distro/debian/$PACKAGE/_service" "$WORK_DIR/"
fi

CHANGELOG_VERSION=""
if [[ -d "distro/debian/$PACKAGE/debian" ]]; then
    # For -git packages, generate version dynamically from git state (like workflows do)
    if [[ "$PACKAGE" == *"-git" ]]; then
        COMMIT_HASH=$(git rev-parse --short=8 HEAD)
        COMMIT_COUNT=$(git rev-list --count HEAD)
        BASE_VERSION=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)
        if [[ -z "$BASE_VERSION" ]]; then
            BASE_VERSION=$(grep -oP '^Version:\s+\K[0-9.]+' distro/opensuse/dms.spec | head -1 || echo "1.0.2")
        fi
        CHANGELOG_VERSION="${BASE_VERSION}+git${COMMIT_COUNT}.${COMMIT_HASH}"
        echo "  - Generated git snapshot version: $CHANGELOG_VERSION"
    else
        # For stable packages: Format: 0.6.2+git{COMMIT_COUNT}.{COMMIT_HASH}
        CHANGELOG_VERSION=$(grep -m1 "^$PACKAGE" "distro/debian/$PACKAGE/debian/changelog" 2>/dev/null | sed 's/.*(\([^)]*\)).*/\1/' || echo "")
        if [[ -n "$CHANGELOG_VERSION" ]] && [[ "$CHANGELOG_VERSION" == *"-"* ]]; then
            SOURCE_FORMAT_CHECK=$(cat "distro/debian/$PACKAGE/debian/source/format" 2>/dev/null || echo "3.0 (quilt)")
            if [[ "$SOURCE_FORMAT_CHECK" == *"native"* ]]; then
                CHANGELOG_VERSION=$(echo "$CHANGELOG_VERSION" | sed 's/-[0-9]*$//')
            fi
        fi
    fi

    # Apply rebuild suffix if specified (must happen before API check)
    if [[ -n "$REBUILD_RELEASE" ]] && [[ -n "$CHANGELOG_VERSION" ]]; then
        BASE_VERSION=$(echo "$CHANGELOG_VERSION" | sed 's/db[0-9]*$//')
        CHANGELOG_VERSION="${BASE_VERSION}db${REBUILD_RELEASE}"
        echo "  - Applied rebuild suffix: $CHANGELOG_VERSION"
    fi

    # Keep Debian _service in sync with changelog version
    if [[ "$PACKAGE" == "dms" ]] && [[ -f "distro/debian/$PACKAGE/_service" ]]; then
        update_debian_dms_service "distro/debian/$PACKAGE/_service"
    fi

    # Check if this version already exists in OBS
    if [[ -n "$CHANGELOG_VERSION" ]]; then
        if [[ -z "$REBUILD_RELEASE" ]]; then
            if check_obs_version_exists "$OBS_PROJECT" "$PACKAGE" "$CHANGELOG_VERSION"; then
                if [[ "$PACKAGE" == *"-git" ]]; then
                    echo "==> Error: This commit is already uploaded to OBS"
                    echo "    The same git commit ($(echo "$CHANGELOG_VERSION" | grep -oP '[a-f0-9]{8}' | tail -1)) already exists on OBS."
                    if [[ -n "${GITHUB_ACTIONS:-}" ]] || [[ -n "${CI:-}" ]]; then
                        echo "    CI run detected: skipping upload as a no-op (already up to date)."
                        echo "    If you need to force rebuild this same commit, set REBUILD_RELEASE (e.g. 2, 3, ...)."
                        echo "✓ Exiting gracefully (no changes needed)"
                        exit 0
                    fi
                    echo "    To rebuild the same commit, specify a rebuild number:"
                    echo "      ./distro/scripts/obs-upload.sh $PACKAGE 2"
                    echo "      ./distro/scripts/obs-upload.sh $PACKAGE 3"
                    echo "    Or push a new commit first, then run:"
                    echo "      ./distro/scripts/obs-upload.sh $PACKAGE"
                else
                    echo "==> Error: Version $CHANGELOG_VERSION already exists in OBS"
                    echo "    To rebuild with a different release number, try:"
                    echo "      ./distro/scripts/obs-upload.sh $PACKAGE --rebuild=2"
                    echo "    or positional syntax:"
                    echo "      ./distro/scripts/obs-upload.sh $PACKAGE 2"
                fi
                exit 1
            fi
        else
            # Rebuild number specified - check if this exact version already exists (exact mode)
            if check_obs_version_exists "$OBS_PROJECT" "$PACKAGE" "$CHANGELOG_VERSION" "exact"; then
                echo "==> Version $CHANGELOG_VERSION already exists in OBS"
                echo "    This exact version (including db${REBUILD_RELEASE}) is already uploaded."
                echo "    Skipping upload - nothing to do."
                echo ""
                echo "    💡 To rebuild with a different release number, try incrementing:"
                NEXT_NUM=$((REBUILD_RELEASE + 1))
                echo "       REBUILD_RELEASE=$NEXT_NUM"
                echo ""
                echo "✓ Exiting gracefully (no changes needed)"
                exit 0
            fi
        fi
    fi
fi

if [[ "$UPLOAD_OPENSUSE" == true ]] && [[ -f "distro/opensuse/$PACKAGE.spec" ]]; then
    echo "  - Copying $PACKAGE.spec for OpenSUSE"
    cp "distro/opensuse/$PACKAGE.spec" "$WORK_DIR/"

    if [[ "$PACKAGE" == *"-git" ]]; then
        update_opensuse_git_spec "$WORK_DIR/$PACKAGE.spec"
    fi

    if [[ -f "$WORK_DIR/.osc/$PACKAGE.spec" ]]; then
        NEW_VERSION=$(grep "^Version:" "$WORK_DIR/$PACKAGE.spec" | awk '{print $2}' | head -1)
        NEW_RELEASE=$(grep "^Release:" "$WORK_DIR/$PACKAGE.spec" | sed 's/^Release:[[:space:]]*//' | sed 's/%{?dist}//' | head -1)
        OLD_VERSION=$(grep "^Version:" "$WORK_DIR/.osc/$PACKAGE.spec" | awk '{print $2}' | head -1)
        OLD_RELEASE=$(grep "^Release:" "$WORK_DIR/.osc/$PACKAGE.spec" | sed 's/^Release:[[:space:]]*//' | sed 's/%{?dist}//' | head -1)

        if [[ "$NEW_VERSION" == "$OLD_VERSION" ]]; then
            if [[ "$IS_MANUAL" == true ]] && [[ -z "${GITHUB_ACTIONS:-}" ]] && [[ -z "${CI:-}" ]]; then
                # Only error for true local manual runs, not CI/workflow runs
                if [[ -n "${REBUILD_RELEASE:-}" ]]; then
                    echo "  🔄 Using manual rebuild release number: $REBUILD_RELEASE"
                    sed -i "s/^Release:[[:space:]]*${NEW_RELEASE}%{?dist}/Release:        ${REBUILD_RELEASE}%{?dist}/" "$WORK_DIR/$PACKAGE.spec"
                    cp "$WORK_DIR/$PACKAGE.spec" "$REPO_ROOT/distro/opensuse/$PACKAGE.spec"
                else
                    echo "  - Error: Same version detected ($NEW_VERSION) but no rebuild number specified"
                    echo "    To rebuild, explicitly specify a rebuild number:"
                    echo "      ./distro/scripts/obs-upload.sh opensuse $PACKAGE 2"
                    echo "    or use flag syntax:"
                    echo "      ./distro/scripts/obs-upload.sh opensuse $PACKAGE --rebuild=2"
                    exit 1
                fi
            else
                echo "  - Detected same version $NEW_VERSION (release $OLD_RELEASE). No changes needed, skipping update."
                echo "✅ No changes needed for this package. Exiting gracefully."
                exit 0
            fi
        else
            echo "  - New version detected: $OLD_VERSION -> $NEW_VERSION (keeping release $NEW_RELEASE)"
            cp "$WORK_DIR/$PACKAGE.spec" "$REPO_ROOT/distro/opensuse/$PACKAGE.spec"
        fi
    else
        echo "  - First upload to OBS (no previous spec found)"
    fi
elif [[ "$UPLOAD_OPENSUSE" == true ]]; then
    echo "  - Warning: OpenSUSE spec file not found, skipping OpenSUSE upload"
fi

if [[ "$UPLOAD_OPENSUSE" == true ]] && [[ "$UPLOAD_DEBIAN" == false ]] && [[ -f "distro/opensuse/$PACKAGE.spec" ]]; then
    echo "  - OpenSUSE-only upload: creating source tarball"

    TEMP_DIR=$(mktemp -d)
    trap 'rm -rf $TEMP_DIR' EXIT

    if [[ -f "distro/debian/$PACKAGE/_service" ]] && grep -q "tar_scm" "distro/debian/$PACKAGE/_service"; then
        GIT_URL=$(grep -A 5 'name="tar_scm"' "distro/debian/$PACKAGE/_service" | grep "url" | sed 's/.*<param name="url">\(.*\)<\/param>.*/\1/')
        GIT_REVISION=$(grep -A 5 'name="tar_scm"' "distro/debian/$PACKAGE/_service" | grep "revision" | sed 's/.*<param name="revision">\(.*\)<\/param>.*/\1/')

        if [[ -n "$GIT_URL" ]]; then
            echo "    Cloning git source from: $GIT_URL (revision: ${GIT_REVISION:-master})"
            SOURCE_DIR="$TEMP_DIR/dms-git-source"
            if git clone --depth 1 --recurse-submodules --shallow-submodules --branch "${GIT_REVISION:-master}" "$GIT_URL" "$SOURCE_DIR" 2>/dev/null ||
                git clone --depth 1 --recurse-submodules --shallow-submodules "$GIT_URL" "$SOURCE_DIR" 2>/dev/null; then
                cd "$SOURCE_DIR"
                if [[ -n "$GIT_REVISION" ]]; then
                    git checkout "$GIT_REVISION" 2>/dev/null || true
                fi
                rm -rf .git
                SOURCE_DIR=$(pwd)
                cd "$REPO_ROOT"
            fi
        fi
    fi

    if [[ -n "$SOURCE_DIR" && -d "$SOURCE_DIR" ]]; then
        SOURCE0=$(grep "^Source0:" "distro/opensuse/$PACKAGE.spec" | awk '{print $2}' | head -1)

        if [[ -n "$SOURCE0" ]]; then
            OBS_TARBALL_DIR=$(mktemp -d -t obs-tarball-XXXXXX)
            cd "$OBS_TARBALL_DIR"

            case "$PACKAGE" in
            dms)
                DMS_VERSION=$(grep "^Version:" "$REPO_ROOT/distro/opensuse/$PACKAGE.spec" | sed 's/^Version:[[:space:]]*//' | head -1)
                EXPECTED_DIR="DankMaterialShell-${DMS_VERSION}"
                ;;
            dms-git)
                EXPECTED_DIR="dms-git-source"
                ;;
            *)
                EXPECTED_DIR=$(basename "$SOURCE_DIR")
                ;;
            esac

            echo "    Creating $SOURCE0 (directory: $EXPECTED_DIR)"
            cp -r "$SOURCE_DIR" "$EXPECTED_DIR"
            tar -czhf "$WORK_DIR/$SOURCE0" "$EXPECTED_DIR"
            rm -rf "$EXPECTED_DIR"
            echo "    Created $SOURCE0 ($(stat -c%s "$WORK_DIR/$SOURCE0" 2>/dev/null || echo 0) bytes)"

            cd "$REPO_ROOT"
            rm -rf "$OBS_TARBALL_DIR"

            if [[ "$PACKAGE" == "dms-git" ]]; then
                echo "  - Staging bundled Go toolchains for RPM (Source1/Source2)"
                ensure_dms_git_go_tarballs "$WORK_DIR"
            fi
        fi
    else
        echo "  - Warning: Could not obtain source for OpenSUSE tarball"
    fi
fi

# Generate .dsc file and handle source format (for Debian only)
if [[ "$UPLOAD_DEBIAN" == true ]] && [[ -d "distro/debian/$PACKAGE/debian" ]]; then
    # Use CHANGELOG_VERSION already set above, or get it if not set
    if [[ -z "$CHANGELOG_VERSION" ]]; then
        CHANGELOG_VERSION=$(grep -m1 "^$PACKAGE" distro/debian/"$PACKAGE"/debian/changelog 2>/dev/null | sed 's/.*(\([^)]*\)).*/\1/' || echo "0.1.11")
    fi

    # Determine source format
    SOURCE_FORMAT=$(cat "distro/debian/$PACKAGE/debian/source/format" 2>/dev/null || echo "3.0 (quilt)")

    # For native format, remove any Debian revision (-N) from version
    # Native format cannot have revisions, so strip them if present
    if [[ "$SOURCE_FORMAT" == *"native"* ]] && [[ "$CHANGELOG_VERSION" == *"-"* ]]; then
        # Remove Debian revision (everything from - onwards)
        CHANGELOG_VERSION=$(echo "$CHANGELOG_VERSION" | sed 's/-[0-9]*$//')
        echo "  Warning: Removed Debian revision from version for native format: $CHANGELOG_VERSION"
    fi

    if [[ "$SOURCE_FORMAT" == *"native"* ]]; then
        echo "  - Native format detected: creating combined tarball"

        VERSION="$CHANGELOG_VERSION"
        TEMP_DIR=$(mktemp -d)
        trap 'rm -rf $TEMP_DIR' EXIT
        COMBINED_TARBALL="${PACKAGE}_${VERSION}.tar.gz"
        SOURCE_DIR=""

        if [[ -f "distro/debian/$PACKAGE/_service" ]]; then
            if grep -q "tar_scm" "distro/debian/$PACKAGE/_service"; then
                GIT_URL=$(grep -A 5 'name="tar_scm"' "distro/debian/$PACKAGE/_service" | grep "url" | sed 's/.*<param name="url">\(.*\)<\/param>.*/\1/')
                GIT_REVISION=$(grep -A 5 'name="tar_scm"' "distro/debian/$PACKAGE/_service" | grep "revision" | sed 's/.*<param name="revision">\(.*\)<\/param>.*/\1/')

                if [[ -n "$GIT_URL" ]]; then
                    echo "    Cloning git source from: $GIT_URL (revision: ${GIT_REVISION:-master})"
                    SOURCE_DIR="$TEMP_DIR/dms-git-source"
                    if git clone --depth 1 --recurse-submodules --shallow-submodules --branch "${GIT_REVISION:-master}" "$GIT_URL" "$SOURCE_DIR" 2>/dev/null ||
                        git clone --depth 1 --recurse-submodules --shallow-submodules "$GIT_URL" "$SOURCE_DIR" 2>/dev/null; then
                        cd "$SOURCE_DIR"
                        if [[ -n "$GIT_REVISION" ]]; then
                            git checkout "$GIT_REVISION" 2>/dev/null || true
                        fi
                        rm -rf .git
                        SOURCE_DIR=$(pwd)
                        cd "$REPO_ROOT"
                    else
                        echo "Error: Failed to clone git repository"
                        exit 1
                    fi
                fi
            elif grep -q "download_url" "distro/debian/$PACKAGE/_service" && [[ "$PACKAGE" != "dms-git" ]]; then
                ALL_PATHS=$(grep -A 5 '<service name="download_url">' "distro/debian/$PACKAGE/_service" |
                    grep '<param name="path">' |
                    sed 's/.*<param name="path">\(.*\)<\/param>.*/\1/')

                SOURCE_PATH=""
                for path in $ALL_PATHS; do
                    if echo "$path" | grep -qE "(source|archive|\.tar\.(gz|xz|bz2))" &&
                        ! echo "$path" | grep -qE "(distropkg|binary)"; then
                        SOURCE_PATH="$path"
                        break
                    fi
                done

                if [[ -z "$SOURCE_PATH" ]]; then
                    for path in $ALL_PATHS; do
                        if echo "$path" | grep -qE "\.tar\.(gz|xz|bz2)$"; then
                            SOURCE_PATH="$path"
                            break
                        fi
                    done
                fi

                if [[ -n "$SOURCE_PATH" ]]; then
                    SOURCE_BLOCK=$(awk -v target="$SOURCE_PATH" '
                        /<service name="download_url">/ { in_block=1; block="" }
                        in_block { block=block"\n"$0 }
                        /<\/service>/ {
                            if (in_block && block ~ target) {
                                print block
                                exit
                            }
                            in_block=0
                        }
                    ' "distro/debian/$PACKAGE/_service")

                    URL_PROTOCOL=$(echo "$SOURCE_BLOCK" | grep "protocol" | sed 's/.*<param name="protocol">\(.*\)<\/param>.*/\1/' | head -1)
                    URL_HOST=$(echo "$SOURCE_BLOCK" | grep "host" | sed 's/.*<param name="host">\(.*\)<\/param>.*/\1/' | head -1)
                    URL_PATH="$SOURCE_PATH"
                fi

                if [[ -n "$URL_PROTOCOL" && -n "$URL_HOST" && -n "$URL_PATH" ]]; then
                    SOURCE_URL="${URL_PROTOCOL}://${URL_HOST}${URL_PATH}"
                    echo "==> Downloading source from: $SOURCE_URL"

                    if wget -q -O "$TEMP_DIR/source-archive" "$SOURCE_URL" 2>/dev/null ||
                        curl -L -f -s -o "$TEMP_DIR/source-archive" "$SOURCE_URL" 2>/dev/null; then
                        cd "$TEMP_DIR"
                        if [[ "$SOURCE_URL" == *.tar.xz ]]; then
                            tar -xJf source-archive
                        elif [[ "$SOURCE_URL" == *.tar.gz ]] || [[ "$SOURCE_URL" == *.tgz ]]; then
                            tar -xzf source-archive
                        fi
                        SOURCE_DIR=$(find . -maxdepth 1 -type d -name "DankMaterialShell-*" | head -1)
                        if [[ -z "$SOURCE_DIR" ]]; then
                            SOURCE_DIR=$(find . -maxdepth 1 -type d ! -name "." | head -1)
                        fi
                        if [[ -z "$SOURCE_DIR" || ! -d "$SOURCE_DIR" ]]; then
                            echo "Error: Failed to extract source archive or find source directory"
                            echo "Contents of $TEMP_DIR:"
                            ls -la "$TEMP_DIR"
                            cd "$REPO_ROOT"
                            exit 1
                        fi
                        SOURCE_DIR=$(cd "$SOURCE_DIR" && pwd)
                        cd "$REPO_ROOT"
                        if [[ "$(pwd)" != "$REPO_ROOT" ]]; then
                            echo "ERROR: Failed to return to REPO_ROOT. Expected: $REPO_ROOT, Got: $(pwd)"
                            exit 1
                        fi
                    else
                        echo "ERROR: Failed to download source from $SOURCE_URL"
                        echo "Attempted both wget and curl"
                        echo "Please check:"
                        echo "  1. URL is accessible: $SOURCE_URL"
                        echo "  2. _service file has correct version"
                        echo "  3. GitHub releases are available"
                        exit 1
                    fi
                fi
            fi
        fi

        if [[ -z "$SOURCE_DIR" || ! -d "$SOURCE_DIR" ]]; then
            echo "Error: Could not determine or obtain source for $PACKAGE"
            echo "SOURCE_DIR: $SOURCE_DIR"
            if [[ -d "$TEMP_DIR" ]]; then
                echo "Contents of temp directory:"
                ls -la "$TEMP_DIR"
            fi
            exit 1
        fi

        echo "==> Found source directory: $SOURCE_DIR"

        # Vendor Go dependencies for dms-git
        if [[ "$PACKAGE" == "dms-git" ]] && [[ -d "$SOURCE_DIR/core" ]]; then
            echo "  - Vendoring Go dependencies for offline OBS build..."
            cd "$SOURCE_DIR/core"

            if ! command -v go &>/dev/null; then
                echo "ERROR: Go not found. Install Go to vendor dependencies."
                echo "  Install: sudo apt-get install golang-go (Debian/Ubuntu)"
                echo "      or: sudo dnf install golang (Fedora)"
                exit 1
            fi

            # Vendor dependencies
            go mod vendor
            if [ ! -d "vendor" ]; then
                echo "ERROR: Failed to vendor Go dependencies"
                exit 1
            fi

            VENDOR_SIZE=$(du -sh vendor | cut -f1)
            echo "    ✓ Go dependencies vendored ($VENDOR_SIZE)"
            cd "$REPO_ROOT"
        fi

        # Create OpenSUSE-compatible source tarballs BEFORE adding debian/ directory
        if [[ "$UPLOAD_OPENSUSE" == true ]] && [[ -f "distro/opensuse/$PACKAGE.spec" ]]; then
            echo "  - Creating OpenSUSE-compatible source tarballs"

            SOURCE0=$(grep "^Source0:" "distro/opensuse/$PACKAGE.spec" | awk '{print $2}' | head -1)
            if [[ -z "$SOURCE0" && "$PACKAGE" == "dms-git" ]]; then
                SOURCE0="dms-git-source.tar.gz"
            fi

            if [[ -n "$SOURCE0" ]]; then
                OBS_TARBALL_DIR=$(mktemp -d -t obs-tarball-XXXXXX)
                cd "$OBS_TARBALL_DIR"

                case "$PACKAGE" in
                dms)
                    DMS_VERSION=$(grep "^Version:" "$REPO_ROOT/distro/opensuse/$PACKAGE.spec" | sed 's/^Version:[[:space:]]*//' | head -1)
                    EXPECTED_DIR="DankMaterialShell-${DMS_VERSION}"
                    echo "    Creating $SOURCE0 (directory: $EXPECTED_DIR)"
                    cp -r "$SOURCE_DIR" "$EXPECTED_DIR"
                    if [[ "$SOURCE0" == *.tar.xz ]]; then
                        tar --sort=name --mtime='2000-01-01 00:00:00' --owner=0 --group=0 -cJhf "$WORK_DIR/$SOURCE0" "$EXPECTED_DIR"
                    elif [[ "$SOURCE0" == *.tar.bz2 ]]; then
                        tar --sort=name --mtime='2000-01-01 00:00:00' --owner=0 --group=0 -cjhf "$WORK_DIR/$SOURCE0" "$EXPECTED_DIR"
                    else
                        tar --sort=name --mtime='2000-01-01 00:00:00' --owner=0 --group=0 -czhf "$WORK_DIR/$SOURCE0" "$EXPECTED_DIR"
                    fi
                    rm -rf "$EXPECTED_DIR"
                    echo "    Created $SOURCE0 ($(stat -c%s "$WORK_DIR/$SOURCE0" 2>/dev/null || echo 0) bytes)"
                    ;;
                dms-git)
                    EXPECTED_DIR="dms-git-source"
                    echo "    Creating $SOURCE0 (directory: $EXPECTED_DIR)"
                    cp -r "$SOURCE_DIR" "$EXPECTED_DIR"
                    if [[ "$SOURCE0" == *.tar.xz ]]; then
                        tar --sort=name --mtime='2000-01-01 00:00:00' --owner=0 --group=0 -cJhf "$WORK_DIR/$SOURCE0" "$EXPECTED_DIR"
                    elif [[ "$SOURCE0" == *.tar.bz2 ]]; then
                        tar --sort=name --mtime='2000-01-01 00:00:00' --owner=0 --group=0 -cjhf "$WORK_DIR/$SOURCE0" "$EXPECTED_DIR"
                    else
                        tar --sort=name --mtime='2000-01-01 00:00:00' --owner=0 --group=0 -czhf "$WORK_DIR/$SOURCE0" "$EXPECTED_DIR"
                    fi
                    rm -rf "$EXPECTED_DIR"
                    echo "    Created $SOURCE0 ($(stat -c%s "$WORK_DIR/$SOURCE0" 2>/dev/null || echo 0) bytes)"
                    ;;
                *)
                    DIR_NAME=$(basename "$SOURCE_DIR")
                    echo "    Creating $SOURCE0 (directory: $DIR_NAME)"
                    cp -r "$SOURCE_DIR" "$DIR_NAME"
                    if [[ "$SOURCE0" == *.tar.xz ]]; then
                        tar --sort=name --mtime='2000-01-01 00:00:00' --owner=0 --group=0 -cJhf "$WORK_DIR/$SOURCE0" "$DIR_NAME"
                    elif [[ "$SOURCE0" == *.tar.bz2 ]]; then
                        tar --sort=name --mtime='2000-01-01 00:00:00' --owner=0 --group=0 -cjhf "$WORK_DIR/$SOURCE0" "$DIR_NAME"
                    else
                        tar --sort=name --mtime='2000-01-01 00:00:00' --owner=0 --group=0 -czhf "$WORK_DIR/$SOURCE0" "$DIR_NAME"
                    fi
                    rm -rf "$DIR_NAME"
                    echo "    Created $SOURCE0 ($(stat -c%s "$WORK_DIR/$SOURCE0" 2>/dev/null || echo 0) bytes)"
                    ;;
                esac
                cd "$REPO_ROOT"
                rm -rf "$OBS_TARBALL_DIR"

                if [[ "$PACKAGE" == "dms-git" ]]; then
                    echo "  - Staging bundled Go toolchains for RPM (Source1/Source2)"
                    ensure_dms_git_go_tarballs "$WORK_DIR"
                fi

                echo "  - OpenSUSE source tarballs created"
            fi

            # Copy and update OpenSUSE spec file with the correct version
            cp "distro/opensuse/$PACKAGE.spec" "$WORK_DIR/"
            if [[ "$PACKAGE" == *"-git" ]]; then
                update_opensuse_git_spec "$WORK_DIR/$PACKAGE.spec"
            fi
        fi

        if [[ "$UPLOAD_DEBIAN" == true ]]; then
            echo "    Copying debian/ directory into source"
            cp -r "distro/debian/$PACKAGE/debian" "$SOURCE_DIR/"

            # Update changelog with the correct version (for -git packages, use dynamically generated version)
            if [[ -n "$CHANGELOG_VERSION" ]] && [[ -f "$SOURCE_DIR/debian/changelog" ]]; then
                echo "    Updating changelog to version $CHANGELOG_VERSION"
                TEMP_CHANGELOG=$(mktemp)
                {
                    echo "$PACKAGE ($CHANGELOG_VERSION) unstable; urgency=medium"
                    echo ""
                    if [[ "$PACKAGE" == *"-git" ]]; then
                        echo "  * Git snapshot (commit $COMMIT_COUNT: $COMMIT_HASH)"
                    else
                        echo "  * Automated update"
                    fi
                    echo ""
                    echo " -- Avenge Media <AvengeMedia.US@gmail.com>  $(date -R)"
                } >"$TEMP_CHANGELOG"
                cp "$TEMP_CHANGELOG" "$SOURCE_DIR/debian/changelog"
                rm -f "$TEMP_CHANGELOG"
            fi

            # For dms, rename directory to match what debian/rules expects
            # debian/rules uses UPSTREAM_VERSION which is the full version from changelog
            if [[ "$PACKAGE" == "dms" ]]; then
                CHANGELOG_IN_SOURCE="$SOURCE_DIR/debian/changelog"
                if [[ -f "$CHANGELOG_IN_SOURCE" ]]; then
                    ACTUAL_VERSION=$(grep -m1 "^$PACKAGE" "$CHANGELOG_IN_SOURCE" 2>/dev/null | sed 's/.*(\([^)]*\)).*/\1/' || echo "$VERSION")
                    CURRENT_DIR=$(basename "$SOURCE_DIR")
                    EXPECTED_DIR="DankMaterialShell-${ACTUAL_VERSION}"
                    if [[ "$CURRENT_DIR" != "$EXPECTED_DIR" ]]; then
                        echo "    Renaming directory from $CURRENT_DIR to $EXPECTED_DIR to match debian/rules"
                        cd "$(dirname "$SOURCE_DIR")"
                        mv "$CURRENT_DIR" "$EXPECTED_DIR"
                        SOURCE_DIR="$(pwd)/$EXPECTED_DIR"
                        cd "$REPO_ROOT"
                    fi
                fi
            fi

            if [[ "$PACKAGE" == "dms-git" ]]; then
                echo "    Bundling Go toolchains into Debian source tree (offline build)"
                ensure_dms_git_go_tarballs "$SOURCE_DIR"
            fi

            rm -f "$WORK_DIR/$COMBINED_TARBALL"

            echo "    Creating combined tarball: $COMBINED_TARBALL"
            cd "$(dirname "$SOURCE_DIR")"
            TARBALL_BASE=$(basename "$SOURCE_DIR")
            tar --sort=name --mtime='2000-01-01 00:00:00' --owner=0 --group=0 -czf "$WORK_DIR/$COMBINED_TARBALL" "$TARBALL_BASE"
            cd "$REPO_ROOT"
            if [[ "$(pwd)" != "$REPO_ROOT" ]]; then
                echo "ERROR: Failed to return to REPO_ROOT after tarball creation"
                exit 1
            fi

            if [[ "$PACKAGE" == "dms" ]]; then
                TARBALL_DIR=$(tar -tzf "$WORK_DIR/$COMBINED_TARBALL" 2>/dev/null | head -1 | cut -d'/' -f1)
                EXPECTED_TARBALL_DIR="DankMaterialShell-${VERSION}"
                if [[ "$TARBALL_DIR" != "$EXPECTED_TARBALL_DIR" ]]; then
                    echo "    Warning: Tarball directory name mismatch: $TARBALL_DIR != $EXPECTED_TARBALL_DIR"
                    echo "    This may cause build failures. Recreating tarball..."
                    cd "$(dirname "$SOURCE_DIR")"
                    rm -f "$WORK_DIR/$COMBINED_TARBALL"
                    tar --sort=name --mtime='2000-01-01 00:00:00' --owner=0 --group=0 -czf "$WORK_DIR/$COMBINED_TARBALL" "$TARBALL_BASE"
                    cd "$REPO_ROOT"
                    if [[ "$(pwd)" != "$REPO_ROOT" ]]; then
                        echo "ERROR: Failed to return to REPO_ROOT after tarball recreation"
                        exit 1
                    fi
                fi
            fi

            TARBALL_SIZE=$(stat -c%s "$WORK_DIR/$COMBINED_TARBALL" 2>/dev/null || stat -f%z "$WORK_DIR/$COMBINED_TARBALL" 2>/dev/null)
            TARBALL_MD5=$(md5sum "$WORK_DIR/$COMBINED_TARBALL" | cut -d' ' -f1)

            # Extract Build-Depends from debian/control using awk for proper multi-line parsing
            if [[ -f "$REPO_ROOT/distro/debian/$PACKAGE/debian/control" ]]; then
                BUILD_DEPS=$(awk '
                    /^Build-Depends:/ {
                        in_build_deps=1;
                        sub(/^Build-Depends:[[:space:]]*/, "");
                        printf "%s", $0;
                        next;
                    }
                    in_build_deps && /^[[:space:]]/ {
                        sub(/^[[:space:]]+/, " ");
                        printf "%s", $0;
                        next;
                    }
                    in_build_deps { exit; }
                ' "$REPO_ROOT/distro/debian/$PACKAGE/debian/control" | sed 's/[[:space:]]\+/ /g; s/^[[:space:]]*//; s/[[:space:]]*$//')

                # If extraction failed or is empty, use default fallback
                if [[ -z "$BUILD_DEPS" ]]; then
                    BUILD_DEPS="debhelper-compat (= 13)"
                fi
            else
                BUILD_DEPS="debhelper-compat (= 13)"
            fi

            cat >"$WORK_DIR/$PACKAGE.dsc" <<EOF
Format: 3.0 (native)
Source: $PACKAGE
Binary: $PACKAGE
Architecture: any
Version: $VERSION
Maintainer: Avenge Media <AvengeMedia.US@gmail.com>
Build-Depends: $BUILD_DEPS
Files:
 $TARBALL_MD5 $TARBALL_SIZE $COMBINED_TARBALL
EOF

            echo "  - Generated $PACKAGE.dsc for native format"
        fi
    else
        if [[ "$UPLOAD_DEBIAN" == true ]]; then
            if [[ "$CHANGELOG_VERSION" == *"-"* ]]; then
                VERSION="$CHANGELOG_VERSION"
            else
                VERSION="${CHANGELOG_VERSION}-1"
            fi

            echo "  - Quilt format detected: creating debian.tar.gz"
            tar -czf "$WORK_DIR/debian.tar.gz" -C "distro/debian/$PACKAGE" debian/

            DEBIAN_MD5=$(md5sum "$WORK_DIR/debian.tar.gz" | cut -d' ' -f1)
            DEBIAN_SIZE=$(stat -c%s "$WORK_DIR/debian.tar.gz" 2>/dev/null || stat -f%z "$WORK_DIR/debian.tar.gz" 2>/dev/null)

            echo "  - Generating $PACKAGE.dsc for quilt format"
            cat >"$WORK_DIR/$PACKAGE.dsc" <<DSCEOF
Format: 3.0 (quilt)
Source: $PACKAGE
Binary: $PACKAGE
Architecture: any
Version: $VERSION
Maintainer: Avenge Media <AvengeMedia.US@gmail.com>
Build-Depends: debhelper-compat (= 13), wget, gzip
Files:
 $DEBIAN_MD5 $DEBIAN_SIZE debian.tar.gz
DSCEOF
        fi
    fi
fi

echo "==> Ensuring we're in the OSC working directory"
cd "$WORK_DIR" || {
    echo "ERROR: Cannot cd to WORK_DIR: $WORK_DIR"
    echo "DEBUG: Current directory: $(pwd)"
    echo "DEBUG: WORK_DIR exists: $(test -d "$WORK_DIR" && echo "yes" || echo "no")"
    exit 1
}
echo "DEBUG: Successfully entered WORK_DIR: $(pwd)"

# Server-side cleanup via API
echo "==> Cleaning old tarballs from OBS server (prevents downloading 100+ old versions)"
OBS_FILES=$(osc api "/source/$OBS_PROJECT/$PACKAGE" 2>/dev/null || echo "")
if [[ -n "$OBS_FILES" ]]; then
    DELETED_COUNT=0
    KEEP_CURRENT=""
    if [[ -n "$CHANGELOG_VERSION" ]]; then
        KEEP_CURRENT="${PACKAGE}_${CHANGELOG_VERSION}.tar.gz"
        echo "  Keeping only current version: ${KEEP_CURRENT}"
    fi

    for old_file in $(echo "$OBS_FILES" | grep -oP '(?<=name=")[^"]*\.(tar\.gz|tar\.xz|tar\.bz2)(?=")' || true); do
        if [[ "$old_file" == "$KEEP_CURRENT" ]]; then
            echo "  - Keeping: $old_file"
            continue
        fi

        # Keep pinned Go toolchain archives (bundled for dms-git offline builds)
        if [[ "$old_file" =~ ^go[0-9].+\.linux-(amd64|arm64)\.tar\.gz$ ]]; then
            echo "  - Keeping Go toolchain tarball: $old_file"
            continue
        fi

        if [[ "$old_file" == "${PACKAGE}-source.tar.gz" ]]; then
            echo "  - Keeping source tarball: $old_file"
            continue
        fi

        echo "  - Deleting from server: $old_file"
        if osc api -X DELETE "/source/$OBS_PROJECT/$PACKAGE/$old_file" 2>/dev/null; then
            ((DELETED_COUNT++)) || true
        fi
    done

    # Remove service-generated download_url artifacts so new ones are created
    for old_file in $(echo "$OBS_FILES" | grep -oP '(?<=name=")_service:download_url:[^"]+(?=")' || true); do
        echo "  - Deleting old service artifact: $old_file"
        if osc api -X DELETE "/source/$OBS_PROJECT/$PACKAGE/$old_file" 2>/dev/null; then
            ((DELETED_COUNT++)) || true
        fi
    done

    if [[ $DELETED_COUNT -gt 0 ]]; then
        echo "  ✓ Deleted $DELETED_COUNT old tarball(s) from server"
    else
        echo "  ✓ No old tarballs found on server (current version preserved)"
    fi
else
    echo "  ⚠️  Could not fetch file list from server, skipping cleanup"
fi

# Update working copy to latest revision (without expanding service files to avoid revision conflicts)
echo "==> Updating working copy"
if ! osc_retry up 2>/dev/null; then
    echo "Error: Failed to update working copy"
    exit 1
fi

# Ensure we're in WORK_DIR and it exists
if [[ ! -d "$WORK_DIR" ]]; then
    echo "ERROR: WORK_DIR does not exist: $WORK_DIR"
    exit 1
fi

cd "$WORK_DIR" || {
    echo "ERROR: Cannot cd to WORK_DIR: $WORK_DIR"
    exit 1
}

find . -maxdepth 1 -type f \( -name "*.dsc" -o -name "*.spec" \) -exec grep -l "^<<<<<<< " {} \; 2>/dev/null | while read -r conflicted_file; do
    echo "  Removing conflicted text file: $conflicted_file"
    rm -f "$conflicted_file"
done

if [[ "$UPLOAD_DEBIAN" == false ]]; then
    rm -f ./*.dsc ./*.dsc.* ./*.spec.* ./*.mine ./*.new ./*.orig _service 2>/dev/null || true
fi

# Ensure we're STILL in WORK_DIR before running osc commands
cd "$WORK_DIR" || {
    echo "ERROR: Cannot cd to WORK_DIR: $WORK_DIR"
    exit 1
}
echo "DEBUG: Current directory: $(pwd)"
echo "DEBUG: WORK_DIR=$WORK_DIR"
echo "DEBUG: Files in directory:"
ls -la 2>&1 | head -20

echo "==> Staging changes"
echo "Files to upload:"
if [[ "$UPLOAD_DEBIAN" == true ]] && [[ "$UPLOAD_OPENSUSE" == true ]]; then
    ls -lh ./*.tar.gz ./*.tar.xz ./*.tar ./*.spec ./*.dsc _service ./go*.linux-*.tar.gz 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}'
elif [[ "$UPLOAD_DEBIAN" == true ]]; then
    ls -lh ./*.tar.gz ./*.dsc _service ./go*.linux-*.tar.gz 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}'
elif [[ "$UPLOAD_OPENSUSE" == true ]]; then
    ls -lh ./*.tar.gz ./*.tar.xz ./*.tar ./*.spec _service ./go*.linux-*.tar.gz 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}'
fi
echo ""

if [[ "$(pwd)" != "$WORK_DIR" ]]; then
    echo "ERROR: Lost directory context. Expected: $WORK_DIR, Got: $(pwd)"
    cd "$WORK_DIR" || {
        echo "FATAL: Cannot recover - unable to cd to WORK_DIR"
        exit 1
    }
    echo "WARNING: Recovered directory context"
fi

osc addremove 2>&1 | grep -v "Git SCM package" || true

SOURCE_TARBALL="${PACKAGE}-source.tar.gz"
if [[ -f "$SOURCE_TARBALL" ]]; then
    echo "==> Ensuring $SOURCE_TARBALL is tracked by OBS"
    osc add "$SOURCE_TARBALL" 2>&1 | grep -v "already added\|already tracked\|Git SCM package" || true
elif [[ -f "$WORK_DIR/$SOURCE_TARBALL" ]]; then
    echo "==> Copying $SOURCE_TARBALL from WORK_DIR and adding to OBS"
    cp "$WORK_DIR/$SOURCE_TARBALL" "$SOURCE_TARBALL"
    osc add "$SOURCE_TARBALL" 2>&1 | grep -v "already added\|already tracked\|Git SCM package" || true
fi
ADDREMOVE_EXIT=${PIPESTATUS[0]}
if [[ $ADDREMOVE_EXIT -ne 0 ]] && [[ $ADDREMOVE_EXIT -ne 1 ]]; then
    echo "Warning: osc addremove returned exit code $ADDREMOVE_EXIT"
fi

if osc status | grep -q '^C'; then
    echo "==> Resolving conflicts"
    osc status | grep '^C' | awk '{print $2}' | xargs -r osc resolved
fi

if ! osc status 2>/dev/null | grep -qE '^[MAD]|^[?]'; then
    echo "==> No changes to commit (package already up to date)"
else
    echo "==> Committing to OBS"
    set +e
    osc_retry commit --skip-local-service-run -m "$MESSAGE" 2>&1 | grep -v "Git SCM package" | grep -v "apiurl\|project\|_ObsPrj\|_manifest\|git-obs"
    COMMIT_EXIT=${PIPESTATUS[0]}
    set -e
    if [[ $COMMIT_EXIT -ne 0 ]]; then
        echo "Error: Upload failed with exit code $COMMIT_EXIT"
        exit 1
    fi
fi

osc results

echo ""
echo "✅ Upload complete!"
cd "$WORK_DIR"
osc results 2>&1 | head -10
cd "$REPO_ROOT"
echo ""
echo "Check build status with:"
echo "  ./distro/scripts/obs-status.sh $PACKAGE"
