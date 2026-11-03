This file is more of a quick reference so I know what to account for before next releases.

# Next
- notifications: timed per-app popup mutes (1h / 4h) from the notification context menu
- Go core migrated to dankgo (shared log/paths/errdefs/ipc/shellapp)
- Quickshell UI embedded in the dms binary, -c / DMS_SHELL_DIR override - breaking for setups relying on ~/.config/quickshell/dms auto-discovery (XDG search removed)
- release binaries + all -git packages build with withshell; sockets/pidfiles/env names unchanged, IPC APIVersion 28 wire-compatible
- -git packages (AUR dms-shell-git, fedora, opensuse, void, debian, ubuntu) no longer install /usr/share/quickshell/dms; dms greeter install falls back to the embedded UI when the greeter package is present
- ping over the socket returns {"pong":true} instead of "pong"
- startup: embedded UI resolution is keyed by build-time .dankrev (no per-start content hashing)

# 1.5.0
- Overhauled shadows
- App ID changed to com.danklinux.dms - breaking for window rules
- Greeter stuff
- Terminal mux
- Locale overrides
- new neovim theming

# 1.4.0

- Overhauled system monitor, graphs, styling
- dbus API for plugins, KDEConnect
- new dank16 algorithm
- launcher actions, customize env, args, name, icon
- launcher v2 - omega stuff, GIF search, supa powerful
- dock on bar
- window rule manager, with IPC - #TODO verify RTL layout (niri only)

# 1.2.0

- Added clipboard and clipboard history integration
- Added swipe to dismiss notification popups and from center
- Added paste from clipboard history view - requires wtype
- Optimize surface damage of OSD & Toast
- Add monitor configurator (niri, Hyprland, MangoWC)
- **BREAKING** ghostty theme changed to ~/.config/ghostty/themes/danktheme
  - requires intervention and doc update
- Added desktop widget plugins
  - dev guidance available
  - builtin clock & dgop widgets
  - new IPC targets
- Initial RTL support/i18n
- Theme registry
- Notification persistence & history
- **BREAKING** vscode theme needs re-installed
- dms doctor cmd
- niri/hypr/mango gaps/window/border overrides
- settings search
- notification display ops on lock screen
