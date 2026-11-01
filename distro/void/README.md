# Void Linux packaging

XBPS templates for Dux Shell on [Void Linux](https://voidlinux.org).

| Package | Source repo | Template |
| --- | --- | --- |
| `dms` | Dux Shell | [`srcpkgs/dms/template`](srcpkgs/dms/template) |
| `dux-gop` | duxlabs-dev/dux-gop | maintained in the **dux-repo** repo (`distro/void/srcpkgs/dux-gop`) |
| `dux-search` | duxlabs-dev/dux-search | maintained in the **dux-repo** repo (`distro/void/srcpkgs/dux-search`) |

All build from source.

## Distribution

This is a DMS maintained repo for VoidLinux until these packages are officially merged upstream in the Void Linux repositories, you can install them from our self-hosted custom XBPS repositories.

### Using the Self-Hosted Repositories

We serve both stable release and development packages from Cloudflare R2 at
`void.duxlabs.dev`: `dms` and `dms-git` from `dms/current`, their dependencies
and `dux-greeter` from `dux-repo/current`.

> **Repository migration:** the former GitHub Pages repositories will be
> frozen for 14 days at cutover. Their retirement date will be announced when
> the snapshots are frozen. Replace any existing `avengemedia.github.io`
> entries with the URLs below.
>
> Existing installs: run `dms migrate dux`.

#### 1. Add Repository Configurations

Create configuration files in `/etc/xbps.d/` pointing to our repositories (needed for both stable and git/nightly variants):

```sh
echo "repository=https://void.duxlabs.dev/dms/current" | sudo tee /etc/xbps.d/dms.conf
echo "repository=https://void.duxlabs.dev/dux-repo/current" | sudo tee /etc/xbps.d/dux.conf
```

#### 2. Install DMS

Synchronize repositories and install the package:

* For the **stable** variant:

    ```sh
    sudo xbps-install -S dms
    ```

* For the **git/nightly** variant (this will conflict with and replace the stable package):

    ```sh
    sudo xbps-install -S dms-git
    ```

*Note: On the first sync, `xbps-install` will output our signing key fingerprint and ask you to type `y` to trust and import it. Verify that the key matches our official signing fingerprint.*

The templates here are the source of truth: copy each into a void-packages
checkout at `srcpkgs/<pkg>/template` to build or submit it.

## Dependencies

Installing `dms` automatically pulls in `quickshell`, `accountsservice`,
`matugen` (which drives the Material You theming), `dbus`, `elogind`, and
`mesa-dri` (GL drivers, required for compositors to render).
The rest are optional, install whichever features you want:

| Package | Enables |
| --- | --- |
| `dux-search` | launcher / filesystem search |
| `cava` | audio visualiser widget |
| `qt6-multimedia` | system sound feedback |
| `qt6ct` | Qt app theming |
| `power-profiles-daemon` | power profile control |
| `cups-pk-helper` | printer management |
| `NetworkManager` | network control |
| `i2c-tools` | external-monitor brightness (DDC) |
| `niri` / `hyprland` / `sway` | a Wayland compositor (niri is the team's choice) |

## Building & testing

Inside a `void-packages` checkout (symlink or copy these `srcpkgs/<pkg>` dirs in):

```sh
./xbps-src pkg dux-search
./xbps-src pkg dms

# lint (xlint ships in the xtools package)
xlint srcpkgs/dms/template

# install the built packages
sudo xbps-install --repository=hostdir/binpkgs dms dux-search
```

## Running the shell

DMS is a user-level Wayland shell with **no system service** — start it from your
compositor's autostart, e.g. niri:

```kdl
spawn-at-startup "dms" "run"
```

or Hyprland (`~/.config/hypr/hyprland.lua`):

```lua
hl.on("hyprland.start", function()
	hl.exec_cmd("dms run")
end)
```

From a TTY on Void without a greeter, start your compositor through a D-Bus
session:

```sh
dbus-run-session niri
dbus-run-session Hyprland
dbus-run-session mango
```

The `mangowc` package provides the `mango` command.

For power menu actions to work on runit systems, make sure the system D-Bus and
elogind services are enabled:

```sh
sudo ln -sf /etc/sv/dbus /var/service/dbus
sudo ln -sf /etc/sv/elogind /var/service/elogind
```

The `duxinstall` Void path enables both services after installing packages.
