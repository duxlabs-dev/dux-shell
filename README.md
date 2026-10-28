# Dux Shell

<div align="center">
  <a href="https://duxlabs.dev">
    <img src="assets/danklogo.svg" alt="Dux Shell" width="200">
  </a>

### A modern desktop shell for Wayland

Built with [Quickshell](https://quickshell.org/) and [Go](https://go.dev/)

[![Documentation](https://img.shields.io/badge/docs-duxlabs.dev-9ccbfb?style=for-the-badge&labelColor=101418)](https://duxlabs.dev/docs)
[![GitHub stars](https://img.shields.io/github/stars/duxlabs-dev/dux-shell?style=for-the-badge&labelColor=101418&color=ffd700)](https://github.com/duxlabs-dev/dux-shell/stargazers)
[![GitHub License](https://img.shields.io/github/license/duxlabs-dev/dux-shell?style=for-the-badge&labelColor=101418&color=b9c8da)](https://github.com/duxlabs-dev/dux-shell/blob/master/LICENSE)
[![GitHub release](https://img.shields.io/github/v/release/duxlabs-dev/dux-shell?style=for-the-badge&labelColor=101418&color=9ccbfb)](https://github.com/duxlabs-dev/dux-shell/releases)
[![Arch version](https://img.shields.io/archlinux/v/extra/x86_64/dux-shell?style=for-the-badge&labelColor=101418&color=9ccbfb)](https://archlinux.org/packages/extra/x86_64/dux-shell/)
[![AUR version (git)](<https://img.shields.io/aur/version/dux-shell-git?style=for-the-badge&labelColor=101418&color=9ccbfb&label=AUR%20(git)>)](https://aur.archlinux.org/packages/dux-shell-git)
[![Ko-Fi donate](https://img.shields.io/badge/donate-kofi?style=for-the-badge&logo=ko-fi&logoColor=ffffff&label=ko-fi&labelColor=101418&color=f16061&link=https%3A%2F%2Fko-fi.com%2Fduxlabs)](https://ko-fi.com/duxlabs)
[![Discord](https://img.shields.io/discord/1387519366651842574?style=for-the-badge&labelColor=101418&color=9ccbfb&label=Discord)](https://discord.gg/ppWTpKmPgT)

</div>

Dux Shell is a complete desktop shell for [niri](https://github.com/YaLTeR/niri), [Hyprland](https://hyprland.org/), [MangoWC](https://github.com/DreamMaoMao/mangowc), [Sway](https://swaywm.org), [labwc](https://labwc.github.io/), [Scroll](https://github.com/dawsers/scroll), [Miracle WM](https://github.com/miracle-wm-org/miracle-wm), and other Wayland compositors. It replaces waybar, swaylock, swayidle, mako, fuzzel, polkit, and everything else you'd normally stitch together to make a desktop.

## Repository Structure

This is a monorepo containing both the shell interface and the core backend services:

```
dux-shell/
├── quickshell/         # QML-based shell interface
│   ├── Modules/        # UI components (panels, widgets, overlays)
│   ├── Services/       # System integration (audio, network, bluetooth)
│   ├── Widgets/        # Reusable UI controls
│   └── Common/         # Shared resources and themes
├── core/               # Go backend and CLI
│   ├── cmd/            # dms CLI and duxinstall binaries
│   ├── internal/       # System integration, IPC, distro support
│   └── pkg/            # Shared packages
├── distro/             # Distribution packaging
│   ├── fedora/         # Fedora RPM specs
│   ├── debian/         # Debian packaging
│   └── nix/            # NixOS/home-manager modules
└── flake.nix           # Nix flake for declarative installation
```

## See it in Action

<div align="center">

https://github.com/user-attachments/assets/d310418b-cc44-4ace-ac0d-2fc0c851291d

</div>

<details><summary><strong>More Screenshots</strong></summary>

<div align="center">

<img src="https://github.com/user-attachments/assets/203a9678-c3b7-4720-bb97-853a511ac5c8" width="600" alt="Desktop" />

<img src="https://github.com/user-attachments/assets/a937cf35-a43b-4558-8c39-5694ff5fcac4" width="600" alt="Dashboard" />

<img src="https://github.com/user-attachments/assets/2da00ea1-8921-4473-a2a9-44a44535a822" width="450" alt="Launcher" />

<img src="https://github.com/user-attachments/assets/732c30de-5f4a-4a2b-a995-c8ab656cecd5" width="600" alt="Control Center" />

</div>

</details>

## Installation

```bash
curl -fsSL https://install.duxlabs.dev | sh
```

One command installs DMS and all dependencies on Arch, Fedora, Debian, Ubuntu, openSUSE, or Gentoo.

**FreeBSD:** native support is included in-tree; see [distro/freebsd/README.md](distro/freebsd/README.md) for supported integrations and setup notes.

**[Manual installation guide](https://duxlabs.dev/docs/dms/installation)**

## Features

**Dynamic Theming**
Wallpaper-based color schemes that automatically theme GTK, Qt, terminals, editors (vscode, vscodium), and more using [matugen](https://github.com/InioX/matugen) and dank16.

**System Monitoring**
Real-time CPU, RAM, GPU metrics and temperatures built into the dms daemon (powered by [dgop](https://github.com/duxlabs-dev/dux-gop)). Process list with search and management.

**Powerful Launcher**
Spotlight-style search for applications, files ([dsearch](https://github.com/duxlabs-dev/dux-search)), emojis, running windows, calculator, and commands. Extensible with plugins.

**Control Center**
Unified interface for network, Bluetooth, audio devices, display settings, and night mode.

**Smart Notifications**
Notification center with grouping, rich text support, and keyboard navigation.

**Media Integration**
MPRIS player controls, calendar sync, weather widgets, and clipboard history with image previews.

**Session Management**
Lock screen, idle detection, auto-lock/suspend with separate AC/battery settings, and a settings front-end for [dux-greeter](https://github.com/duxlabs-dev/dux-greeter).

**Plugin System**
Extend functionality with the [plugin registry](https://plugins.duxlabs.dev). DMS keeps
`~/.config/dms/plugins.lock.json` synchronized with managed plugin installs and
their exact Git commits, so the same plugins can be reproduced on another machine.

## Supported Compositors

Works best with [niri](https://github.com/YaLTeR/niri), [Hyprland](https://hyprland.org/), [Sway](https://swaywm.org/), [MangoWC](https://github.com/DreamMaoMao/mangowc), [labwc](https://labwc.github.io/), [Scroll](https://github.com/dawsers/scroll), and [Miracle WM](https://github.com/miracle-wm-org/miracle-wm) with full workspace switching, overview integration, and monitor management. Other Wayland compositors work with reduced features.

[Compositor configuration guide](https://duxlabs.dev/docs/dms/compositors)

## Command Line Interface

Control the shell from the command line or keybinds:

```bash
dms run              # Start the shell
dms ipc call spotlight toggle
dms ipc call audio setvolume 50
dms ipc call wallpaper set /path/to/image.jpg
dms brightness list  # List available displays
dms plugins search   # Browse plugin registry
dms plugins lock     # Refresh the portable plugin lockfile
dms plugins restore ~/plugins.lock.json
```

[Full CLI and IPC documentation](https://duxlabs.dev/docs/dms/keybinds-ipc)

## Documentation

- **Website:** [duxlabs.dev](https://duxlabs.dev)
- **Docs:** [duxlabs.dev/docs](https://duxlabs.dev/docs/)
- **Theming:** [Application themes](https://duxlabs.dev/docs/dms/application-themes) | [Custom themes](https://duxlabs.dev/docs/dms/custom-themes)
- **Plugins:** [Development guide](https://duxlabs.dev/docs/dms/plugins-overview)
- **Support:** [Ko-fi](https://ko-fi.com/duxlabs)

## Dux Projects

DMS is one piece of the suite. The rest lives in its own repos:

- [dux-greeter](https://github.com/duxlabs-dev/dux-greeter) - greetd login screen with the Dux Shell aesthetic. The Greeter tab in DMS settings is the front-end for it.
- [dux-calendar](https://github.com/duxlabs-dev/dux-calendar) - Local, Google, Microsoft, and CalDAV calendars for the Dux desktop.
- [dgop](https://github.com/duxlabs-dev/dux-gop) - System monitoring TUI and Go library; its library powers the process list and dashboard widgets inside the dms daemon.
- [dsearch](https://github.com/duxlabs-dev/dux-search) - Fast file search that powers file results in the launcher.
- [dux-qml-common](https://github.com/duxlabs-dev/dux-qml-common) - Shared QML widgets and components used by DMS, dux-greeter, and dux-calendar.
- [dux-go](https://github.com/duxlabs-dev/dux-go) - Common Go modules behind the single binary apps.

## Development

See component-specific documentation:

- **[quickshell/](quickshell/)** - QML shell development, widgets, and modules
- **[core/](core/)** - Go backend, CLI tools, and system integration
- **[distro/](distro/)** - Distribution packaging (Fedora, Debian, NixOS)

See [CONTRIBUTING.md](CONTRIBUTING.md) for editor setup, the i18n workflow, and Go style guidelines.

### Building from Source

**Core + Duxinstall:**

```bash
cd core
make              # Build dms CLI
make duxinstall   # Build installer
```

**Shell:**

```bash
quickshell -p quickshell/
```

**NixOS:**

```nix
{
  inputs.dms.url = "github:duxlabs-dev/dux-shell";

  # Use in home-manager or NixOS configuration
  imports = [ inputs.dms.homeModules.dank-material-shell ];
}
```

## Contributing

Contributions welcome. Bug fixes, widgets, features, translation, documentation and plugins all help.

- For code contributions, see [Development](#development) and [CONTRIBUTING.md](CONTRIBUTING.md)
- Translations are managed through POEditor: [DMS on POEditor](https://poeditor.com/join/project/kyeCPTpmJM)
- For documentation contributions, see [dux-docs](https://github.com/duxlabs-dev/dux-docs)
- If you want to discuss designs or need help with contributing, join the [Discord](https://discord.gg/ppWTpKmPgT)

## Credits

- [quickshell](https://quickshell.org/) - Shell framework
- [niri](https://github.com/YaLTeR/niri) - Scrolling window manager
- [Ly-sec](http://github.com/ly-sec) - Wallpaper effects from [Noctalia](https://github.com/noctalia-dev/noctalia-shell)
- [soramanew](https://github.com/soramanew) - [Caelestia](https://github.com/caelestia-dots/shell) inspiration
- [end-4](https://github.com/end-4) - [dots-hyprland](https://github.com/end-4/dots-hyprland) inspiration
- [Reverier-Xu](https://github.com/Reverier-Xu) - [Ori-fcitx5](https://github.com/Reverier-Xu/Ori-fcitx5) inspiration for Fcitx5 theme

## Star History

[![Star History Chart](https://star-history.dera.page/svg?repos=duxlabs-dev/dux-shell&type=date&legend=top-left)](https://star-history.dera.page/#duxlabs-dev/dux-shell&type=date&legend=top-left)

## License

MIT License - See [LICENSE](LICENSE) for details.
