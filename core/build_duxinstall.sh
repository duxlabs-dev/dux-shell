#!/bin/bash

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get latest version tag
VERSION=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")

echo -e "${GREEN}Building duxinstall ${VERSION}${NC}"

# Create bin directory if it doesn't exist
mkdir -p bin

# Build for each architecture
for ARCH in amd64 arm64; do
    echo -e "${BLUE}Building for ${ARCH}...${NC}"

    cd cmd/duxinstall
    GOOS=linux CGO_ENABLED=0 GOARCH=${ARCH} \
        go build -trimpath -ldflags "-s -w -X main.Version=${VERSION}" \
        -o ../../bin/duxinstall-${ARCH}
    cd ../..

    # Compress
    gzip -9 -k -f bin/duxinstall-${ARCH}

    # Generate checksum
    (cd bin && sha256sum duxinstall-${ARCH}.gz > duxinstall-${ARCH}.gz.sha256)

    echo -e "${GREEN}✓ Built bin/duxinstall-${ARCH}.gz${NC}"
done

echo -e "${GREEN}Done! Files ready in bin/:${NC}"
ls -lh bin/duxinstall-*
