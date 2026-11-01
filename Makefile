# Root Makefile for Dux Shell (DMS)
# Orchestrates building, installation, and systemd management

# Build configuration
BINARY_NAME=dms
CORE_DIR=core
BUILD_DIR=$(CORE_DIR)/bin
PREFIX ?= /usr/local
INSTALL_DIR=$(DESTDIR)$(PREFIX)/bin
DATA_DIR=$(DESTDIR)$(PREFIX)/share
ICON_DIR=$(DATA_DIR)/icons/hicolor/scalable/apps

USER_HOME := $(if $(SUDO_USER),$(shell getent passwd $(SUDO_USER) | cut -d: -f6),$(HOME))
SYSTEMD_USER_DIR=$(USER_HOME)/.config/systemd/user

SHELL_DIR=quickshell
QMLTESTRUNNER ?=
SHELL_INSTALL_DIR=$(DATA_DIR)/quickshell/dms
ASSETS_DIR=assets
APPLICATIONS_DIR=$(DATA_DIR)/applications

.PHONY: all build dev run clean lint-qml install install-bin install-completions install-systemd install-icon install-desktop uninstall uninstall-bin uninstall-shell uninstall-completions uninstall-systemd uninstall-icon uninstall-desktop help

all: build

build:
	@echo "Building $(BINARY_NAME)..."
	@$(MAKE) -C $(CORE_DIR) build
	@echo "Build complete"

dev:
	@$(MAKE) -C $(CORE_DIR) dev

run: dev
	@$(BUILD_DIR)/$(BINARY_NAME) run -c $(CURDIR)/$(SHELL_DIR)

clean:
	@echo "Cleaning build artifacts..."
	@$(MAKE) -C $(CORE_DIR) clean
	@echo "Clean complete"

lint-qml:
	@./quickshell/scripts/qmllint-entrypoints.sh

.PHONY: test-qml
test-qml:
	QMLTESTRUNNER="$(QMLTESTRUNNER)" python3 quickshell/tests/run-qml.py

# Pull the latest dux-qml-common and pin it everywhere it is consumed
# (submodule pointer + nix flake input). Commit both in one change.
update-common:
	git submodule update --remote --merge dux-qml-common
	nix --extra-experimental-features 'nix-command flakes' flake update dank-qml-common

# Installation targets
install-bin:
	@echo "Installing $(BINARY_NAME) to $(INSTALL_DIR)..."
	@install -D -m 755 $(BUILD_DIR)/$(BINARY_NAME) $(INSTALL_DIR)/$(BINARY_NAME)
	@echo "Binary installed"

install-completions:
	@echo "Installing shell completions..."
	@mkdir -p $(DATA_DIR)/bash-completion/completions
	@mkdir -p $(DATA_DIR)/zsh/site-functions
	@mkdir -p $(DATA_DIR)/fish/vendor_completions.d
	@$(BUILD_DIR)/$(BINARY_NAME) completion bash > $(DATA_DIR)/bash-completion/completions/dms 2>/dev/null || true
	@$(BUILD_DIR)/$(BINARY_NAME) completion zsh > $(DATA_DIR)/zsh/site-functions/_dms 2>/dev/null || true
	@$(BUILD_DIR)/$(BINARY_NAME) completion fish > $(DATA_DIR)/fish/vendor_completions.d/dms.fish 2>/dev/null || true
	@echo "Shell completions installed"

install-systemd:
ifneq ($(shell uname),Linux)
	@echo "Skipping systemd user service (non-Linux); start the shell from your compositor config with 'dms run'"
else
	@echo "Installing systemd user service..."
	@mkdir -p $(SYSTEMD_USER_DIR)
	@if [ -n "$(SUDO_USER)" ]; then chown -R $(SUDO_USER):"$(id -gn $SUDO_USER)" $(SYSTEMD_USER_DIR); fi
	@sed 's|/usr/bin/dms|$(PREFIX)/bin/dms|g' $(ASSETS_DIR)/systemd/dms.service > $(SYSTEMD_USER_DIR)/dms.service
	@chmod 644 $(SYSTEMD_USER_DIR)/dms.service
	@if [ -n "$(SUDO_USER)" ]; then chown $(SUDO_USER):"$(id -gn $SUDO_USER)" $(SYSTEMD_USER_DIR)/dms.service; fi
	@echo "Systemd service installed to $(SYSTEMD_USER_DIR)/dms.service"
endif

install-icon:
	@echo "Installing icon..."
	@install -D -m 644 $(ASSETS_DIR)/dev.duxlabs.shell.svg $(ICON_DIR)/dev.duxlabs.shell.svg
	@rm -f $(ICON_DIR)/com.danklinux.dms.svg
	@gtk-update-icon-cache -q $(DATA_DIR)/icons/hicolor 2>/dev/null || true
	@echo "Icon installed"

install-desktop:
	@echo "Installing desktop entries..."
	@install -D -m 644 $(ASSETS_DIR)/dms-open.desktop $(APPLICATIONS_DIR)/dms-open.desktop
	@install -D -m 644 $(ASSETS_DIR)/dev.duxlabs.shell.desktop $(APPLICATIONS_DIR)/dev.duxlabs.shell.desktop
	@install -D -m 644 $(ASSETS_DIR)/dev.duxlabs.shell.notepad.desktop $(APPLICATIONS_DIR)/dev.duxlabs.shell.notepad.desktop
	@rm -f $(APPLICATIONS_DIR)/com.danklinux.dms.desktop $(APPLICATIONS_DIR)/com.danklinux.dms.notepad.desktop
	@update-desktop-database -q $(APPLICATIONS_DIR) 2>/dev/null || true
	@echo "Desktop entries installed"

install: install-bin install-completions install-systemd install-icon install-desktop
	@echo ""
	@echo "Installation complete!"
	@echo ""
	@echo "=== Cheers, the DMS Team! ==="

# Uninstallation targets
uninstall-bin:
	@echo "Removing $(BINARY_NAME) from $(INSTALL_DIR)..."
	@rm -f $(INSTALL_DIR)/$(BINARY_NAME)
	@echo "Binary removed"

uninstall-shell:
	@echo "Removing pre-1.6 shell files from $(SHELL_INSTALL_DIR)..."
	@rm -rf $(SHELL_INSTALL_DIR)
	@echo "Shell files removed"

uninstall-completions:
	@echo "Removing shell completions..."
	@rm -f $(DATA_DIR)/bash-completion/completions/dms
	@rm -f $(DATA_DIR)/zsh/site-functions/_dms
	@rm -f $(DATA_DIR)/fish/vendor_completions.d/dms.fish
	@echo "Shell completions removed"

uninstall-systemd:
	@echo "Removing systemd user service..."
	@rm -f $(SYSTEMD_USER_DIR)/dms.service
	@echo "Systemd service removed"
	@echo "Note: Stop/disable service manually if running: systemctl --user stop dms"

uninstall-icon:
	@echo "Removing icon..."
	@rm -f $(ICON_DIR)/dev.duxlabs.shell.svg
	@rm -f $(ICON_DIR)/com.danklinux.dms.svg
	@rm -f $(ICON_DIR)/danklogo.svg
	@gtk-update-icon-cache -q $(DATA_DIR)/icons/hicolor 2>/dev/null || true
	@echo "Icon removed"

uninstall-desktop:
	@echo "Removing desktop entries..."
	@rm -f $(APPLICATIONS_DIR)/dms-open.desktop
	@rm -f $(APPLICATIONS_DIR)/dev.duxlabs.shell.desktop
	@rm -f $(APPLICATIONS_DIR)/dev.duxlabs.shell.notepad.desktop
	@rm -f $(APPLICATIONS_DIR)/com.danklinux.dms.desktop $(APPLICATIONS_DIR)/com.danklinux.dms.notepad.desktop
	@update-desktop-database -q $(APPLICATIONS_DIR) 2>/dev/null || true
	@echo "Desktop entries removed"

uninstall: uninstall-systemd uninstall-desktop uninstall-icon uninstall-completions uninstall-shell uninstall-bin
	@echo ""
	@echo "Uninstallation complete!"

# Target assist
help:
	@echo "Available targets:"
	@echo ""
	@echo "Build:"
	@echo "  all (default)        - Build the DMS binary"
	@echo "  build                - Same as 'all'"
	@echo "  clean                - Clean build artifacts"
	@echo "  lint-qml             - Run qmllint on shell entrypoints using the Quickshell tooling VFS"
	@echo "  test-qml             - Run shell logic and Qt unit tests"
	@echo ""
	@echo "Install:"
	@echo "  install              - Build and install everything (requires sudo)"
	@echo "  install-bin          - Install only the binary"
	@echo "  install-completions  - Install only shell completions"
	@echo "  install-systemd      - Install only systemd service"
	@echo "  install-icon         - Install only icon"
	@echo "  install-desktop      - Install only desktop entry"
	@echo ""
	@echo "Uninstall:"
	@echo "  uninstall            - Remove everything (requires sudo)"
	@echo "  uninstall-bin        - Remove only the binary"
	@echo "  uninstall-shell      - Remove shell files left by pre-1.6 installs"
	@echo "  uninstall-completions - Remove only shell completions"
	@echo "  uninstall-systemd    - Remove only systemd service"
	@echo "  uninstall-icon       - Remove only icon"
	@echo "  uninstall-desktop    - Remove only desktop entry"
	@echo ""
	@echo "Usage:"
	@echo "  sudo make install              - Build and install DMS"
	@echo "  sudo make uninstall            - Remove DMS"
	@echo "  systemctl --user enable --now dms  - Enable and start service"
