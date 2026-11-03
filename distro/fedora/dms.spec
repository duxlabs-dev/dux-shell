# Feodra spec for DMS stable releases

%global debug_package %{nil}
%global version VERSION_PLACEHOLDER
%global pkg_summary Dux Shell - Material 3 inspired shell for Wayland compositors

Name:           dms
Version:        %{version}
Release:        RELEASE_PLACEHOLDER%{?dist}
Summary:        %{pkg_summary}

License:        MIT
URL:            https://github.com/duxlabs-dev/dux-shell

Source0:        dms-qml.tar.gz

BuildRequires:  gzip
BuildRequires:  wget
BuildRequires:  systemd-rpm-macros

Requires:       (quickshell or quickshell-git)
Requires:       accountsservice
Requires:       dms-cli = %{version}-%{release}

Recommends:     cava
Recommends:     (dux-search or danksearch)
Recommends:     matugen
Recommends:     NetworkManager
Recommends:     qt6-qtmultimedia
Suggests:       cups-pk-helper
Suggests:       qt6ct
Suggests:       (dux-gop or dgop)

%description
Dux Shell (DMS) is a modern Wayland desktop shell built with Quickshell
and optimized for the niri and hyprland compositors. Features notifications,
app launcher, wallpaper customization, and fully customizable with plugins.

Includes auto-theming for GTK/Qt apps with matugen, 20+ customizable widgets,
process monitoring, notification center, clipboard history, dock, control center,
lock screen, and comprehensive plugin system.

%package -n dms-cli
Summary:        Dux Shell CLI tool
License:        MIT
URL:            https://github.com/duxlabs-dev/dux-shell

%description -n dms-cli
Command-line interface for Dux Shell configuration and management.
Provides native DBus bindings, NetworkManager integration, and system utilities.

%prep
%setup -q -c -n dms-qml

case "%{_arch}" in
  x86_64)
    ARCH_SUFFIX="amd64"
    ;;
  aarch64)
    ARCH_SUFFIX="arm64"
    ;;
  *)
    echo "Unsupported architecture: %{_arch}"
    exit 1
    ;;
esac

# Download dms-cli for target architecture
wget -O %{_builddir}/dms-cli.gz "https://github.com/duxlabs-dev/dux-shell/releases/download/v%{version}/dms-distropkg-${ARCH_SUFFIX}.gz" || {
  echo "Failed to download dms-cli for architecture %{_arch}"
  exit 1
}
gunzip -c %{_builddir}/dms-cli.gz > %{_builddir}/dms-cli
chmod +x %{_builddir}/dms-cli

%build

%install
install -Dm755 %{_builddir}/dms-cli %{buildroot}%{_bindir}/dms

# Shell completions
install -d %{buildroot}%{_datadir}/bash-completion/completions
install -d %{buildroot}%{_datadir}/zsh/site-functions
install -d %{buildroot}%{_datadir}/fish/vendor_completions.d
%{_builddir}/dms-cli completion bash > %{buildroot}%{_datadir}/bash-completion/completions/dms || :
%{_builddir}/dms-cli completion zsh > %{buildroot}%{_datadir}/zsh/site-functions/_dms || :
%{_builddir}/dms-cli completion fish > %{buildroot}%{_datadir}/fish/vendor_completions.d/dms.fish || :

install -Dm644 %{_builddir}/dms-qml/assets/systemd/dms.service %{buildroot}%{_userunitdir}/dms.service

install -Dm644 %{_builddir}/dms-qml/assets/dms-open.desktop %{buildroot}%{_datadir}/applications/dms-open.desktop
install -Dm644 %{_builddir}/dms-qml/assets/dev.duxlabs.shell.desktop %{buildroot}%{_datadir}/applications/dev.duxlabs.shell.desktop
install -Dm644 %{_builddir}/dms-qml/assets/dev.duxlabs.shell.notepad.desktop %{buildroot}%{_datadir}/applications/dev.duxlabs.shell.notepad.desktop
install -Dm644 %{_builddir}/dms-qml/assets/dev.duxlabs.shell.svg %{buildroot}%{_datadir}/icons/hicolor/scalable/apps/dev.duxlabs.shell.svg

install -dm755 %{buildroot}%{_datadir}/quickshell/dms
cp -r %{_builddir}/dms-qml/* %{buildroot}%{_datadir}/quickshell/dms/

rm -rf %{buildroot}%{_datadir}/quickshell/dms/.git*
rm -f %{buildroot}%{_datadir}/quickshell/dms/.gitignore
rm -rf %{buildroot}%{_datadir}/quickshell/dms/.github
rm -rf %{buildroot}%{_datadir}/quickshell/dms/distro

echo "%{version}" > %{buildroot}%{_datadir}/quickshell/dms/VERSION

%posttrans
# Signal running DMS instances to reload
pkill -USR1 -x dms >/dev/null 2>&1 || :

%files
%license LICENSE
%doc README.md CONTRIBUTING.md
%{_datadir}/quickshell/dms/
%{_userunitdir}/dms.service
%{_datadir}/applications/dms-open.desktop
%{_datadir}/applications/dev.duxlabs.shell.desktop
%{_datadir}/applications/dev.duxlabs.shell.notepad.desktop
%{_datadir}/icons/hicolor/scalable/apps/dev.duxlabs.shell.svg

%files -n dms-cli
%{_bindir}/dms
%{_datadir}/bash-completion/completions/dms
%{_datadir}/zsh/site-functions/_dms
%{_datadir}/fish/vendor_completions.d/dms.fish

%changelog
* CHANGELOG_DATE_PLACEHOLDER AvengeMedia <contact@avengemedia.com> - VERSION_PLACEHOLDER-RELEASE_PLACEHOLDER
- Stable release VERSION_PLACEHOLDER
- Built from GitHub release
