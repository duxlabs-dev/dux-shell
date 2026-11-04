# DMS Backend & CLI

Go-based backend for Dux Modular Shell providing system integration, IPC, and installation tools.

**See [root README](../README.md) for project overview and installation.**

## Components

**dms CLI**
Command-line interface and daemon for shell management and system control.

**duxinstall**
Distribution-aware installer for deploying DMS and compositor configurations on Arch, Fedora, Debian, Ubuntu, openSUSE, Gentoo, and Void. Supports both an interactive TUI and a headless (unattended) mode via CLI flags.

## System Integration

### Wayland Protocols (Client)

All Wayland protocols are consumed as a client - connecting to the compositor.

| Protocol                                  | Purpose                                                     |
| ----------------------------------------- | ----------------------------------------------------------- |
| `wlr-gamma-control-unstable-v1`           | Night mode color temperature control                        |
| `wlr-screencopy-unstable-v1`              | Screen capture for color picker/screenshot                  |
| `wlr-layer-shell-unstable-v1`             | Overlay surfaces for color picker UI/screenshot             |
| `wlr-output-management-unstable-v1`       | Display configuration                                       |
| `wlr-output-power-management-unstable-v1` | DPMS on/off CLI                                             |
| `wp-viewporter`                           | Fractional scaling support (color picker/screenshot UIs)    |
| `keyboard-shortcuts-inhibit-unstable-v1`  | Inhibit compositor shortcuts during color picker/screenshot |
| `ext-data-control-v1`                     | Clipboard history and persistence                           |
| `ext-workspace-v1`                        | Workspace integration                                       |
| `dwl-ipc-unstable-v2`                     | dwl/MangoWC IPC for tags, outputs, etc.                     |

### DBus Interfaces

**Client (consuming external services):**

| Interface                        | Purpose                                       |
| -------------------------------- | --------------------------------------------- |
| `org.bluez`                      | Bluetooth management with pairing agent       |
| `org.freedesktop.NetworkManager` | Network management                            |
| `net.connman.iwd`                | iwd Wi-Fi backend                             |
| `org.freedesktop.network1`       | systemd-networkd integration                  |
| `org.freedesktop.login1`         | Session control, sleep inhibitors, brightness |
| `org.freedesktop.Accounts`       | User account information                      |
| `org.freedesktop.portal.Desktop` | Desktop appearance settings (color scheme)    |
| CUPS via IPP + D-Bus             | Printer management with job notifications     |

**Server (implementing interfaces):**

| Interface                     | Purpose                                |
| ----------------------------- | -------------------------------------- |
| `org.freedesktop.ScreenSaver` | Screensaver inhibit for video playback |

Custom IPC via unix socket (JSON API) for shell communication.

### Hardware Control

| Subsystem | Method              | Purpose                            |
| --------- | ------------------- | ---------------------------------- |
| DDC/CI    | I2C direct          | External monitor brightness        |
| Backlight | logind or sysfs     | Internal display brightness        |
| evdev     | `/dev/input/event*` | Keyboard state (caps lock LED)     |
| udev      | netlink monitor     | Backlight device updates (for OSD) |

### Plugin System

- Plugin registry integration
- Plugin lifecycle management
- Settings persistence

## CLI Commands

- `dms run [-d]` - Start shell (optionally as daemon)
- `dms restart` / `dms kill` - Manage running processes
- `dms ipc <command>` - Send IPC commands (toggle launcher, notifications, etc.)
- `dms plugins [install|browse|search|lock|restore]` - Plugin management and portable exact-revision lockfiles
- `dms brightness [list|set]` - Control display/monitor brightness
- `dms color pick` - Native color picker (see below)
- `dms update` - Update DMS and dependencies (disabled in distro packages)
- `dms greeter` - Deprecated; forwards to the standalone [dms-greeter](https://github.com/duxlabs-dev/dux-greeter) binary

### Color Picker

Native Wayland color picker with magnifier, no external dependencies. Supports HiDPI and fractional scaling.

```bash
dms color pick              # Pick color, output hex
dms color pick --rgb        # Output as RGB (255 128 64)
dms color pick --hsv        # Output as HSV (24 75% 100%)
dms color pick --json       # Output all formats as JSON
dms color pick -a           # Auto-copy to clipboard
```

The on-screen preview displays the selected format. JSON output includes hex, RGB, HSL, HSV, and CMYK values.

## Building

Requires Go 1.25+

**Development build:**

```bash
make              # Build dms CLI
make duxinstall   # Build installer
make test         # Run tests
```

**Distribution build:**

```bash
make dist         # Build without update features
```

Produces `bin/dms-linux-amd64` and `bin/dms-linux-arm64`

**Installation:**

```bash
sudo make install  # Install to /usr/local/bin/dms
```

## Development

**Setup pre-commit hooks:**

```bash
git config core.hooksPath .githooks
```

This runs gofmt, golangci-lint, tests, and builds before each commit when `core/` files are staged.

**Regenerating Wayland Protocol Bindings:**

Protocol XML files live in `internal/proto/xml/`. Bindings are generated with the [dankgo](https://github.com/duxlabs-dev/dux-go) `go-wayland-scanner`:

```bash
go run github.com/duxlabs-dev/dux-go/cmd/go-wayland-scanner@latest \
  -i internal/proto/xml/wlr-gamma-control-unstable-v1.xml \
  -pkg wlr_gamma_control -o internal/proto/wlr_gamma_control/gamma_control.go
```

**Module Structure:**

- `cmd/` - Binary entrypoints (dms, duxinstall)
- `internal/distros/` - Distribution-specific installation logic
- `internal/proto/` - Wayland protocol bindings
- `pkg/` - Shared packages

## Installation via duxinstall

**Interactive (TUI):**

```bash
curl -fsSL https://install.duxlabs.dev | sh
```

**Headless (unattended):**

Headless mode requires cached credentials or a passwordless rule for your privilege escalation tool (sudo, doas, or run0). With sudo, run `sudo -v` first:

```bash
sudo -v && curl -fsSL https://install.duxlabs.dev | sh -s -- -c niri -t ghostty -y
sudo -v && curl -fsSL https://install.duxlabs.dev | sh -s -- -c hyprland -t kitty --dux-greeter -y
sudo -v && curl -fsSL https://install.duxlabs.dev | sh -s -- -c niri -t ghostty --git-deps niri,quickshell --all-features -y
```

| Flag | Short | Description |
|------|-------|-------------|
| `--compositor <niri\|hyprland\|mango>` | `-c` | Compositor/WM to install (required for headless) |
| `--term <ghostty\|kitty\|alacritty>` | `-t` | Terminal emulator (required for headless) |
| `--privesc <sudo\|doas\|run0>` | | Privilege escalation tool (default: autodetect) |
| `--git` | | Install the git version of every dependency that has one |
| `--git-deps <name,...>` | | Install the git version of specific dependencies (e.g. `niri,quickshell`) |
| `--all-features` | | Enable all optional dependencies (`dux-greeter`, `dux-search`, `dux-calendar`, `dux-files`) |
| `--dux-greeter` | | Install dux-greeter |
| `--dux-search` | | Install dux-search and enable its user indexing service |
| `--dux-calendar` | | Install dux-calendar |
| `--dux-files` | | Install dux-files (dfiles file manager) |
| `--include-deps <name,...>` | | Enable optional dependencies (e.g. `dux-greeter`) |
| `--exclude-deps <name,...>` | | Skip specific dependencies |
| `--replace-configs <name,...>` | | Replace specific configuration files (mutually exclusive with `--replace-configs-all`) |
| `--replace-configs-all` | | Replace all configuration files (mutually exclusive with `--replace-configs`) |
| `--yes` | `-y` | Required for headless mode - confirms installation without interactive prompts |

Headless mode requires `--yes` to proceed; without it, the installer exits with an error.
Configuration files are not replaced by default unless `--replace-configs` or `--replace-configs-all` is specified.
Optional packages (`dux-greeter`, `dux-search`, `dux-calendar`, `dux-files`) are disabled by default; enable them with their dedicated flags, `--include-deps`, or `--all-features`.
The old `--dms-greeter`, `--danksearch` and `--dankcalendar` flags and dependency names still work but are deprecated.

When no flags are provided, `duxinstall` launches the interactive TUI.

### Headless mode validation rules

Headless mode activates when `--compositor` or `--term` is provided.

- Both `--compositor` and `--term` are required; providing only one results in an error.
- Headless-only flags (`--privesc`, `--git`, `--git-deps`, `--all-features`, `--include-deps`, `--exclude-deps`, `--replace-configs`, `--replace-configs-all`, `--yes`, `--dux-search`, `--dux-calendar`, `--dux-files`, `--dux-greeter` and their deprecated aliases) are rejected in TUI mode.
- Positional arguments are not accepted.

### Log file location

`duxinstall` writes logs to `/tmp` by default.
Set the `DUXINSTALL_LOG_DIR` environment variable to override the log directory.

## Supported Distributions

Arch, Fedora, Debian, Ubuntu, openSUSE, Gentoo, Void (and derivatives)

**Arch Linux**
Uses `pacman` for system packages, builds AUR packages via `makepkg`, no AUR helper dependency.

**Fedora**

Uses COPR repositories (`duxlabs/dux-repo`, plus `duxlabs/dms` or `duxlabs/dms-git` for git builds).

**Ubuntu**
Requires PPA support. Most packages built from source (slow first install).

**Debian**
Debian 13+ (Trixie), testing, and sid. Stable quickshell from Debian (trixie-backports on 13). Other companions via OBS.

**openSUSE**
Most packages available in standard repos. Minimal building required.

**Gentoo**
Uses Portage with GURU overlay. Automatically configures USE flags. Variable success depending on system configuration.

**Void Linux**
Uses XBPS with the DMS and Dux Labs self-hosted repositories.

See installer output for distribution-specific details during installation.
