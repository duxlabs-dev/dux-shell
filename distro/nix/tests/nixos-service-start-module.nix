{
  self,
  pkgs,
  ...
}:
let
  fakeDms = pkgs.writeShellScriptBin "dms" ''
    printf '%s\n' "$@" > /tmp/dms-service-args
    status="Shell ready"
    if test -f /tmp/dms-readiness-timeout; then
      status="Shell started with a readiness warning: shell readiness timed out: UI did not report readiness"
    fi
    exec ${pkgs.systemd}/bin/systemd-notify --ready --status="$status" --pid=self --exec \; -- ${pkgs.coreutils}/bin/sleep 300
  '';
in
pkgs.testers.runNixOSTest {
  name = "dms-nixos-service-start-module";

  nodes.machine = {
    imports = [
      self.nixosModules.dank-material-shell
    ];

    users.users.danklinux = {
      isNormalUser = true;
      linger = true;
      extraGroups = [ "wheel" ];
    };

    programs.dank-material-shell = {
      enable = true;
      package = fakeDms;
      systemd = {
        enable = true;
        target = "default.target";
      };
    };

    system.stateVersion = "25.11";
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("user@1000.service")

    machine.succeed("systemctl --machine=danklinux@ --user start dms.service")
    machine.wait_until_succeeds("systemctl --machine=danklinux@ --user is-active dms.service")
    machine.wait_until_succeeds("test -f /tmp/dms-service-args")
    machine.succeed("grep -Fx run /tmp/dms-service-args")
    machine.succeed("grep -Fx -- --session /tmp/dms-service-args")

    machine.succeed("systemctl --machine=danklinux@ --user stop dms.service")
    machine.succeed("touch /tmp/dms-readiness-timeout")
    machine.succeed("systemctl --machine=danklinux@ --user start dms.service")
    machine.wait_until_succeeds("systemctl --machine=danklinux@ --user is-active dms.service")
    assert machine.succeed("systemctl --machine=danklinux@ --user show dms.service -p StatusText --value").strip() == "Shell started with a readiness warning: shell readiness timed out: UI did not report readiness"
    assert machine.succeed("systemctl --machine=danklinux@ --user show dms.service -p NRestarts --value").strip() == "0"

    machine.succeed("systemctl --machine=danklinux@ --user stop dms.service")
    machine.succeed("rm /tmp/dms-readiness-timeout")
    machine.succeed("systemctl --machine=danklinux@ --user start dms.service")
    machine.wait_until_succeeds("systemctl --machine=danklinux@ --user is-active dms.service")
  '';
}
