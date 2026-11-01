{
  self,
  pkgs,
  ...
}:
let
  homeManagerNixosModule =
    (fetchTarball {
      url = "https://github.com/nix-community/home-manager/archive/53ebbdc405acc04acd9bb73ccca462b51ddb8c6d.tar.gz";
      sha256 = "1cqmfgwb3jac2zzv82bwvgypxff1z30xkz9j6qcinkmqf58j3k3b";
    })
    + "/nixos";
in
pkgs.testers.runNixOSTest {
  name = "dms-home-manager-module";

  nodes.machine = {
    ...
  }: {
    imports = [
      homeManagerNixosModule
    ];

    users.users.danklinux = {
      isNormalUser = true;
      createHome = true;
      home = "/home/danklinux";
      extraGroups = [ "wheel" ];
    };

    home-manager.useGlobalPkgs = true;
    home-manager.useUserPackages = true;

    home-manager.users.danklinux = {
      pkgs,
      ...
    }: {
      imports = [
        self.homeModules.dank-material-shell
      ];

      home.username = "danklinux";
      home.homeDirectory = "/home/danklinux";
      home.stateVersion = "25.11";

      programs.dank-material-shell = {
        enable = true;
        systemd = {
          enable = true;
          target = "default.target";
        };

        settings = {
          theme = "integration-test";
        };

        clipboardSettings = {
          maxItems = 10;
        };

        session = {
          startedFrom = "nixos-test";
        };

        plugins.TestPlugin = {
          enable = true;
          src = pkgs.runCommand "dms-test-plugin" { } ''
            mkdir -p "$out"
            echo plugin > "$out/plugin.txt"
          '';
          settings = {
            enabled = true;
            source = "test";
          };
        };
      };
    };

    system.stateVersion = "25.11";
  };

  testScript = ''
    import json

    machine.wait_for_unit("multi-user.target")

    machine.succeed("su -- danklinux -c 'command -v dms'")
    machine.succeed("su -- danklinux -c 'test -f ~/.config/dms/settings.json'")
    machine.succeed("su -- danklinux -c 'test -f ~/.config/dms/clsettings.json'")
    machine.succeed("su -- danklinux -c 'test -f ~/.config/dms/plugin_settings.json'")
    machine.succeed("su -- danklinux -c 'test -e ~/.config/dms/plugins/TestPlugin'")
    machine.succeed("su -- danklinux -c 'test -f ~/.local/state/dms/session.json'")

    settings = json.loads(machine.succeed("su -- danklinux -c 'cat ~/.config/dms/settings.json'"))
    clipboard = json.loads(machine.succeed("su -- danklinux -c 'cat ~/.config/dms/clsettings.json'"))
    session = json.loads(machine.succeed("su -- danklinux -c 'cat ~/.local/state/dms/session.json'"))
    plugins = json.loads(machine.succeed("su -- danklinux -c 'cat ~/.config/dms/plugin_settings.json'"))
    doctor = json.loads(machine.succeed("su -- danklinux -c 'dms doctor --json'"))

    t.assertEqual(settings["theme"], "integration-test")
    t.assertEqual(clipboard["maxItems"], 10)
    t.assertEqual(session["startedFrom"], "nixos-test")
    t.assertTrue(plugins["TestPlugin"]["enabled"])
    t.assertEqual(plugins["TestPlugin"]["source"], "test")
    t.assertIsInstance(doctor.get("results"), list)
  '';
}
