{
  self,
  pkgs,
  ...
}:
pkgs.testers.runNixOSTest {
  name = "dms-nixos-module";

  nodes.machine = {
    imports = [
      self.nixosModules.dank-material-shell
    ];

    users.users.danklinux = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
    };

    programs.dank-material-shell = {
      enable = true;
      systemd.enable = true;
      lockscreen.securityKey.enable = true;
      plugins = {
        TestPlugin = {
          src = pkgs.emptyDirectory;
        };
      };
    };

    system.stateVersion = "25.11";
  };

  testScript = ''
    import json

    machine.wait_for_unit("multi-user.target")

    machine.succeed("command -v dms")
    machine.succeed("su -- danklinux -c 'dms --help >/dev/null'")
    machine.succeed("test -d /etc/xdg/quickshell/dms-plugins")
    machine.succeed("test -f /run/current-system/sw/lib/systemd/user/dms.service")
    machine.succeed("grep -q 'lib/security/pam_u2f.so cue' /etc/pam.d/dankshell-u2f")

    payload = json.loads(machine.succeed("su -- danklinux -c 'dms doctor --json'"))
    t.assertIn("summary", payload)
    t.assertIsInstance(payload.get("results"), list)
  '';
}
