BINARY_NAME=dms
BINARY_NAME_INSTALL=duxinstall
SOURCE_DIR=cmd/dms
SOURCE_DIR_INSTALL=cmd/duxinstall
BUILD_DIR=bin
SHELL_SRC=../quickshell
EMBED_DIR=internal/shellembed/dist
PREFIX ?= /usr/local
INSTALL_DIR=$(PREFIX)/bin

GO=go
GOFLAGS=-ldflags="-s -w"

# Version and build info
BASE_VERSION=$(shell git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "0.0.0")
COMMIT_COUNT=$(shell git rev-list --count HEAD 2>/dev/null || echo "0")
COMMIT_HASH=$(shell git rev-parse --short=8 HEAD 2>/dev/null || echo "unknown")
VERSION?=$(BASE_VERSION)+git$(COMMIT_COUNT).$(COMMIT_HASH)
BUILD_TIME?=$(shell date -u '+%Y-%m-%d_%H:%M:%S')
COMMIT?=$(COMMIT_HASH)

BUILD_LDFLAGS=-ldflags='-s -w -X main.Version=$(VERSION) -X main.buildTime=$(BUILD_TIME) -X main.commit=$(COMMIT)'

# Architecture to build for dist target (amd64, arm64, or all)
ARCH ?= all
# Target OSes for dist builds
DIST_OSES ?= linux freebsd
# purego's fake cgo needs this to compile without cgo on freebsd
FREEBSD_GCFLAGS=-gcflags=github.com/ebitengine/purego/internal/fakecgo=-std

ifeq ($(ARCH),all)
DIST_ARCHS = amd64 arm64
else
DIST_ARCHS = $(ARCH)
endif

.PHONY: all build qtbase clean-qtbase build-distro sync-shell duxinstall dist clean install install-all install-duxinstall uninstall uninstall-all uninstall-duxinstall install-config uninstall-config test fmt vet deps print-version help

# Default target
all: build

# quickshell runtime built from the dux-qt-base submodule and embedded in dms as libdux-qt-base.so,
# which `dms qs` dlopens. QTBASE=0 skips it and `dms qs` then dlopens an installed libdux-qt-base.so.0
# (next to dms or in the system library dirs, e.g. a dux-qt-base package) or falls back to upstream qs on PATH.
QTBASE ?= 1
QTBASE_SRC ?= ../dux-qt-base
QTBASE_BUILD ?= build/dux-qt-base
QTBASE_LIB = $(QTBASE_BUILD)/src/libdux-qt-base.so.0
QTBASE_EMBED_DIR = internal/qtbaseembed/lib
ifeq ($(QTBASE),0)
QTBASE_DEP =
QTBASE_TAG =
else
QTBASE_DEP = qtbase
QTBASE_TAG = withqtbase
endif

qtbase:
	@test -f $(QTBASE_SRC)/CMakeLists.txt || { echo "dux-qt-base missing: run git submodule update --init"; exit 1; }
	@test -f $(QTBASE_BUILD)/build.ninja || cmake -S $(QTBASE_SRC) -B $(QTBASE_BUILD) -GNinja -DCMAKE_BUILD_TYPE=Release \
		-DDISTRIBUTOR=$(BINARY_NAME)-source -DGIT_REVISION=$$(git -C $(QTBASE_SRC) rev-parse --short=8 HEAD 2>/dev/null || echo unknown)
	cmake --build $(QTBASE_BUILD)
	@mkdir -p $(QTBASE_EMBED_DIR)
	@strip --strip-unneeded -o $(QTBASE_EMBED_DIR)/libdux-qt-base.so.0 $(QTBASE_LIB)
	@sha256sum $(QTBASE_EMBED_DIR)/libdux-qt-base.so.0 | cut -c1-16 > $(QTBASE_EMBED_DIR)/.dankrev

clean-qtbase:
	@rm -rf $(QTBASE_BUILD)

sync-shell:
	@test -e $(SHELL_SRC)/DCommon/Widgets/DIcon.qml || { echo "DCommon missing: run git submodule update --init"; exit 1; }
	@rm -rf $(EMBED_DIR)
	@mkdir -p $(EMBED_DIR)
	@tar -C $(SHELL_SRC) --exclude=.qmlls.ini --exclude-from=../scripts/shell-test-excludes.txt -chf - . | tar -C $(EMBED_DIR) -xf -
	@rm -rf $(EMBED_DIR)/.git* $(EMBED_DIR)/.github
	@rm -rf $(EMBED_DIR)/tests
	@find $(EMBED_DIR) -type d \( -name .claude -o -name .vscode \) -prune -exec rm -rf {} +
	@rm -f $(EMBED_DIR)/AGENTS.md $(EMBED_DIR)/qmlformat-all.sh
	@rm -f $(EMBED_DIR)/scripts/i18nsync.py $(EMBED_DIR)/scripts/build-vscode-vsix.sh $(EMBED_DIR)/scripts/qmllint-entrypoints.sh
	@rm -f $(EMBED_DIR)/scripts/spam-notifications.sh $(EMBED_DIR)/scripts/verify-notifications.sh
	@rm -f $(EMBED_DIR)/translations/*.py $(EMBED_DIR)/translations/WORKFLOW.md
	@cd $(EMBED_DIR) && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | cut -c1-16 > .dankrev

# Build the main binary (dms) with the UI and the quickshell runtime embedded
build: sync-shell $(QTBASE_DEP)
	@echo "Building $(BINARY_NAME)..."
	@mkdir -p $(BUILD_DIR)
	CGO_ENABLED=0 $(GO) build -tags 'withshell $(QTBASE_TAG)' $(BUILD_LDFLAGS) -o $(BUILD_DIR)/$(BINARY_NAME) ./$(SOURCE_DIR)
	@echo "Build complete: $(BUILD_DIR)/$(BINARY_NAME)"

# Native distro package binary (no update/greeter support), UI and runtime embedded
build-distro: sync-shell $(QTBASE_DEP)
	@echo "Building $(BINARY_NAME) for distro packaging..."
	@mkdir -p $(BUILD_DIR)
	CGO_ENABLED=0 $(GO) build -tags 'distro_binary withshell $(QTBASE_TAG)' $(BUILD_LDFLAGS) -o $(BUILD_DIR)/$(BINARY_NAME) ./$(SOURCE_DIR)
	@echo "Build complete: $(BUILD_DIR)/$(BINARY_NAME)"

duxinstall:
	@echo "Building $(BINARY_NAME_INSTALL)..."
	@mkdir -p $(BUILD_DIR)
	CGO_ENABLED=0 $(GO) build $(BUILD_LDFLAGS) -o $(BUILD_DIR)/$(BINARY_NAME_INSTALL) ./$(SOURCE_DIR_INSTALL)
	@echo "Build complete: $(BUILD_DIR)/$(BINARY_NAME_INSTALL)"

# Build distro binaries (no update/greeter support) for each DIST_OSES/DIST_ARCHS pair
dist: sync-shell
	@echo "Building $(BINARY_NAME) for distribution ($(DIST_OSES) x $(DIST_ARCHS))..."
	@mkdir -p $(BUILD_DIR)
	@for os in $(DIST_OSES); do \
		for arch in $(DIST_ARCHS); do \
			echo "Building for $$os/$$arch..."; \
			gcflags=""; [ "$$os" = freebsd ] && gcflags="$(FREEBSD_GCFLAGS)"; \
			CGO_ENABLED=0 GOOS=$$os GOARCH=$$arch $(GO) build $$gcflags -tags 'distro_binary withshell' $(BUILD_LDFLAGS) -o $(BUILD_DIR)/$(BINARY_NAME)-$$os-$$arch ./$(SOURCE_DIR) || exit 1; \
			echo "  $(BUILD_DIR)/$(BINARY_NAME)-$$os-$$arch"; \
		done; \
	done
	@echo "Distribution builds complete"

build-all: build duxinstall

install:
	@echo "Installing $(BINARY_NAME) to $(INSTALL_DIR)..."
	@install -D -m 755 $(BUILD_DIR)/$(BINARY_NAME) $(INSTALL_DIR)/$(BINARY_NAME)
	@echo "Installation complete"

install-all:
	@echo "Installing $(BINARY_NAME) to $(INSTALL_DIR)..."
	@install -D -m 755 $(BUILD_DIR)/$(BINARY_NAME) $(INSTALL_DIR)/$(BINARY_NAME)
	@echo "Installing $(BINARY_NAME_INSTALL) to $(INSTALL_DIR)..."
	@install -D -m 755 $(BUILD_DIR)/$(BINARY_NAME_INSTALL) $(INSTALL_DIR)/$(BINARY_NAME_INSTALL)
	@echo "Installation complete"

install-duxinstall:
	@echo "Installing $(BINARY_NAME_INSTALL) to $(INSTALL_DIR)..."
	@install -D -m 755 $(BUILD_DIR)/$(BINARY_NAME_INSTALL) $(INSTALL_DIR)/$(BINARY_NAME_INSTALL)
	@echo "Installation complete"

uninstall:
	@echo "Uninstalling $(BINARY_NAME) from $(INSTALL_DIR)..."
	@rm -f $(INSTALL_DIR)/$(BINARY_NAME)
	@echo "Uninstall complete"

uninstall-all:
	@echo "Uninstalling $(BINARY_NAME) from $(INSTALL_DIR)..."
	@rm -f $(INSTALL_DIR)/$(BINARY_NAME)
	@echo "Uninstalling $(BINARY_NAME_INSTALL) from $(INSTALL_DIR)..."
	@rm -f $(INSTALL_DIR)/$(BINARY_NAME_INSTALL)
	@echo "Uninstall complete"

uninstall-duxinstall:
	@echo "Uninstalling $(BINARY_NAME_INSTALL) from $(INSTALL_DIR)..."
	@rm -f $(INSTALL_DIR)/$(BINARY_NAME_INSTALL)
	@echo "Uninstall complete"

clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(BUILD_DIR) $(EMBED_DIR) $(QTBASE_EMBED_DIR)
	@echo "Clean complete"

test:
	@echo "Running tests..."
	CGO_ENABLED=0 $(GO) test -v ./...

fmt:
	@echo "Formatting Go code..."
	$(GO) fmt ./...

vet:
	@echo "Running go vet..."
	CGO_ENABLED=0 $(GO) vet $$($(GO) list ./... | grep -v internal/highlight/lexers)
	CGO_ENABLED=0 $(GO) vet -composites=false ./internal/highlight/lexers

deps:
	@echo "Updating dependencies..."
	$(GO) mod tidy
	$(GO) mod download

dev: $(QTBASE_DEP)
	@echo "Building $(BINARY_NAME) for development..."
	@mkdir -p $(BUILD_DIR)
	CGO_ENABLED=0 $(GO) build -tags '$(QTBASE_TAG)' -o $(BUILD_DIR)/$(BINARY_NAME) ./$(SOURCE_DIR)
	@echo "Development build complete: $(BUILD_DIR)/$(BINARY_NAME)"

check-go:
	@echo "Checking Go version..."
	@go version | grep -E "go1\.(2[2-9]|[3-9][0-9])" > /dev/null || (echo "ERROR: Go 1.22 or higher required" && exit 1)
	@echo "Go version OK"

version: check-go
	@echo "Version: $(VERSION)"
	@echo "Build Time: $(BUILD_TIME)"
	@echo "Commit: $(COMMIT)"

print-version:
	@echo "$(VERSION)"

help:
	@echo "Available targets:"
	@echo "  all                 - Build the main binary (dms) (default)"
	@echo "  build               - Build the main binary (dms) with the embedded UI and runtime (needs the dux-qt-base submodule)"
	@echo "                        QTBASE=0 skips the runtime: dms then uses an installed dux-qt-base package or qs on PATH"
	@echo "  build-distro        - Native build for distro packages (distro_binary tag, same QTBASE switch)"
	@echo "  sync-shell          - Copy quickshell/ into the embed dir (runs before tagged builds)"
	@echo "  duxinstall         - Build duxinstall binary"
	@echo "  dist                - Build dms for linux/freebsd amd64/arm64 (no update/greeter)"
	@echo "                        Use ARCH=amd64 or ARCH=arm64 and/or DIST_OSES=linux to narrow"
	@echo "                        No embedded runtime: dist binaries need an installed dux-qt-base or qs on PATH"
	@echo "  build-all           - Build both binaries"
	@echo "  install             - Install dms to $(INSTALL_DIR)"
	@echo "  install-all         - Install both dms and duxinstall to $(INSTALL_DIR)"
	@echo "  install-duxinstall - Install only duxinstall to $(INSTALL_DIR)"
	@echo "  uninstall           - Remove dms from $(INSTALL_DIR)"
	@echo "  uninstall-all       - Remove both binaries from $(INSTALL_DIR)"
	@echo "  uninstall-duxinstall - Remove only duxinstall from $(INSTALL_DIR)"
	@echo "  clean               - Clean build artifacts"
	@echo "  test                - Run tests"
	@echo "  fmt                 - Format Go code"
	@echo "  vet                 - Run go vet"
	@echo "  deps                - Update dependencies"
	@echo "  dev                 - Build with debug info"
	@echo "  check-go            - Check Go version compatibility"
	@echo "  version             - Show version information"
	@echo "  help                - Show this help message"
