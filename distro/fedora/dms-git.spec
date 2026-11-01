# Spec for DMS - uses rpkg macros for git builds

%global debug_package %{nil}
%global version {{{
set -e
if [ "$(git rev-parse --is-shallow-repository)" = "true" ]; then
    git fetch --unshallow --quiet
fi
if [ "$(git rev-parse --is-shallow-repository)" = "true" ]; then
    echo "clone is still shallow; refusing a truncated commit count" >&2
    exit 1
fi
printf '0.0.git.%s.%s\n' \
    "$(git rev-list --count HEAD)" \
    "$(git rev-parse --short=8 HEAD)"
}}}
%global pkg_summary Dux Shell - Material 3 inspired shell for Wayland compositors
%global go_toolchain_version 1.27.3

Name:           dms
Epoch:          2
Version:        %{version}
Release:        1%{?dist}
Summary:        %{pkg_summary}

License:        MIT
URL:            https://github.com/duxlabs-dev/dux-shell
VCS:            {{{ git_repo_vcs }}}
Source0:        {{{ git_repo_pack }}}
Source1:        https://go.dev/dl/go%{go_toolchain_version}.linux-amd64.tar.gz
Source2:        https://go.dev/dl/go%{go_toolchain_version}.linux-arm64.tar.gz
# git_repo_pack archives skip submodule content, so pack dux-qml-common separately
Source3:        {{{ git_pack path=$GIT_ROOT/dux-qml-common dir_name=dux-qml-common source_name=dux-qml-common.tar.gz }}}

BuildRequires:  git-core
BuildRequires:  gzip
BuildRequires:  make
BuildRequires:  systemd-rpm-macros

# Core requirements
Requires:       (quickshell-git or quickshell)
Requires:       accountsservice
Requires:       dms-cli = %{epoch}:%{version}-%{release}

# Core utilities (Recommended for DMS functionality)
Recommends:     cava
Recommends:     (dux-search or danksearch)
Recommends:     matugen
Recommends:     quickshell-git

# Recommended system packages
Recommends:     NetworkManager
Recommends:     qt6-qtmultimedia
Suggests:       cups-pk-helper
Suggests:       qt6ct
Suggests:       (dux-gop or dgop)

%description
Dux Shell (DMS) is a modern Wayland desktop shell built with Quickshell
and optimized for the niri, hyprland, sway, and dwl (MangoWC) compositors. Features notifications,
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
{{{ git_repo_setup_macro }}}
rm -rf dux-qml-common
tar -xzf %{SOURCE3}
test -e quickshell/DCommon/Widgets/DIcon.qml || { echo "DCommon missing after submodule unpack"; exit 1; }

%build
# Build DMS CLI from source (core/subdirectory)
VERSION="%{version}"
COMMIT=$(echo "%{version}" | grep -oP '[a-f0-9]{7,}' | head -n1 || echo "unknown")

# Use pinned bundled Go toolchain (deterministic across chroots)
case "%{_arch}" in
  x86_64)
    GO_TARBALL="%{_sourcedir}/go%{go_toolchain_version}.linux-amd64.tar.gz"
    ;;
  aarch64)
    GO_TARBALL="%{_sourcedir}/go%{go_toolchain_version}.linux-arm64.tar.gz"
    ;;
  *)
    echo "Unsupported architecture for bundled Go: %{_arch}"
    exit 1
    ;;
esac

rm -rf .go
tar -xzf "$GO_TARBALL"
mv go .go
export GOROOT="$PWD/.go"
export PATH="$GOROOT/bin:$PATH"
export GOTOOLCHAIN=local
go version

cd core
make dist VERSION="$VERSION" COMMIT="$COMMIT"

%install
# Install dms-cli binary (built from source)
case "%{_arch}" in
  x86_64)
    DMS_BINARY="dms-linux-amd64"
    ;;
  aarch64)
    DMS_BINARY="dms-linux-arm64"
    ;;
  *)
    echo "Unsupported architecture: %{_arch}"
    exit 1
    ;;
esac

install -Dm755 core/bin/${DMS_BINARY} %{buildroot}%{_bindir}/dms

# Shell completions
install -d %{buildroot}%{_datadir}/bash-completion/completions
install -d %{buildroot}%{_datadir}/zsh/site-functions
install -d %{buildroot}%{_datadir}/fish/vendor_completions.d
core/bin/${DMS_BINARY} completion bash > %{buildroot}%{_datadir}/bash-completion/completions/dms || :
core/bin/${DMS_BINARY} completion zsh > %{buildroot}%{_datadir}/zsh/site-functions/_dms || :
core/bin/${DMS_BINARY} completion fish > %{buildroot}%{_datadir}/fish/vendor_completions.d/dms.fish || :

# Install systemd user service
install -Dm644 assets/systemd/dms.service %{buildroot}%{_userunitdir}/dms.service

install -Dm644 assets/dms-open.desktop %{buildroot}%{_datadir}/applications/dms-open.desktop
install -Dm644 assets/dev.duxlabs.shell.desktop %{buildroot}%{_datadir}/applications/dev.duxlabs.shell.desktop
install -Dm644 assets/dev.duxlabs.shell.notepad.desktop %{buildroot}%{_datadir}/applications/dev.duxlabs.shell.notepad.desktop
install -Dm644 assets/dev.duxlabs.shell.svg %{buildroot}%{_datadir}/icons/hicolor/scalable/apps/dev.duxlabs.shell.svg

%posttrans
# Signal running DMS instances to reload
pkill -USR1 -x dms >/dev/null 2>&1 || :

%files
%license LICENSE
%doc CONTRIBUTING.md
%doc quickshell/README.md
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
{{{ git_repo_changelog }}}
