#!/usr/bin/env bash
# Generic source package builder for DMS PPA packages
# Usage: ./create-source.sh <package-dir> [ubuntu-series]
#
# Example:
#   ./create-source.sh ../dms resolute     # Ubuntu 26.04 LTS (default series in ppa-upload)
#   ./create-source.sh ../dms stonking     # Ubuntu 26.10
#   ./create-source.sh ../dms-git resolute
#   ./create-source.sh ../dms-git stonking

set -e

PPA_OWNER="${PPA_OWNER:-duxlabs}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# go.mod may declare "1.27" with no patch level; resolve it to the newest release.
go_toolchain_version() {
    local declared
    declared="$(grep -m1 '^go ' "$1" 2>/dev/null | awk '{print $2}')"
    [[ -n "$declared" ]] || return 1
    if [[ "$declared" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        printf '%s' "$declared"
        return
    fi
    [[ "$declared" =~ ^[0-9]+\.[0-9]+$ ]] || return 1
    curl -fsSL 'https://go.dev/dl/?mode=json&include=all' \
        | grep -o "\"version\": *\"go${declared//./\\.}\.[0-9]*\"" \
        | grep -o '[0-9][0-9.]*' \
        | sort -t. -k3,3n \
        | tail -1
}

if [ $# -lt 1 ]; then
    error "Usage: $0 <package-dir> [ubuntu-series]"
    echo
    echo "Arguments:"
    echo "  package-dir     : Path to package directory (e.g., ../dms)"
    echo "  ubuntu-series   : Ubuntu series (optional, default: noble)"
    echo "                    Options: noble, jammy, oracular, mantic, resolute, stonking"
    echo
    echo "Examples:"
    echo "  $0 ../dms resolute"
    echo "  $0 ../dms stonking"
    echo "  $0 ../dms-git resolute"
    echo "  $0 ../dms-git stonking"
    exit 1
fi

PACKAGE_DIR="$1"
UBUNTU_SERIES="${2:-noble}"

if [ ! -d "$PACKAGE_DIR" ]; then
    error "Package directory not found: $PACKAGE_DIR"
    exit 1
fi

if [ ! -d "$PACKAGE_DIR/debian" ]; then
    error "No debian/ directory found in $PACKAGE_DIR"
    exit 1
fi

PACKAGE_DIR=$(cd "$PACKAGE_DIR" && pwd)
PACKAGE_NAME=$(basename "$PACKAGE_DIR")
PACKAGE_PARENT=$(dirname "$PACKAGE_DIR")

# Choose temp directory: use /tmp in CI, ~/tmp locally (keeps artifacts out of repo)
if [[ -n "${GITHUB_ACTIONS:-}" ]] || [[ -n "${CI:-}" ]]; then
    TEMP_BASE="/tmp"
else
    TEMP_BASE="$HOME/tmp"
    mkdir -p "$TEMP_BASE"
fi

TEMP_WORK_DIR=$(mktemp -d "$TEMP_BASE/ppa_build_work_XXXXXX")

# Cleanup function for temp directories
cleanup_temp_dirs() {
    if [[ -z "${PPA_UPLOAD_SCRIPT:-}" ]] && [[ -d "${TEMP_WORK_DIR:-}" ]]; then
        rm -rf "$TEMP_WORK_DIR"
    fi

    if [[ -d "${TEMP_CLONE:-}" ]]; then
        rm -rf "$TEMP_CLONE"
    fi

    for temp_dir in "$TEMP_BASE"/ppa_clone_* "$TEMP_BASE"/ppa_tag_*; do
        if [[ -d "$temp_dir" ]]; then
            rm -rf "$temp_dir" 2>/dev/null || true
        fi
    done
}

trap cleanup_temp_dirs EXIT

info "Building source package for: $PACKAGE_NAME"
info "Package directory: $PACKAGE_DIR"
info "Working directory: $TEMP_WORK_DIR"
info "Target Ubuntu series: $UBUNTU_SERIES"
REQUIRED_FILES=(
    "debian/control"
    "debian/rules"
    "debian/changelog"
    "debian/copyright"
    "debian/source/format"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$PACKAGE_DIR/$file" ]; then
        error "Required file missing: $file"
        exit 1
    fi
done

# Verify GPG key is set up
info "Checking GPG key setup..."
if ! gpg --list-secret-keys &>/dev/null; then
    error "No GPG secret keys found. Please set up GPG first!"
    error "See GPG_SETUP.md for instructions"
    exit 1
fi

success "GPG key found"

# Function to get PPA name from package name
get_ppa_name() {
    local pkg="$1"
    case "$pkg" in
        dms) echo "dms" ;;
        dms-git) echo "dms-git" ;;
        *) echo "" ;;
    esac
}

# Parameters:
#   $1 = PPA_NAME
#   $2 = SOURCE_NAME
#   $3 = VERSION
#   $4 = CHECK_MODE Exact version match, "commit" = check commit hash (default)
check_ppa_version_exists() {
    local PPA_NAME="$1"
    local SOURCE_NAME="$2"
    local VERSION="$3"
    local CHECK_MODE="${4:-commit}"
    local DISTRO_SERIES="${5:-}"

    # Query Launchpad API (optionally scoped to one Ubuntu series so the same version can ship to resolute and stonking)
    local API_URL="https://api.launchpad.net/1.0/~${PPA_OWNER}/+archive/ubuntu/$PPA_NAME?ws.op=getPublishedSources&source_name=$SOURCE_NAME&status=Published"
    if [[ -n "$DISTRO_SERIES" ]]; then
        API_URL+="&distro_series=https://api.launchpad.net/1.0/ubuntu/${DISTRO_SERIES}"
    fi
    PPA_VERSION=$(curl -s "$API_URL" \
        | grep -oP '"source_package_version":\s*"\K[^"]+' | head -1 || echo "")

    if [[ -n "$PPA_VERSION" ]]; then
        # For git packages with "commit" mode, check if same commit already exists
        if [[ "$CHECK_MODE" == "commit" ]] && [[ "$SOURCE_NAME" == *"-git" ]]; then
            # Extract commit hash from versions (e.g., 79794d34 from 1.0.2+git2546.79794d34ppa2)
            PPA_COMMIT=$(echo "$PPA_VERSION" | grep -oP '\.[a-f0-9]{8}(ppa[0-9]+)?$' | grep -oP '[a-f0-9]{8}' || echo "")
            NEW_COMMIT=$(echo "$VERSION" | grep -oP '\.[a-f0-9]{8}(ppa[0-9]+)?$' | grep -oP '[a-f0-9]{8}' || echo "")

            if [[ -n "$PPA_COMMIT" && -n "$NEW_COMMIT" && "$PPA_COMMIT" == "$NEW_COMMIT" ]]; then
                warn "Commit $NEW_COMMIT already exists in PPA (current version: $PPA_VERSION)"
                return 0
            fi
        fi

        # Exact version match check (always performed)
        if [[ "$PPA_VERSION" == "$VERSION" ]]; then
            warn "Version $VERSION already exists in PPA"
            return 0
        fi
    else
        warn "Could not fetch PPA version (API may be unavailable), proceeding anyway"
        return 1
    fi
    return 1
}

if ! command -v debuild &>/dev/null; then
    error "debuild not found. Install devscripts:"
    error "  sudo dnf install devscripts"
    exit 1
fi

cd "$PACKAGE_DIR"
CHANGELOG_VERSION=$(dpkg-parsechangelog -S Version)
SOURCE_NAME=$(dpkg-parsechangelog -S Source)

info "Source package: $SOURCE_NAME"
info "Version: $CHANGELOG_VERSION"

CHANGELOG_SERIES=$(dpkg-parsechangelog -S Distribution)
if [ "$CHANGELOG_SERIES" != "$UBUNTU_SERIES" ] && [ "$CHANGELOG_SERIES" != "UNRELEASED" ]; then
    warn "Changelog targets '$CHANGELOG_SERIES' but building for '$UBUNTU_SERIES'"
    warn "Consider updating changelog with: dch -r '' -D $UBUNTU_SERIES"
fi

info "Copying package to working directory..."
cp -r "$PACKAGE_DIR" "$TEMP_WORK_DIR/"
WORK_PACKAGE_DIR="$TEMP_WORK_DIR/$PACKAGE_NAME"

if [ -f "$WORK_PACKAGE_DIR/debian/files" ]; then
    info "Removing old debian/files build artifact..."
    rm -f "$WORK_PACKAGE_DIR/debian/files"
fi

cd "$WORK_PACKAGE_DIR"
get_latest_tag() {
    local repo="$1"
    # Get the latest tag, sorted by version
    git ls-remote --tags --refs --sort='-v:refname' "https://github.com/$repo.git" | head -n1 | awk -F/ '{print $NF}' | sed 's/^v//'
}

IS_GIT_PACKAGE=false
GIT_REPO=""
SOURCE_DIR=""

if [[ "$PACKAGE_NAME" == *"-git" ]]; then
    IS_GIT_PACKAGE=true
fi

if grep -q "git clone" debian/rules 2>/dev/null; then
    IS_GIT_PACKAGE=true
    GIT_URL=$(grep -o "git clone.*https://github.com/[^/]*/[^/]*\.git" debian/rules 2>/dev/null | head -1 | sed 's/.*github\.com\///' | sed 's/\.git.*//' || echo "")
    if [ -n "$GIT_URL" ]; then
        GIT_REPO="$GIT_URL"
    fi
fi
case "$PACKAGE_NAME" in
dms-git)
    IS_GIT_PACKAGE=true
    GIT_REPO="duxlabs-dev/dux-shell"
    SOURCE_DIR="dms-git-repo"
    ;;
dms)
    GIT_REPO="duxlabs-dev/dux-shell"
    ;;
dux-search)
    GIT_REPO="duxlabs-dev/dux-search"
    ;;
dux-gop)
    GIT_REPO="duxlabs-dev/dux-gop"
    ;;
esac

# Handle stable packages - update changelog FIRST before downloads
if [ "$IS_GIT_PACKAGE" = false ] && [ -n "$GIT_REPO" ]; then
    info "Detected stable package: $PACKAGE_NAME"
    info "Fetching latest tag from $GIT_REPO..."

    LATEST_TAG=$(get_latest_tag "$GIT_REPO")
    if [ -n "$LATEST_TAG" ]; then
        SOURCE_FORMAT=$(head -1 debian/source/format 2>/dev/null || echo "3.0 (quilt)")
        CURRENT_VERSION=$(dpkg-parsechangelog -S Version 2>/dev/null || echo "")
        if [[ -n "${REBUILD_RELEASE:-}" ]]; then
            PPA_NUM=$REBUILD_RELEASE
            info "Using REBUILD_RELEASE=$REBUILD_RELEASE for PPA number"
        else
            PPA_NUM=1
        fi

        if [[ "$SOURCE_FORMAT" == *"native"* ]]; then
            BASE_VERSION="${LATEST_TAG}"
            NEW_VERSION="${BASE_VERSION}ppa${PPA_NUM}"
        else
            BASE_VERSION="${LATEST_TAG}-1"
            NEW_VERSION="${BASE_VERSION}ppa${PPA_NUM}"
        fi

        # Check if this version already exists in PPA (for stable packages, use exact match)
        PPA_NAME=$(get_ppa_name "$PACKAGE_NAME")
        if [[ -n "$PPA_NAME" ]]; then
            info "Checking if version $NEW_VERSION already exists in PPA..."
            if [[ -z "${REBUILD_RELEASE:-}" ]]; then
                if check_ppa_version_exists "$PPA_NAME" "$SOURCE_NAME" "${BASE_VERSION}ppa1" "exact" "$UBUNTU_SERIES"; then
                    error "==> Error: Version ${BASE_VERSION}ppa1 already exists in PPA $PPA_NAME"
                    error "    To rebuild with a different release number, use:"
                    error "      ./distro/scripts/ppa-upload.sh $PACKAGE_NAME 2"
                    exit 1
                fi
            else
                if check_ppa_version_exists "$PPA_NAME" "$SOURCE_NAME" "$NEW_VERSION" "exact" "$UBUNTU_SERIES"; then
                    error "==> Error: Version $NEW_VERSION already exists in PPA $PPA_NAME"
                    NEXT_NUM=$((REBUILD_RELEASE + 1))
                    error "    To rebuild with a different release number, use:"
                    error "      ./distro/scripts/ppa-upload.sh $PACKAGE_NAME $NEXT_NUM"
                    exit 1
                fi
            fi
        fi

        if [ "$CURRENT_VERSION" != "$NEW_VERSION" ]; then
            if [ "$PPA_NUM" -gt 1 ]; then
                info "Updating changelog for rebuild (PPA number incremented to $PPA_NUM)"
            else
                info "Updating changelog to latest tag: $LATEST_TAG"
            fi
            if [ "$PPA_NUM" -gt 1 ]; then
                CHANGELOG_MSG="Rebuild for packaging fixes (ppa${PPA_NUM})"
            else
                CHANGELOG_MSG="Upstream release ${LATEST_TAG}"
            fi

            # Single changelog entry (full history available on Launchpad)
            cat >debian/changelog <<EOF
${SOURCE_NAME} (${NEW_VERSION}) ${UBUNTU_SERIES}; urgency=medium

  * ${CHANGELOG_MSG}

 -- Avenge Media <AvengeMedia.US@gmail.com>  $(date -R)
EOF
            success "Version updated to $NEW_VERSION"
            CHANGELOG_VERSION=$(dpkg-parsechangelog -S Version)

            # Note: No longer writing back to repository (changelog stays as template)
        else
            info "Version already at latest tag: $LATEST_TAG"
        fi
    else
        warn "Could not determine latest tag for $GIT_REPO, using existing version"
    fi

    # Download binaries/source using the updated version from changelog
    VERSION=$(dpkg-parsechangelog -S Version | sed 's/-[^-]*$//' | sed 's/ppa[0-9]*$//')

    case "$PACKAGE_NAME" in
    dms)
        info "Downloading pre-built binaries and source for dms..."
        if [ ! -f "dms-distropkg-amd64.gz" ]; then
            info "Downloading dms binary for amd64..."
            if wget -O dms-distropkg-amd64.gz "https://github.com/duxlabs-dev/dux-shell/releases/download/v${VERSION}/dms-distropkg-amd64.gz"; then
                success "amd64 binary downloaded"
            else
                error "Failed to download dms-distropkg-amd64.gz"
                exit 1
            fi
        fi

        if [ ! -f "dms-distropkg-arm64.gz" ]; then
            info "Downloading dms binary for arm64..."
            # Try to download arm64 binary, but don't fail if it doesn't exist (yet)
            if wget -O dms-distropkg-arm64.gz "https://github.com/duxlabs-dev/dux-shell/releases/download/v${VERSION}/dms-distropkg-arm64.gz"; then
                success "arm64 binary downloaded"
            else
                warn "Failed to download dms-distropkg-arm64.gz (skipping)"
                rm -f dms-distropkg-arm64.gz
            fi
        fi

        if [ ! -f "dms-source.tar.gz" ]; then
            info "Downloading dms source for QML files..."
            if wget -O dms-source.tar.gz "https://github.com/duxlabs-dev/dux-shell/releases/download/v${VERSION}/dms-source.tar.gz"; then
                success "source tarball downloaded"
            else
                error "Failed to download dms-source.tar.gz"
                exit 1
            fi
        fi
        ;;
    esac
fi

# Handle git packages
if [ "$IS_GIT_PACKAGE" = true ] && [ -n "$GIT_REPO" ]; then
    info "Detected git package: $PACKAGE_NAME"

    if [ -z "$SOURCE_DIR" ]; then
        BASE_NAME=$(echo "$PACKAGE_NAME" | sed 's/-git$//')
        if [ -d "${BASE_NAME}-source" ] 2>/dev/null; then
            SOURCE_DIR="${BASE_NAME}-source"
        elif [ -d "${BASE_NAME}-repo" ] 2>/dev/null; then
            SOURCE_DIR="${BASE_NAME}-repo"
        elif [ -d "$BASE_NAME" ] 2>/dev/null; then
            SOURCE_DIR="$BASE_NAME"
        else
            SOURCE_DIR="${BASE_NAME}-source"
        fi
    fi

    info "Cloning $GIT_REPO from GitHub (getting latest commit info)..."
    TEMP_CLONE=$(mktemp -d "$TEMP_BASE/ppa_clone_XXXXXX")
    if git clone --recurse-submodules --shallow-submodules "https://github.com/$GIT_REPO.git" "$TEMP_CLONE"; then
        GIT_COMMIT_HASH=$(cd "$TEMP_CLONE" && git rev-parse --short HEAD)
        GIT_COMMIT_COUNT=$(cd "$TEMP_CLONE" && git rev-list --count HEAD)
        UPSTREAM_VERSION=$(cd "$TEMP_CLONE" && git tag -l "v*" | sed 's/^v//' | sort -V | tail -1)
        if [ -z "$UPSTREAM_VERSION" ]; then
            UPSTREAM_VERSION=$(cd "$TEMP_CLONE" && git tag -l | grep -E '^[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -1)
        fi
        if [ -z "$UPSTREAM_VERSION" ]; then
            UPSTREAM_VERSION=$(cd "$TEMP_CLONE" && git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "0.0.1")
        fi
        if [ -z "$GIT_COMMIT_COUNT" ] || [ "$GIT_COMMIT_COUNT" = "0" ]; then
            error "Failed to get commit count from $GIT_REPO"
            rm -rf "$TEMP_CLONE"
            exit 1
        fi

        if [ -z "$GIT_COMMIT_HASH" ]; then
            error "Failed to get commit hash from $GIT_REPO"
            rm -rf "$TEMP_CLONE"
            exit 1
        fi

        success "Got commit info: $GIT_COMMIT_COUNT ($GIT_COMMIT_HASH), upstream: $UPSTREAM_VERSION"

        # Build base version (without ppa suffix yet)
        BASE_VERSION="${UPSTREAM_VERSION}+git${GIT_COMMIT_COUNT}.${GIT_COMMIT_HASH}"

        # EARLY VERSION CHECK
        PPA_NAME=$(get_ppa_name "$PACKAGE_NAME")
        if [[ -n "$PPA_NAME" ]]; then
            if [[ -z "${REBUILD_RELEASE:-}" ]]; then
                info "Checking if commit $GIT_COMMIT_HASH already exists in PPA..."
                if check_ppa_version_exists "$PPA_NAME" "$SOURCE_NAME" "${BASE_VERSION}ppa1" "commit" "$UBUNTU_SERIES"; then
                    error "==> Error: This commit is already uploaded to PPA"
                    error "    The same git commit ($GIT_COMMIT_HASH) already exists in PPA."
                    error "    To rebuild the same commit, specify a rebuild number:"
                    error "      ./distro/scripts/ppa-upload.sh $PACKAGE_NAME 2"
                    error "      ./distro/scripts/ppa-upload.sh $PACKAGE_NAME 3"
                    error "    Or with build script directly:"
                    error "      REBUILD_RELEASE=2 ./distro/scripts/ppa-build.sh $PACKAGE_DIR"
                    error "    Or push a new commit first, then run:"
                    error "      ./distro/scripts/ppa-upload.sh $PACKAGE_NAME"
                    rm -rf "$TEMP_CLONE"
                    exit 1
                fi
                PPA_NUM=1
                info "Using PPA number $PPA_NUM"
            else
                PPA_NUM=$REBUILD_RELEASE
                NEW_VERSION="${BASE_VERSION}ppa${PPA_NUM}"
                info "Checking if version $NEW_VERSION already exists in PPA..."
                if check_ppa_version_exists "$PPA_NAME" "$SOURCE_NAME" "$NEW_VERSION" "exact" "$UBUNTU_SERIES"; then
                    error "==> Error: Version $NEW_VERSION already exists in PPA"
                    error "    This exact version (including ppa${PPA_NUM}) is already uploaded."
                    NEXT_NUM=$((PPA_NUM + 1))
                    error "    To rebuild with a different release number, try incrementing:"
                    error "      ./distro/scripts/ppa-upload.sh $PACKAGE_NAME $NEXT_NUM"
                    error "    Or with build script directly:"
                    error "      REBUILD_RELEASE=$NEXT_NUM ./distro/scripts/ppa-build.sh $PACKAGE_DIR"
                    rm -rf "$TEMP_CLONE"
                    exit 1
                fi
                info "Using REBUILD_RELEASE=$REBUILD_RELEASE for PPA number"
            fi
        else
            # No PPA name found, use default
            if [[ -n "${REBUILD_RELEASE:-}" ]]; then
                PPA_NUM=$REBUILD_RELEASE
                info "Using REBUILD_RELEASE=$REBUILD_RELEASE for PPA number"
            else
                PPA_NUM=1
                info "Using PPA number $PPA_NUM"
            fi
        fi

        NEW_VERSION="${BASE_VERSION}ppa${PPA_NUM}"
        info "Updating changelog with git commit info..."
        CURRENT_VERSION=$(dpkg-parsechangelog -S Version 2>/dev/null || echo "")

        # Single changelog entry (git snapshots don't need history)
        cat >debian/changelog <<EOF
${SOURCE_NAME} (${NEW_VERSION}) ${UBUNTU_SERIES}; urgency=medium

  * Git snapshot (commit ${GIT_COMMIT_COUNT}: ${GIT_COMMIT_HASH})

 -- Avenge Media <AvengeMedia.US@gmail.com>  $(date -R)
EOF
        success "Version updated to $NEW_VERSION"
        CHANGELOG_VERSION=$(dpkg-parsechangelog -S Version)

        # Note: No longer writing back to repository (changelog stays as template)

        rm -rf "$SOURCE_DIR"
        cp -r "$TEMP_CLONE" "$SOURCE_DIR"

        if [ "$PACKAGE_NAME" = "dms-git" ]; then
            info "Saving version info to .dms-version for build process..."
            echo "VERSION=${UPSTREAM_VERSION}+git${GIT_COMMIT_COUNT}.${GIT_COMMIT_HASH}" >"$SOURCE_DIR/.dms-version"
            echo "COMMIT=${GIT_COMMIT_HASH}" >>"$SOURCE_DIR/.dms-version"
            success "Version info saved: ${UPSTREAM_VERSION}+git${GIT_COMMIT_COUNT}.${GIT_COMMIT_HASH}"

            info "Vendoring Go dependencies for offline build..."
            cd "$SOURCE_DIR/core"
            go mod vendor

            if [ ! -d "vendor" ]; then
                error "Failed to vendor Go dependencies"
                exit 1
            fi

            success "Go dependencies vendored successfully"

            # Launchpad has no network and distro Go lags go.mod; bundle the exact toolchain
            GO_TOOLCHAIN_VERSION=$(go_toolchain_version go.mod || true)
            if [ -z "$GO_TOOLCHAIN_VERSION" ]; then
                error "Could not resolve a Go toolchain release from core/go.mod"
                exit 1
            fi
            GO_TOOLCHAIN_CACHE="${GO_TOOLCHAIN_CACHE:-$HOME/.cache/dms-ppa-go-toolchain}/$GO_TOOLCHAIN_VERSION"
            mkdir -p "$GO_TOOLCHAIN_CACHE"
            for GO_ARCH in amd64 arm64; do
                GO_TARBALL="go${GO_TOOLCHAIN_VERSION}.linux-${GO_ARCH}.tar.gz"
                if [ ! -f "$GO_TOOLCHAIN_CACHE/$GO_TARBALL" ]; then
                    info "Downloading Go ${GO_TOOLCHAIN_VERSION} (${GO_ARCH})..."
                    if ! curl -fsSL -o "$GO_TOOLCHAIN_CACHE/$GO_TARBALL.tmp" "https://go.dev/dl/$GO_TARBALL"; then
                        rm -f "$GO_TOOLCHAIN_CACHE/$GO_TARBALL.tmp"
                        error "Failed to download https://go.dev/dl/$GO_TARBALL"
                        exit 1
                    fi
                    mv "$GO_TOOLCHAIN_CACHE/$GO_TARBALL.tmp" "$GO_TOOLCHAIN_CACHE/$GO_TARBALL"
                fi
                cp -f "$GO_TOOLCHAIN_CACHE/$GO_TARBALL" "$WORK_PACKAGE_DIR/$SOURCE_DIR/$GO_TARBALL"
            done
            success "Bundled Go ${GO_TOOLCHAIN_VERSION} toolchains"
            cd "$PACKAGE_DIR"
        fi

        rm -rf "$SOURCE_DIR/.git"
        rm -rf "$TEMP_CLONE"

        success "Source prepared for packaging"
    else
        error "Failed to clone $GIT_REPO"
        rm -rf "$TEMP_CLONE"
        exit 1
    fi
fi

# Handle packages that need pre-built binaries downloaded
cd "$WORK_PACKAGE_DIR"
case "$PACKAGE_NAME" in
dux-search)
    info "Downloading pre-built binaries for dux-search..."
    VERSION=$(dpkg-parsechangelog -S Version | sed 's/-[^-]*$//' | sed 's/ppa[0-9]*$//')

    if [ ! -f "dsearch-amd64" ]; then
        info "Downloading dsearch binary for amd64..."
        if wget -O dsearch-amd64.gz "https://github.com/duxlabs-dev/dux-search/releases/download/v${VERSION}/dsearch-linux-amd64.gz"; then
            gunzip dsearch-amd64.gz
            chmod +x dsearch-amd64
            success "amd64 binary downloaded"
        else
            error "Failed to download dsearch-amd64.gz"
            exit 1
        fi
    fi

    if [ ! -f "dsearch-arm64" ]; then
        info "Downloading dsearch binary for arm64..."
        if wget -O dsearch-arm64.gz "https://github.com/duxlabs-dev/dux-search/releases/download/v${VERSION}/dsearch-linux-arm64.gz"; then
            gunzip dsearch-arm64.gz
            chmod +x dsearch-arm64
            success "arm64 binary downloaded"
        else
            error "Failed to download dsearch-arm64.gz"
            exit 1
        fi
    fi
    ;;
dux-gop)
    if [ ! -f "dgop" ]; then
        warn "dgop binary not found - should be committed to repo"
    fi
    ;;
esac

cd "$WORK_PACKAGE_DIR"

info "Building source package..."
echo

SOURCE_FORMAT=$(head -1 "$WORK_PACKAGE_DIR/debian/source/format" 2>/dev/null || echo "3.0 (quilt)")

# Native format packages don't use orig tarballs - they include everything in one tarball
if [[ "$SOURCE_FORMAT" == *"native"* ]]; then
    info "Native format detected - including all source files (no orig tarball needed)"
    DEBUILD_SOURCE_FLAG="-sa"
elif [ -f "$PACKAGE_PARENT/${PACKAGE_NAME}_${VERSION%.ppa*}.orig.tar.xz" ]; then
    ORIG_TARBALL="${PACKAGE_NAME}_${VERSION%.ppa*}.orig.tar.xz"
    info "Found existing orig tarball in $PACKAGE_PARENT, using -sd (debian changes only)"
    cp "$PACKAGE_PARENT/$ORIG_TARBALL" "$TEMP_WORK_DIR/"
    DEBUILD_SOURCE_FLAG="-sd"
else
    info "No existing orig tarball found, using -sa (include original source)"
    DEBUILD_SOURCE_FLAG="-sa"
fi

# -d skips dependency checking (we're building on Fedora, not Ubuntu)
# -k: debsign otherwise picks the key from the changelog maintainer, which need not match the CI key
if yes | DEBIAN_FRONTEND=noninteractive debuild -S $DEBUILD_SOURCE_FLAG -d ${DEBSIGN_KEYID:+-k"$DEBSIGN_KEYID"}; then
    echo
    success "Source package built successfully!"

    TEMP_MARKER_FILE="$PACKAGE_PARENT/.ppa_build_temp_${PACKAGE_NAME}"
    echo "PPA_BUILD_TEMP_DIR=$TEMP_WORK_DIR" > "$TEMP_MARKER_FILE"

    if [[ -z "${PPA_UPLOAD_SCRIPT:-}" ]] && ! pgrep -f "ppa-upload.sh" >/dev/null 2>&1; then
        info "Copying build artifacts to $PACKAGE_PARENT (standalone build)..."
        cp -v "$TEMP_WORK_DIR"/"${SOURCE_NAME}"_"${CHANGELOG_VERSION}"* "$PACKAGE_PARENT/" 2>/dev/null || true
        info "Generated files in $PACKAGE_PARENT:"
        ls -lh "$PACKAGE_PARENT"/"${SOURCE_NAME}"_"${CHANGELOG_VERSION}"* 2>/dev/null || true
    fi

    # Show what to do next
    echo
    info "Next steps:"
    echo "  1. Review the source package:"
    echo "     cd $PACKAGE_PARENT"
    echo "     ls -lh ${SOURCE_NAME}_${CHANGELOG_VERSION}*"
    echo
    echo "  2. Upload to PPA (stable):"
    echo "     dput ppa:${PPA_OWNER}/dms ${SOURCE_NAME}_${CHANGELOG_VERSION}_source.changes"
    echo
    echo "  3. Or upload to PPA (nightly):"
    echo "     dput ppa:${PPA_OWNER}/dms-git ${SOURCE_NAME}_${CHANGELOG_VERSION}_source.changes"
    echo
    echo "  4. Or use the upload script:"
    echo "     ./upload-ppa.sh $PACKAGE_PARENT/${SOURCE_NAME}_${CHANGELOG_VERSION}_source.changes dms"

else
    error "Source package build failed!"
    exit 1
fi
