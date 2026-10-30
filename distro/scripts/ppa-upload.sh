#!/bin/bash
# Build and upload PPA package with automatic cleanup
# Usage: ./ppa-upload.sh [package-name] [ppa-name] [ubuntu-series] [rebuild-number] [--keep-builds] [--rebuild=N]
#
# Examples:
#   ./ppa-upload.sh dms                    # Upload to resolute + stonking (default)
#   ./ppa-upload.sh dms 2                 # Native: resolute ppa2, stonking ppa3 (auto +1 on second series)
#   ./ppa-upload.sh dms --rebuild=2       # Rebuild with ppa2 (flag syntax)
#   ./ppa-upload.sh dms-git               # Single package (both series)
#   ./ppa-upload.sh all                   # All packages (each to both series)
#   ./ppa-upload.sh dms resolute          # 26.04 LTS only (same as "dms dms resolute")
#   ./ppa-upload.sh dms stonking          # 26.10 only
#   ./ppa-upload.sh dms dms resolute      # Explicit PPA name + one series (optional form)
#   ./ppa-upload.sh dms dms resolute 2    # One series + rebuild number
#   ./ppa-upload.sh distro/ubuntu/dms dms # Path-style (backward compatible)

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

AVAILABLE_PACKAGES=(dms dms-git)
export PPA_OWNER="${PPA_OWNER:-duxlabs}"

KEEP_BUILDS=false
REBUILD_RELEASE=""
POSITIONAL_ARGS=()
for arg in "$@"; do
    case "$arg" in
        --keep-builds) KEEP_BUILDS=true ;;
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

PACKAGE_INPUT="${POSITIONAL_ARGS[0]:-}"
PPA_NAME_INPUT="${POSITIONAL_ARGS[1]:-}"
UBUNTU_SERIES_RAW="${POSITIONAL_ARGS[2]:-}"

if [[ ${#POSITIONAL_ARGS[@]} -gt 0 ]]; then
    LAST_INDEX=$((${#POSITIONAL_ARGS[@]} - 1))
    LAST_ARG="${POSITIONAL_ARGS[$LAST_INDEX]}"
    if [[ "$LAST_ARG" =~ ^[0-9]+$ ]] && [[ -z "$REBUILD_RELEASE" ]]; then
        # Last argument is a number and no --rebuild flag was used
        # Use it as rebuild release and remove from positional args
        REBUILD_RELEASE="$LAST_ARG"
        POSITIONAL_ARGS=("${POSITIONAL_ARGS[@]:0:$LAST_INDEX}")
        PACKAGE_INPUT="${POSITIONAL_ARGS[0]:-}"
        PPA_NAME_INPUT="${POSITIONAL_ARGS[1]:-}"
        UBUNTU_SERIES_RAW="${POSITIONAL_ARGS[2]:-}"
    fi
fi

# Shorthand: "dms resolute" / "dms stonking" (package + series; PPA inferred — no need for "dms dms resolute")
if [[ ${#POSITIONAL_ARGS[@]} -eq 2 ]] && [[ "${POSITIONAL_ARGS[1]}" == "resolute" || "${POSITIONAL_ARGS[1]}" == "stonking" ]]; then
    PACKAGE_INPUT="${POSITIONAL_ARGS[0]}"
    PPA_NAME_INPUT=""
    UBUNTU_SERIES_RAW="${POSITIONAL_ARGS[1]}"
fi

SERIES_LIST=()
if [[ -z "$UBUNTU_SERIES_RAW" ]]; then
    SERIES_LIST=(resolute stonking)
elif [[ "$UBUNTU_SERIES_RAW" == "resolute" || "$UBUNTU_SERIES_RAW" == "stonking" ]]; then
    SERIES_LIST=("$UBUNTU_SERIES_RAW")
else
    error "Invalid Ubuntu series: $UBUNTU_SERIES_RAW (use resolute, stonking, or omit for both)"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BUILD_SCRIPT="$SCRIPT_DIR/ppa-build.sh"

if [ ! -f "$BUILD_SCRIPT" ]; then
    error "Build script not found: $BUILD_SCRIPT"
    exit 1
fi

get_ppa_name() {
    local pkg="$1"
    case "$pkg" in
        dms) echo "dms" ;;
        dms-git) echo "dms-git" ;;
        *) echo "" ;;
    esac
}

# Support both path-style and name-style arguments
PACKAGE_DIR=""
PACKAGE_NAME=""
PPA_NAME=""

if [[ -n "$PACKAGE_INPUT" ]] && [[ "$PACKAGE_INPUT" == *"/"* ]]; then
    # Path-style argument (backward compatibility)
    if [[ -d "$PACKAGE_INPUT" ]]; then
        PACKAGE_DIR="$(cd "$PACKAGE_INPUT" && pwd)"
    elif [[ -d "$REPO_ROOT/$PACKAGE_INPUT" ]]; then
        PACKAGE_DIR="$(cd "$REPO_ROOT/$PACKAGE_INPUT" && pwd)"
    else
        error "Package directory not found: $PACKAGE_INPUT"
        exit 1
    fi
    PACKAGE_NAME=$(basename "$PACKAGE_DIR")
    PPA_NAME="${PPA_NAME_INPUT:-$(get_ppa_name "$PACKAGE_NAME")}"
    if [[ -z "$PPA_NAME" ]]; then
        error "Could not determine PPA name for package: $PACKAGE_NAME"
        error "Please specify PPA name as second argument"
        exit 1
    fi
    info "Using path-style argument: $PACKAGE_DIR"
elif [[ -n "$PACKAGE_INPUT" ]] && [[ "$PACKAGE_INPUT" == "all" ]]; then
    echo ""
    info "Building and uploading all packages..."
    FAILED_PACKAGES=()
    for pkg in "${AVAILABLE_PACKAGES[@]}"; do
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        info "Processing $pkg..."
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        BUILD_ARGS=("$pkg")
        [[ -n "$PPA_NAME_INPUT" ]] && BUILD_ARGS+=("$PPA_NAME_INPUT")
        if [[ ${#SERIES_LIST[@]} -eq 1 ]]; then
            BUILD_ARGS+=("${SERIES_LIST[0]}")
        fi
        [[ -n "$REBUILD_RELEASE" ]] && BUILD_ARGS+=("$REBUILD_RELEASE")
        [[ "$KEEP_BUILDS" == "true" ]] && BUILD_ARGS+=("--keep-builds")
        if ! "$0" "${BUILD_ARGS[@]}"; then
            FAILED_PACKAGES+=("$pkg")
            error "$pkg failed to upload"
        fi
    done
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if [[ ${#FAILED_PACKAGES[@]} -eq 0 ]]; then
        success "All packages uploaded successfully!"
    else
        error "Some packages failed: ${FAILED_PACKAGES[*]}"
        exit 1
    fi
    exit 0
elif [[ -n "$PACKAGE_INPUT" ]]; then
    VALID_PACKAGE=false
    for pkg in "${AVAILABLE_PACKAGES[@]}"; do
        if [[ "$PACKAGE_INPUT" == "$pkg" ]]; then
            VALID_PACKAGE=true
            break
        fi
    done

    if [[ "$VALID_PACKAGE" != "true" ]]; then
        error "Unknown package: $PACKAGE_INPUT"
        echo "Available packages: ${AVAILABLE_PACKAGES[*]}"
        exit 1
    fi

    PACKAGE_NAME="$PACKAGE_INPUT"
    PACKAGE_DIR="$REPO_ROOT/distro/ubuntu/$PACKAGE_NAME"
    PPA_NAME="${PPA_NAME_INPUT:-$(get_ppa_name "$PACKAGE_NAME")}"
else
    echo "Available packages:"
    echo ""
    for i in "${!AVAILABLE_PACKAGES[@]}"; do
        echo "  $((i+1)). ${AVAILABLE_PACKAGES[$i]}"
    done
    echo "  a. all"
    echo ""
    read -rp "Select package (1-${#AVAILABLE_PACKAGES[@]}, a): " selection

    if [[ "$selection" == "a" ]] || [[ "$selection" == "all" ]]; then
        PACKAGE_INPUT="all"
        BUILD_ARGS=("all")
        [[ -n "$PPA_NAME_INPUT" ]] && BUILD_ARGS+=("$PPA_NAME_INPUT")
        [[ -n "$REBUILD_RELEASE" ]] && BUILD_ARGS+=("$REBUILD_RELEASE")
        [[ "$KEEP_BUILDS" == "true" ]] && BUILD_ARGS+=("--keep-builds")
        exec "$0" "${BUILD_ARGS[@]}"
    elif [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 ]] && [[ "$selection" -le ${#AVAILABLE_PACKAGES[@]} ]]; then
        PACKAGE_NAME="${AVAILABLE_PACKAGES[$((selection-1))]}"
        PACKAGE_DIR="$REPO_ROOT/distro/ubuntu/$PACKAGE_NAME"
        PPA_NAME="${PPA_NAME_INPUT:-$(get_ppa_name "$PACKAGE_NAME")}"
    else
        error "Invalid selection"
        exit 1
    fi
fi

if [ ! -d "$PACKAGE_DIR" ]; then
    error "Package directory not found: $PACKAGE_DIR"
    exit 1
fi

if [ ! -d "$PACKAGE_DIR/debian" ]; then
    error "No debian/ directory found in $PACKAGE_DIR"
    exit 1
fi

PACKAGE_DIR=$(cd "$PACKAGE_DIR" && pwd)
PARENT_DIR=$(dirname "$PACKAGE_DIR")

setup_launchpad_sftp() {
    if [[ -z "${LAUNCHPAD_SSH_PRIVATE_KEY:-}" || -z "${LAUNCHPAD_SSH_LOGIN:-}" ]]; then
        error "LAUNCHPAD_SSH_PRIVATE_KEY and LAUNCHPAD_SSH_LOGIN are required for CI SFTP uploads."
        error "The key's public half must be registered on the Launchpad account named by LAUNCHPAD_SSH_LOGIN."
        exit 1
    fi

    local ssh_dir="$HOME/.ssh"
    local key_file="$ssh_dir/launchpad_ppa"
    local login="$LAUNCHPAD_SSH_LOGIN"
    local strict_host_key_checking="yes"

    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"
    printf '%s\n' "$LAUNCHPAD_SSH_PRIVATE_KEY" > "$key_file"
    chmod 600 "$key_file"

    if ssh-keyscan -H ppa.launchpad.net >> "$ssh_dir/known_hosts" 2>/dev/null; then
        chmod 600 "$ssh_dir/known_hosts"
    else
        warn "Could not prefetch ppa.launchpad.net SSH host key; allowing OpenSSH to trust it on first SFTP connection"
        strict_host_key_checking="accept-new"
    fi

    cat > "$ssh_dir/config" <<EOF
Host ppa.launchpad.net
    HostName ppa.launchpad.net
    User ${login}
    IdentityFile ${key_file}
    IdentitiesOnly yes
    StrictHostKeyChecking ${strict_host_key_checking}
EOF
    chmod 600 "$ssh_dir/config"
}

if [[ ${#SERIES_LIST[@]} -gt 1 ]]; then
    SOURCE_FORMAT_LINE=$(head -1 "$PACKAGE_DIR/debian/source/format" 2>/dev/null || echo "")
    IS_NATIVE_DUAL=false
    if [[ "$SOURCE_FORMAT_LINE" == *"native"* ]]; then
        IS_NATIVE_DUAL=true
        info "Native source format: second series uses PPA suffix +1 (or ppa2 if unset) so both uploads succeed."
    fi
    export REBUILD_RELEASE
    for idx in "${!SERIES_LIST[@]}"; do
        SERIES="${SERIES_LIST[$idx]}"
        if [[ -n "$PACKAGE_INPUT" ]] && [[ "$PACKAGE_INPUT" == *"/"* ]]; then
            ARGS=("$PACKAGE_DIR" "$PPA_NAME" "$SERIES")
        else
            ARGS=("$PACKAGE_NAME" "$PPA_NAME" "$SERIES")
        fi
        if [[ "$IS_NATIVE_DUAL" == true ]]; then
            if [[ "$idx" -eq 0 ]]; then
                [[ -n "${REBUILD_RELEASE:-}" ]] && ARGS+=("$REBUILD_RELEASE")
            else
                if [[ -n "${REBUILD_RELEASE:-}" ]]; then
                    SECOND_PPA=$((REBUILD_RELEASE + 1))
                    ARGS+=("$SECOND_PPA")
                    info "Second series ${SERIES}: using ppa${SECOND_PPA} (native dual-series)"
                else
                    ARGS+=("2")
                    info "Second series ${SERIES}: using ppa2 (native dual-series; first uses default ppa1)"
                fi
            fi
        else
            [[ -n "${REBUILD_RELEASE:-}" ]] && ARGS+=("$REBUILD_RELEASE")
        fi
        [[ "$KEEP_BUILDS" == "true" ]] && ARGS+=("--keep-builds")
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        info "Upload series: $SERIES (of ${SERIES_LIST[*]})"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        "$0" "${ARGS[@]}" || exit 1
    done
    exit 0
fi
UBUNTU_SERIES="${SERIES_LIST[0]}"

info "Building and uploading: $PACKAGE_NAME"
info "Package directory: $PACKAGE_DIR"
info "PPA: ppa:${PPA_OWNER}/$PPA_NAME"
info "Ubuntu series: $UBUNTU_SERIES"
if [[ -n "$REBUILD_RELEASE" ]]; then
    info "Rebuild release number: ppa$REBUILD_RELEASE"
fi
echo

info "Step 1: Building source package..."
if [[ -n "$REBUILD_RELEASE" ]]; then
    export REBUILD_RELEASE
fi
export PPA_UPLOAD_SCRIPT=1
if ! "$BUILD_SCRIPT" "$PACKAGE_DIR" "$UBUNTU_SERIES"; then
    error "Build failed!"
    exit 1
fi

TEMP_DIR_FILE="$PARENT_DIR/.ppa_build_temp_${PACKAGE_NAME}"
if [ -f "$TEMP_DIR_FILE" ]; then
    BUILD_TEMP_DIR=$(grep -oP 'PPA_BUILD_TEMP_DIR=\K.*' "$TEMP_DIR_FILE")
    rm -f "$TEMP_DIR_FILE"
    info "Using build artifacts from temp directory: $BUILD_TEMP_DIR"
    CHANGES_FILE=$(find "$BUILD_TEMP_DIR" -maxdepth 1 -name "${PACKAGE_NAME}_*_source.changes" -type f 2>/dev/null | sort -V | tail -1)
else
    BUILD_TEMP_DIR="$PARENT_DIR"
    CHANGES_FILE=$(find "$PARENT_DIR" -maxdepth 1 -name "${PACKAGE_NAME}_*_source.changes" -type f | sort -V | tail -1)
fi

if [ -z "$CHANGES_FILE" ]; then
    warn "Changes file not found in $BUILD_TEMP_DIR"
    warn "Assuming build was skipped (no changes needed) and exiting successfully."
    exit 0
fi

info "Found changes file: $CHANGES_FILE"
echo

info "Step 2: Uploading to PPA..."

if [ "$PPA_NAME" = "dms" ] || [ "$PPA_NAME" = "dms-git" ]; then
    warn "Using lftp for upload"

    BUILD_DIR=$(dirname "$CHANGES_FILE")
    CHANGES_BASENAME=$(basename "$CHANGES_FILE")
    DSC_FILE="${CHANGES_BASENAME/_source.changes/.dsc}"
    TARBALL="${CHANGES_BASENAME/_source.changes/.tar.xz}"
    BUILDINFO="${CHANGES_BASENAME/_source.changes/_source.buildinfo}"

    # Check all files exist
    MISSING_FILES=()
    [ ! -f "$BUILD_DIR/$DSC_FILE" ] && MISSING_FILES+=("$DSC_FILE")
    [ ! -f "$BUILD_DIR/$TARBALL" ] && MISSING_FILES+=("$TARBALL")
    [ ! -f "$BUILD_DIR/$BUILDINFO" ] && MISSING_FILES+=("$BUILDINFO")

    if [ ${#MISSING_FILES[@]} -gt 0 ]; then
        error "Missing required files:"
        for file in "${MISSING_FILES[@]}"; do
            error "  - $file"
        done
        exit 1
    fi

    info "Uploading files:"
    info "  - $CHANGES_BASENAME"
    info "  - $DSC_FILE"
    info "  - $TARBALL"
    info "  - $BUILDINFO"
    echo

    if [[ -n "${GITHUB_ACTIONS:-}" || -n "${CI:-}" ]] && command -v dput >/dev/null 2>&1; then
        setup_launchpad_sftp
        DPUT_CONFIG=$(mktemp)
        cat >"$DPUT_CONFIG" <<EOF
[${PPA_OWNER}-${PPA_NAME}]
fqdn = ppa.launchpad.net
method = sftp
incoming = ~${PPA_OWNER}/ubuntu/${PPA_NAME}/
login = ${LAUNCHPAD_SSH_LOGIN}
allow_unsigned_uploads = 0
EOF

        info "Using dput for CI upload (SFTP)"
        if dput -c "$DPUT_CONFIG" "${PPA_OWNER}-${PPA_NAME}" "$CHANGES_FILE"; then
            success "Upload successful!"
            rm -f "$DPUT_CONFIG"
        else
            rm -f "$DPUT_CONFIG"
            error "dput upload failed!"
            exit 1
        fi
    else
        LFTP_SCRIPT=$(mktemp)
        cat >"$LFTP_SCRIPT" <<EOF
cd ~${PPA_OWNER}/ubuntu/$PPA_NAME/
lcd $BUILD_DIR
mput $CHANGES_BASENAME
mput $DSC_FILE
mput $TARBALL
mput $BUILDINFO
bye
EOF

        if lftp -d ftp://anonymous:@ppa.launchpad.net <"$LFTP_SCRIPT"; then
            success "Upload successful!"
            rm -f "$LFTP_SCRIPT"
        else
            error "Upload failed!"
            rm -f "$LFTP_SCRIPT"
            exit 1
        fi
    fi
else
    # This branch should not be reached for DMS packages
    # All DMS packages (dms, dms-git) use lftp
    error "Unknown PPA: $PPA_NAME"
    error "DMS packages use lftp for upload. Supported PPAs: dms, dms-git"
    exit 1
fi

echo
success "Package uploaded successfully!"
info "Monitor build progress at:"
echo "  https://launchpad.net/~${PPA_OWNER}/+archive/ubuntu/$PPA_NAME/+packages"
echo

if [ "$KEEP_BUILDS" = "false" ]; then
    info "Step 3: Cleaning up build artifacts..."

    if [ -n "${BUILD_TEMP_DIR:-}" ] && [ "$BUILD_TEMP_DIR" != "$PARENT_DIR" ]; then
        if [ -d "$BUILD_TEMP_DIR" ]; then
            info "Removing temp build directory: $BUILD_TEMP_DIR"
            rm -rf "$BUILD_TEMP_DIR"
        fi
    fi

    rm -f "$PARENT_DIR/.ppa_build_temp_${PACKAGE_NAME}"
    ARTIFACTS=(
        "${PACKAGE_NAME}_*.dsc"
        "${PACKAGE_NAME}_*.tar.xz"
        "${PACKAGE_NAME}_*.tar.gz"
        "${PACKAGE_NAME}_*_source.changes"
        "${PACKAGE_NAME}_*_source.buildinfo"
        "${PACKAGE_NAME}_*_source.build"
    )

    REMOVED=0
    for pattern in "${ARTIFACTS[@]}"; do
        for file in "$PARENT_DIR"/$pattern; do
            if [ -f "$file" ]; then
                rm -f "$file"
                REMOVED=$((REMOVED + 1))
            fi
        done
    done

    case "$PACKAGE_NAME" in
    dux-search)
        if [ -f "$PACKAGE_DIR/dsearch-amd64" ]; then
            rm -f "$PACKAGE_DIR/dsearch-amd64"
            REMOVED=$((REMOVED + 1))
        fi
        if [ -f "$PACKAGE_DIR/dsearch-arm64" ]; then
            rm -f "$PACKAGE_DIR/dsearch-arm64"
            REMOVED=$((REMOVED + 1))
        fi
        ;;
    dms)
        if [ -f "$PACKAGE_DIR/dms-distropkg-amd64.gz" ]; then
            rm -f "$PACKAGE_DIR/dms-distropkg-amd64.gz"
            REMOVED=$((REMOVED + 1))
        fi
        if [ -f "$PACKAGE_DIR/dms-distropkg-arm64.gz" ]; then
            rm -f "$PACKAGE_DIR/dms-distropkg-arm64.gz"
            REMOVED=$((REMOVED + 1))
        fi
        if [ -f "$PACKAGE_DIR/dms-source.tar.gz" ]; then
            rm -f "$PACKAGE_DIR/dms-source.tar.gz"
            REMOVED=$((REMOVED + 1))
        fi
        ;;
    dms-git)
        # Remove git source directory binary
        if [ -d "$PACKAGE_DIR/dms-git-repo" ]; then
            rm -rf "$PACKAGE_DIR/dms-git-repo"
            REMOVED=$((REMOVED + 1))
        fi
        ;;
    esac

    if [ $REMOVED -gt 0 ]; then
        success "Removed $REMOVED build artifact(s)"
    else
        info "No build artifacts to clean up"
    fi
else
    info "Keeping build artifacts (--keep-builds specified)"
    info "Build artifacts in: $PARENT_DIR"
fi

echo
success "Done!"
