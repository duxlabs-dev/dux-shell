{
  config,
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
    (lib.mkRemovedOptionModule (
      path ++ [ "quickshell" "package" ]
    ) "The Quickshell runtime is embedded in dms as dux-qt-base; set programs.dank-material-shell.duxQtBase.package instead.")
    ./dms-rename.nix
  ];

  options.programs.dank-material-shell = {
    enable = lib.mkEnableOption "Dux Modular Shell";
    package = lib.mkOption {
      type = types.package;
      default = dmsPkgs.dms-shell.override { duxQtBase = config.programs.dank-material-shell.duxQtBase.package; };
      defaultText = lib.literalExpression "dmsPkgs.dms-shell.override { duxQtBase = config.programs.dank-material-shell.duxQtBase.package; }";
      description = "The Dux Modular Shell package to use (defaults to be built from source against duxQtBase.package)";
    };

    systemd = {
      enable = lib.mkEnableOption "Dux Modular Shell systemd startup";
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

    duxQtBase = {
      package = lib.mkPackageOption dmsPkgs "dux-qt-base" {
        extraDescription = "The Quickshell runtime library embedded in the dms package (defaults to the pinned dux-qt-base flake input, built against this system's nixpkgs).";
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
