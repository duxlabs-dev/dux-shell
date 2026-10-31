{
  description = "Dux Shell";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-compat = {
      url = "github:NixOS/flake-compat";
      flake = false;
    };
    dank-qml-common = {
      url = "github:duxlabs-dev/dux-qml-common";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      dank-qml-common,
      ...
    }:
    let
      goModVersion =
        let
          content = builtins.readFile ./core/go.mod;
          lines = builtins.filter builtins.isString (builtins.split "\n" content);
          goLines = builtins.filter (l: builtins.match "go [0-9]+\\..*" l != null) lines;
          matched =
            if goLines != [ ] then builtins.match "go ([0-9]+)\\.([0-9]+).*" (builtins.head goLines) else null;
        in
        if matched != null then
          {
            major = builtins.elemAt matched 0;
            minor = builtins.elemAt matched 1;
          }
        else
          {
            major = "1";
            minor = "25";
          };
      goForPkgs = pkgs: pkgs.${"go_${goModVersion.major}_${goModVersion.minor}"};
      forEachSystem =
        fn:
        nixpkgs.lib.genAttrs [ "aarch64-darwin" "aarch64-linux" "x86_64-darwin" "x86_64-linux" ] (
          system: fn system nixpkgs.legacyPackages.${system}
        );
      forEachLinuxSystem =
        fn:
        nixpkgs.lib.genAttrs [ "aarch64-linux" "x86_64-linux" ] (
          system: fn system nixpkgs.legacyPackages.${system}
        );

      mkModuleWithDmsPkgs =
        modulePath:
        args@{ pkgs, ... }:
        {
          imports = [
            (import modulePath (args // { dmsPkgs = buildDmsPkgs pkgs; }))
          ];
        };

      mkQmlImportPath =
        pkgs: qmlPkgs:
        pkgs.lib.concatStringsSep ":" (map (o: "${o}/${pkgs.qt6.qtbase.qtQmlPrefix}") qmlPkgs);

      mkQtPluginPath =
        pkgs: qtPkgs:
        pkgs.lib.concatStringsSep ":" (map (o: "${o}/${pkgs.qt6.qtbase.qtPluginPrefix}") qtPkgs);

      qmlPkgs =
        pkgs: with pkgs.kdePackages; [
          kirigami.unwrapped
          sonnet
          qtmultimedia
          qtimageformats
          kimageformats
        ];

      # Allows downstream modules to provide their own 'pkgs' (with overlays)
      # instead of being forced to use the flake's locked nixpkgs.
      mkDmsShell =
        pkgs:
        let
          mkDate =
            longDate:
            pkgs.lib.concatStringsSep "-" [
              (builtins.substring 0 4 longDate)
              (builtins.substring 4 2 longDate)
              (builtins.substring 6 2 longDate)
            ];
          version =
            let
              rawVersion = pkgs.lib.removePrefix "v" (pkgs.lib.trim (builtins.readFile ./quickshell/VERSION));
              cleanVersion = builtins.replaceStrings [ " " ] [ "" ] rawVersion;
              dateSuffix = "+date=" + mkDate (self.lastModifiedDate or "19700101");
              revSuffix = "_" + (self.shortRev or "dirty");
            in
            "${cleanVersion}${dateSuffix}${revSuffix}";
        in
        pkgs.lib.makeOverridable (
          {
            extraQtPackages ? [ ],
          }:
          (pkgs.buildGoModule.override { go = goForPkgs pkgs; }) (
            let
              rootSrc = ./.;
              qtPackages = (qmlPkgs pkgs) ++ extraQtPackages;
            in
            {
              inherit version;
              pname = "dms-shell";
              src = ./core;
              vendorHash = "sha256-O8I6nXBTq2mQatLOUflWZO+q5Eg5GmrC3gZLx/jqS3U=";

              subPackages = [ "cmd/dms" ];

              ldflags = [
                "-s"
                "-w"
                "-X 'main.Version=${version}'"
              ];

              nativeBuildInputs = with pkgs; [
                installShellFiles
                makeWrapper
              ];

              postInstall = ''
                mkdir -p $out/share/quickshell/dms
                tar -C ${rootSrc}/quickshell --mode=u+w --exclude-from=${rootSrc}/scripts/shell-test-excludes.txt -cf - . \
                  | tar -C $out/share/quickshell/dms -xf -

                rm -f $out/share/quickshell/dms/DCommon
                tar -C ${dank-qml-common} --mode=u+w --exclude-from=${rootSrc}/scripts/shell-test-excludes.txt -cf - DCommon \
                  | tar -C $out/share/quickshell/dms -xf -

                echo "${version}" > $out/share/quickshell/dms/VERSION

                # Install desktop file and icon
                install -D ${rootSrc}/assets/dms-open.desktop \
                  $out/share/applications/dms-open.desktop
                install -D ${rootSrc}/assets/dev.duxlabs.shell.desktop \
                  $out/share/applications/dev.duxlabs.shell.desktop
                install -D ${rootSrc}/assets/dev.duxlabs.shell.notepad.desktop \
                  $out/share/applications/dev.duxlabs.shell.notepad.desktop
                install -D ${rootSrc}/assets/dev.duxlabs.shell.svg \
                  $out/share/icons/hicolor/scalable/apps/dev.duxlabs.shell.svg

                # Snapshot pre-wrap Qt paths so launched apps get their own, not DMS's pins.
                wrapProgram $out/bin/dms \
                  --add-flags "-c $out/share/quickshell/dms" \
                  --run 'export DMS_ORIG_NIXPKGS_QT6_QML_IMPORT_PATH="''${NIXPKGS_QT6_QML_IMPORT_PATH:-}"' \
                  --run 'export DMS_ORIG_QT_PLUGIN_PATH="''${QT_PLUGIN_PATH:-}"' \
                  --prefix "NIXPKGS_QT6_QML_IMPORT_PATH" ":" "${mkQmlImportPath pkgs qtPackages}" \
                  --prefix "QT_PLUGIN_PATH" ":" "${mkQtPluginPath pkgs qtPackages}"

                install -Dm644 ${rootSrc}/assets/systemd/dms.service \
                  $out/lib/systemd/user/dms.service

                substituteInPlace $out/lib/systemd/user/dms.service \
                  --replace-fail /usr/bin/dms $out/bin/dms \
                  --replace-fail /bin/kill ${pkgs.coreutils}/bin/kill

                substituteInPlace $out/share/quickshell/dms/assets/pam/fprint \
                  --replace-fail pam_fprintd.so ${pkgs.fprintd}/lib/security/pam_fprintd.so \
                  --replace-fail pam_deny.so ${pkgs.pam}/lib/security/pam_deny.so \
                  --replace-fail pam_permit.so ${pkgs.pam}/lib/security/pam_permit.so

                substituteInPlace $out/share/quickshell/dms/assets/pam/u2f \
                  --replace-fail pam_u2f.so ${pkgs.pam_u2f}/lib/security/pam_u2f.so \
                  --replace-fail pam_deny.so ${pkgs.pam}/lib/security/pam_deny.so \
                  --replace-fail pam_permit.so ${pkgs.pam}/lib/security/pam_permit.so

                substituteInPlace $out/share/quickshell/dms/assets/pam/other \
                  --replace-fail pam_deny.so ${pkgs.pam}/lib/security/pam_deny.so

                installShellCompletion --cmd dms \
                  --bash <($out/bin/dms completion bash) \
                  --fish <($out/bin/dms completion fish) \
                  --zsh <($out/bin/dms completion zsh)
              '';

              meta = {
                description = "Desktop shell for wayland compositors built with Quickshell & GO";
                homepage = "https://duxlabs.dev";
                changelog = "https://github.com/duxlabs-dev/dux-shell/releases/tag/v${version}";
                license = pkgs.lib.licenses.mit;
                mainProgram = "dms";
                platforms = pkgs.lib.platforms.linux;
              };
            }
          )
        ) { };

      buildDmsPkgs = pkgs: {
        dms-shell = mkDmsShell pkgs;
      };
    in
    {
      packages = forEachSystem (
        system: pkgs: {
          dms-shell = mkDmsShell pkgs;
          default = self.packages.${system}.dms-shell;
          quickshell = builtins.warn "dank-material-shell: the package Quickshell is not included in the DMS flake anymore. We recommend you to use the one from nixos-unstable branch of Nixpkgs or the upstream flake." pkgs.quickshell;
        }
      );

      lib = { inherit mkDmsShell buildDmsPkgs; };

      homeModules.dank-material-shell = mkModuleWithDmsPkgs ./distro/nix/home.nix;

      homeModules.default = self.homeModules.dank-material-shell;

      homeModules.niri = import ./distro/nix/niri.nix;

      homeModules.dankMaterialShell.default = builtins.warn "dank-material-shell: flake output `homeModules.dankMaterialShell.default` has been renamed to `homeModules.dank-material-shell`" self.homeModules.dank-material-shell;

      homeModules.dankMaterialShell.niri = builtins.warn "dank-material-shell: flake output `homeModules.dankMaterialShell.niri` has been renamed to `homeModules.niri`" self.homeModules.niri;

      nixosModules.dank-material-shell = mkModuleWithDmsPkgs ./distro/nix/nixos.nix;

      nixosModules.default = self.nixosModules.dank-material-shell;

      nixosModules.greeter = builtins.warn "dank-material-shell: the greeter moved to the dux-greeter repo; use `inputs.dank-greeter.nixosModules.default` and `programs.dms-greeter` (https://github.com/duxlabs-dev/dux-greeter)" { };

      nixosModules.dankMaterialShell = builtins.warn "dank-material-shell: flake output `nixosModules.dankMaterialShell` has been renamed to `nixosModules.dank-material-shell`" self.nixosModules.dank-material-shell;

      devShells = forEachSystem (
        system: pkgs:
        let
          devQmlPkgs = with pkgs;
          [
            quickshell
            kdePackages.qtdeclarative
          ]
          ++ (qmlPkgs pkgs);
        in
        {
          default = pkgs.mkShell {
            buildInputs =
              with pkgs;
              [
                (goForPkgs pkgs)
                go-mockery
                gopls
                delve
                go-tools
                gnumake
                nodejs
                lua
                python3
                matugen

                prek
                uv # for prek
                shellcheck

                # Nix development tools
                nixd
                nil
              ]
              ++ devQmlPkgs;

            shellHook = ''
              touch quickshell/.qmlls.ini 2>/dev/null
              if [ ! -f .git/hooks/pre-commit ]; then prek install; fi
            '';

            QML2_IMPORT_PATH = mkQmlImportPath pkgs devQmlPkgs;
            QT_PLUGIN_PATH = mkQtPluginPath pkgs devQmlPkgs;
          };
        }
      );

      nixosTests = forEachLinuxSystem (
        system: pkgs:
        import ./distro/nix/tests {
          inherit
            self
            pkgs
            ;
          lib = pkgs.lib;
        }
      );
    };
}
