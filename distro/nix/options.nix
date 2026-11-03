{
  lib,
  dmsPkgs,
  pkgs,
  ...
}:
let
  inherit (lib) types;
  path = [
    "programs"
    "dank-material-shell"
  ];
  jsonFormat = pkgs.formats.json { };
  builtInRemovedMsg = "This is now built-in in DMS and doesn't need additional dependencies.";
in
{
  imports = [
    (lib.mkRemovedOptionModule (path ++ [ "enableBrightnessControl" ]) builtInRemovedMsg)
    (lib.mkRemovedOptionModule (path ++ [ "enableColorPicker" ]) builtInRemovedMsg)
    (lib.mkRemovedOptionModule (path ++ [ "enableClipboard" ]) builtInRemovedMsg)
    (lib.mkRemovedOptionModule (
      path ++ [ "enableSystemSound" ]
    ) "qtmultimedia is now included on dms-shell package.")
    ./dms-rename.nix
  ];

  options.programs.dank-material-shell = {
    enable = lib.mkEnableOption "Dux Shell";
    package = lib.mkPackageOption dmsPkgs "dms-shell" {
      extraDescription = "The Dux Shell package to use (defaults to be built from source)";
    };

    systemd = {
      enable = lib.mkEnableOption "Dux Shell systemd startup";
      restartIfChanged = lib.mkOption {
        type = types.bool;
        default = true;
        description = "Auto-restart dms.service when dank-material-shell changes";
      };
    };

    enableSystemMonitoring = lib.mkOption {
      type = types.bool;
      default = true;
      description = "Enable system monitoring widgets and keybinds";
    };

    enableVPN = lib.mkOption {
      type = types.bool;
      default = true;
      description = "Add needed dependencies to use the VPN widget";
    };

    enableDynamicTheming = lib.mkOption {
      type = types.bool;
      default = true;
      description = "Add needed dependencies to have dynamic theming support";
    };

    enableAudioWavelength = lib.mkOption {
      type = types.bool;
      default = true;
      description = "Add needed dependencies to have audio wavelength support";
    };

    enableCalendarEvents = lib.mkOption {
      type = types.bool;
      default = true;
      description = "Add calendar events support via khal";
    };

    enableClipboardPaste = lib.mkOption {
      type = types.bool;
      default = true;
      description = "Deprecated: paste is built into dms; no extra dependencies needed. Kept as a no-op for compatibility.";
    };

    quickshell = {
      package = lib.mkPackageOption pkgs "quickshell" {
        extraDescription = "(we recommend at least 0.3.0, currently available in nixos-unstable)";
      };
    };

    plugins = lib.mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            enable = lib.mkOption {
              type = types.bool;
              default = true;
              description = "Whether to enable this plugin";
            };
            src = lib.mkOption {
              type = types.either types.package types.path;
              description = "Source of the plugin package or path";
            };
            settings = lib.mkOption {
              type = jsonFormat.type;
              default = { };
              description = "Plugin settings as an attribute set";
            };
          };
        }
      );
      default = { };
      description = "DMS Plugins to install and enable";
      example = lib.literalExpression ''
        {
          DockerManager = {
            src = pkgs.fetchFromGitHub {
              owner = "LuckShiba";
              repo = "DmsDockerManager";
              rev = "v1.2.0";
              sha256 = "sha256-VoJCaygWnKpv0s0pqTOmzZnPM922qPDMHk4EPcgVnaU=";
            };
          };
          AnotherPlugin = {
            enable = true;
            src = pkgs.another-plugin;
          };
        }
      '';
    };
  };
}
