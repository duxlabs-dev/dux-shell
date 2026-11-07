#!/usr/bin/env bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Check for root privileges
if [ "$(id -u)" = "0" ]; then
    printf "%bError: This script must not be run as root%b\n" "$RED" "$NC"
    exit 1
fi

# Check if running on Linux
if [ "$(uname)" != "Linux" ]; then
    printf "%bError: This installer only supports Linux systems%b\n" "$RED" "$NC"
    exit 1
fi

# Detect architecture
ARCH=$(uname -m)
case "$ARCH" in
x86_64)
    ARCH="amd64"
    ;;
aarch64)
    ARCH="arm64"
    ;;
*)
    printf "%bError: Unsupported architecture: %s%b\n" "$RED" "$ARCH" "$NC"
    printf "This installer only supports x86_64 (amd64) and aarch64 (arm64) architectures\n"
    exit 1
    ;;
esac

REPO_URL="https://github.com/duxlabs-dev/dux-shell"

# The web redirect has no per-ip quota; api.github.com allows 60 unauthenticated requests per hour per ip
LATEST_VERSION=$(curl -sI "$REPO_URL/releases/latest" | tr -d '\r' | awk 'tolower($1) == "location:" { sub(".*/releases/tag/", "", $2); print $2 }')

if [ -z "$LATEST_VERSION" ]; then
    API_RESPONSE=$(curl -sL https://api.github.com/repos/duxlabs-dev/dux-shell/releases/latest)
    LATEST_VERSION=$(printf "%s" "$API_RESPONSE" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
fi

if [ -z "$LATEST_VERSION" ]; then
    printf "%bError: Could not fetch latest version%b\n" "$RED" "$NC"
    if printf "%s" "$API_RESPONSE" | grep -q "rate limit"; then
        printf "GitHub API rate limit reached for your IP address (60 requests per hour). Wait an hour or install from a different network.\n"
    fi
    exit 1
fi

printf "%bInstalling Duxinstall %s for %s...%b\n" "$GREEN" "$LATEST_VERSION" "$ARCH" "$NC"

# Download and install
TEMP_DIR=$(mktemp -d)
trap 'cd / && rm -rf "$TEMP_DIR"' EXIT
cd "$TEMP_DIR" || exit 1

# Download the gzipped binary and its checksum
printf "%bDownloading installer...%b\n" "$GREEN" "$NC"
RELEASE_URL="$REPO_URL/releases/download/$LATEST_VERSION"
# install.duxlabs.dev serves this file from master; releases before 2.0.1 only ship dankinstall-*.gz
ASSET="duxinstall-$ARCH.gz"
if ! curl -fsLI "$RELEASE_URL/$ASSET" >/dev/null; then
    ASSET="dankinstall-$ARCH.gz"
fi
curl -fL "$RELEASE_URL/$ASSET" -o "installer.gz"
curl -fL "$RELEASE_URL/$ASSET.sha256" -o "expected.sha256"

# Get the expected checksum
EXPECTED_CHECKSUM=$(awk '{print $1}' expected.sha256)

# Calculate actual checksum
printf "%bVerifying checksum...%b\n" "$GREEN" "$NC"
ACTUAL_CHECKSUM=$(sha256sum installer.gz | awk '{print $1}')

# Compare checksums
if [ "$EXPECTED_CHECKSUM" != "$ACTUAL_CHECKSUM" ]; then
    printf "%bError: Checksum verification failed%b\n" "$RED" "$NC"
    printf "Expected: %s\n" "$EXPECTED_CHECKSUM"
    printf "Got:      %s\n" "$ACTUAL_CHECKSUM"
    printf "The downloaded file may be corrupted or tampered with\n"
    exit 1
fi

# Decompress the binary
printf "%bDecompressing installer...%b\n" "$GREEN" "$NC"
gunzip installer.gz
chmod +x installer

# Execute the installer
printf "%bRunning installer...%b\n" "$GREEN" "$NC"
./installer "$@"
