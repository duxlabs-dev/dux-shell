# Kali Linux

Kali Rolling is a Debian derivative, so DMS on Kali reuses the Debian packages and the Dux OBS repositories. There are no Kali-specific packages.

> **Experimental.** The installer's Kali detection and repo selection are unit tested, but a full install has not been validated on a live Kali system yet.

## What the installer does on Kali

- Detects `ID=kali` and treats it as Debian family: the same package mapping, `apt`, and window manager choices as Debian (niri).
- Uses the `Debian_Testing` OBS repositories, since Kali Rolling tracks Debian testing. Kali's `VERSION_ID` is a release date, not a Debian version number.
- Supports `amd64` and `arm64`.

## Install

Build the installer from this repo and run it. The hosted `install.duxlabs.dev` installer does not know about Kali.

```sh
sudo apt install -y git golang
git clone https://github.com/Karthik-HR0/dux-shell.git
cd dux-shell/core
go build -o duxinstall ./cmd/duxinstall
./duxinstall
```

Or add the repositories by hand and install the packages the installer would:

```sh
sudo mkdir -p /etc/apt/keyrings
for project in dms dux-repo; do
  name="home-duxlabs-dev-$project"
  url="https://download.opensuse.org/repositories/home:/duxlabs-dev:/$project/Debian_Testing"
  curl -fsSL "$url/Release.key" | gpg --dearmor | sudo tee "/etc/apt/keyrings/$name.gpg" >/dev/null
  echo "deb [signed-by=/etc/apt/keyrings/$name.gpg arch=$(dpkg --print-architecture)] $url/ /" | sudo tee "/etc/apt/sources.list.d/$name.list"
done
sudo apt update
sudo apt install dms libdux-qt-base0 niri xwayland-satellite matugen dux-search xdg-desktop-portal-gtk accountsservice
```

## Things to know

- **Back up first.** Kali Rolling is not designed to mix with outside apt sources. Take a snapshot before adding them.
- **Dependency lag.** Kali syncs from Debian testing with a delay, so an OBS package can briefly need a newer library than Kali ships. If `apt` reports unmet dependencies, wait for Kali to catch up rather than forcing the install.
- **Wayland session.** Kali defaults to Xfce on X11. DMS needs a Wayland compositor, so choose the niri session from your login manager.
- **Greeter.** `dux-greeter` is optional and has not been tested on Kali.
