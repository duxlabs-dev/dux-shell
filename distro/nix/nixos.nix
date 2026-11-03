{
  config,
  pkgs,
  lib,
  ...
}@args:
let
  cfg = config.programs.dank-material-shell;
  common = import ./common.nix {
    inherit
      config
      pkgs
      lib
      ;
  };
in
{
  imports = [
    (import ./options.nix args)
  ];
  options.programs.dank-material-shell.systemd.target = lib.mkOption {
    type = lib.types.str;
    description = "Systemd target to bind to.";
    default = "graphical-session.target";
  };
  options.programs.dank-material-shell.lockscreen.securityKey = {
    enable = lib.mkEnableOption "FIDO2/U2F security key unlock for the DMS lock screen via a dedicated dankshell-u2f PAM service";
    package = lib.mkPackageOption pkgs "pam_u2f" { };
    moduleArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "cue" ];
      description = "Arguments passed to pam_u2f.so in the dankshell-u2f PAM service.";
    };
  };
  config = lib.mkIf cfg.enable {
    systemd.user.services.dms = lib.mkIf cfg.systemd.enable {
      description = "Dux Shell";
      path = lib.mkForce [ ];

      partOf = [ cfg.systemd.target ];
      after = [ cfg.systemd.target ];
      wantedBy = [ cfg.systemd.target ];
      restartIfChanged = cfg.systemd.restartIfChanged;

      serviceConfig = {
        Type = "notify";
        BusName = "org.freedesktop.Notifications";
        NotifyAccess = "main";
        Environment = [ "QS_DISABLE_CRASH_HANDLER=1" ];
        ExecStart = lib.getExe cfg.package + " run --session";
        Restart = "on-failure";
        RestartForceExitStatus = "TEMPFAIL";
        SuccessExitStatus = "TEMPFAIL";
      };
    };

    environment.systemPackages = [ cfg.quickshell.package ] ++ common.packages;

    environment.etc = lib.mapAttrs' (name: value: {
      name = "xdg/quickshell/dms-plugins/${name}";
      inherit value;
    }) common.plugins;

    # DMS's bundled U2F fallback stack references pam_u2f.so by name, which NixOS's
    # libpam cannot resolve; the dedicated service below uses the absolute store path
    # and is picked up automatically by the lock screen when present.
    security.pam.services."dankshell-u2f" = lib.mkIf cfg.lockscreen.securityKey.enable {
      text = ''
        auth     required ${cfg.lockscreen.securityKey.package}/lib/security/pam_u2f.so ${lib.concatStringsSep " " cfg.lockscreen.securityKey.moduleArgs}
        account  required pam_permit.so
        password required pam_deny.so
        session  required pam_permit.so
      '';
    };

    services.power-profiles-daemon.enable = lib.mkDefault true;
    services.accounts-daemon.enable = lib.mkDefault true;
    services.geoclue2.enable = lib.mkDefault true;
    security.polkit.enable = lib.mkDefault true;
  };
}
