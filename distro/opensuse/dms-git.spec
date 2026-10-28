%global debug_package %{nil}
%global go_toolchain_version 1.27.3

Name:           dms-git
Version:        1.4.0+git2528.d336866f
Release:        1%{?dist}
Epoch:          2
Summary:        Dux Shell - Material 3 inspired shell (git nightly)

License:        MIT
URL:            https://github.com/duxlabs-dev/dux-shell
Source0:        dms-git-source.tar.gz
Source1:        go%{go_toolchain_version}.linux-amd64.tar.gz
Source2:        go%{go_toolchain_version}.linux-arm64.tar.gz

BuildRequires:  git-core
BuildRequires:  systemd-rpm-macros

Requires:       (quickshell-git or quickshell)
Requires:       accountsservice

Recommends:     cava
Recommends:     danksearch
Recommends:     matugen
Recommends:     quickshell-git
Recommends:     NetworkManager
Recommends:     qt6-multimedia-imports
Suggests:       cups-pk-helper
Suggests:       qt6ct

Provides:       dms
Conflicts:      dms
Obsoletes:      dms

%description
Dux Shell (DMS) is a modern Wayland desktop shell built with Quickshell
and optimized for niri, Hyprland, Sway, and other wlroots compositors.

This git version tracks the master branch and includes the latest features
and fixes. The Quickshell UI is embedded in the dms binary.

%prep
%setup -q -n dms-git-source

# Verify vendored Go dependencies exist (vendored by obs-upload.sh before packaging)
# OBS build environment has no network access
test -d core/vendor || (echo "ERROR: Go vendor directory missing!" && exit 1)

%build
# Bundled Go toolchain
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

rm -rf "%{_builddir}/go-bootstrap" "%{_builddir}/.go-toolchain"
mkdir -p "%{_builddir}/go-bootstrap"
tar -xzf "$GO_TARBALL" -C "%{_builddir}/go-bootstrap"
mv "%{_builddir}/go-bootstrap/go" "%{_builddir}/.go-toolchain"

export GOROOT="%{_builddir}/.go-toolchain"
export PATH="$GOROOT/bin:$PATH"

# Create Go cache directories (OBS build env may have restricted HOME)
export HOME=%{_builddir}/go-home
export GOCACHE=%{_builddir}/go-cache
export GOMODCACHE=%{_builddir}/go-mod
mkdir -p $HOME $GOCACHE $GOMODCACHE

# OBS has no network access, so use local toolchain only
export GOTOOLCHAIN=local

go version

# Pin go.mod and vendor/modules.txt to the bundled Go toolchain version
sed -i "s/^go [0-9]\+\.[0-9]\+\(\.[0-9]*\)\?$/go %{go_toolchain_version}/" core/go.mod
sed -i "s/^\(## explicit; go \)[0-9]\+\.[0-9]\+\(\.[0-9]*\)\?$/\1%{go_toolchain_version}/" core/vendor/modules.txt

# Extract version info for embedding in binary
VERSION="%{version}"
COMMIT=$(echo "%{version}" | grep -oP '(?<=git)[0-9]+\.[a-f0-9]+' | cut -d. -f2 | head -c8 || echo "unknown")

# Build dms-cli from source using vendored dependencies
# Architecture mapping: RPM x86_64/aarch64 -> Makefile amd64/arm64
cd core
%ifarch x86_64
make GOFLAGS="-mod=vendor" dist ARCH=amd64 VERSION="$VERSION" COMMIT="$COMMIT"
mv bin/dms-linux-amd64 ../dms
%endif
%ifarch aarch64
make GOFLAGS="-mod=vendor" dist ARCH=arm64 VERSION="$VERSION" COMMIT="$COMMIT"
mv bin/dms-linux-arm64 ../dms
%endif
cd ..
chmod +x dms

%install
install -Dm755 dms %{buildroot}%{_bindir}/dms

install -d %{buildroot}%{_datadir}/bash-completion/completions
install -d %{buildroot}%{_datadir}/zsh/site-functions
install -d %{buildroot}%{_datadir}/fish/vendor_completions.d
./dms completion bash > %{buildroot}%{_datadir}/bash-completion/completions/dms || :
./dms completion zsh > %{buildroot}%{_datadir}/zsh/site-functions/_dms || :
./dms completion fish > %{buildroot}%{_datadir}/fish/vendor_completions.d/dms.fish || :

install -Dm644 assets/systemd/dms.service %{buildroot}%{_userunitdir}/dms.service

install -Dm644 assets/dms-open.desktop %{buildroot}%{_datadir}/applications/dms-open.desktop
install -Dm644 assets/dev.duxlabs.shell.desktop %{buildroot}%{_datadir}/applications/dev.duxlabs.shell.desktop
install -Dm644 assets/dev.duxlabs.shell.notepad.desktop %{buildroot}%{_datadir}/applications/dev.duxlabs.shell.notepad.desktop
install -Dm644 assets/dev.duxlabs.shell.svg %{buildroot}%{_datadir}/icons/hicolor/scalable/apps/dev.duxlabs.shell.svg

%posttrans
if [ -d "%{_sysconfdir}/xdg/quickshell/dms" ]; then
    rmdir "%{_sysconfdir}/xdg/quickshell/dms" 2>/dev/null || true
    rmdir "%{_sysconfdir}/xdg/quickshell" 2>/dev/null || true
fi
# Signal running DMS instances to reload
pkill -USR1 -x dms >/dev/null 2>&1 || :

%files
%license LICENSE
%doc CONTRIBUTING.md
%doc quickshell/README.md
%{_bindir}/dms
%dir %{_datadir}/fish
%dir %{_datadir}/fish/vendor_completions.d
%{_datadir}/fish/vendor_completions.d/dms.fish
%dir %{_datadir}/zsh
%dir %{_datadir}/zsh/site-functions
%{_datadir}/zsh/site-functions/_dms
%{_datadir}/bash-completion/completions/dms
%{_userunitdir}/dms.service
%{_datadir}/applications/dms-open.desktop
%{_datadir}/applications/dev.duxlabs.shell.desktop
%{_datadir}/applications/dev.duxlabs.shell.notepad.desktop
%dir %{_datadir}/icons/hicolor
%dir %{_datadir}/icons/hicolor/scalable
%dir %{_datadir}/icons/hicolor/scalable/apps
%{_datadir}/icons/hicolor/scalable/apps/dev.duxlabs.shell.svg

%changelog
* Sun Dec 14 2025 Avenge Media <AvengeMedia.US@gmail.com> - 1.0.2+git2528.d336866f-1
- Git snapshot (commit 2528: d336866f)
* Sat Dec 13 2025 Avenge Media <AvengeMedia.US@gmail.com> - 1.0.2+git2521.3b511e2f-1
- Git snapshot (commit 2521: 3b511e2f)
* Sat Dec 13 2025 Avenge Media <AvengeMedia.US@gmail.com> - 1.0.2+git2518.a783d650-1
- Git snapshot (commit 2518: a783d650)
* Sat Dec 13 2025 Avenge Media <AvengeMedia.US@gmail.com> - 1.0.2+git2510.0f89886c-1
- Git snapshot (commit 2510: 0f89886c)
* Sat Dec 13 2025 Avenge Media <AvengeMedia.US@gmail.com> - 1.0.2+git2507.b2ac9c6c-1
- Git snapshot (commit 2507: b2ac9c6c)
* Sat Dec 13 2025 Avenge Media <AvengeMedia.US@gmail.com> - 1.0.2+git2505.82f881af-1
- Git snapshot (commit 2505: 82f881af)
* Tue Nov 25 2025 Avenge Media <AvengeMedia.US@gmail.com> - 0.6.2+git2147.03073f68-1
- Git snapshot (commit 2147: 03073f68)
* Fri Nov 22 2025 AvengeMedia <maintainer@avengemedia.com> - 0.6.2+git-5
- Git nightly build from master branch
- Multi-arch support (x86_64, aarch64)
