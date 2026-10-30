package main

import (
	"fmt"
	"os"
	"os/exec"
	"syscall"

	"github.com/duxlabs-dev/dux-shell/core/internal/distros"
	"github.com/duxlabs-dev/dux-shell/core/internal/site"
	"github.com/spf13/cobra"
)

var greeterCmd = &cobra.Command{
	Use:                "greeter",
	Short:              "Deprecated: moved to the standalone dms-greeter binary",
	Long:               "The greeter has moved to the standalone dux-greeter package.\nThis command forwards to 'dms-greeter' when it is installed.",
	DisableFlagParsing: true,
	SilenceUsage:       true,
	RunE: func(_ *cobra.Command, args []string) error {
		binary, err := exec.LookPath("dms-greeter")
		if err != nil {
			return fmt.Errorf("'dms greeter' has moved to the standalone dux-greeter package.\n  %s", greeterPackageInstallHint())
		}
		if isLegacyWrapperScript(binary) {
			return fmt.Errorf("'dms greeter' has moved to the standalone dux-greeter package; %s is the old wrapper script.\n  %s", binary, greeterPackageInstallHint())
		}
		fmt.Fprintln(os.Stderr, "warning: 'dms greeter' is deprecated; use 'dms-greeter' directly")
		return syscall.Exec(binary, append([]string{"dms-greeter"}, args...), os.Environ())
	},
}

func greeterRepoURL(config distros.DistroConfig) string {
	return config.Constructor(config, nil).GetPackageMapping(0)["dms-greeter"].RepoURL
}

func isLegacyWrapperScript(path string) bool {
	file, err := os.Open(path)
	if err != nil {
		return false
	}
	defer file.Close()
	header := make([]byte, 2)
	if _, err := file.Read(header); err != nil {
		return false
	}
	return string(header) == "#!"
}

func greeterPackageInstallHint() string {
	osInfo, err := distros.GetOSInfo()
	if err != nil {
		return "Install package: dux-greeter"
	}
	config, exists := distros.Registry[osInfo.Distribution.ID]
	if !exists {
		return "Install package: dux-greeter"
	}

	if config.ID == "pika" {
		return "Install with 'sudo apt install dms-greeter'"
	}

	switch config.Family {
	case distros.FamilyDebian:
		return "Install with 'sudo apt install dux-greeter' (requires Dux Labs OBS repo — see " + site.Docs + "/dms-greeter/installation#debian)"
	case distros.FamilySUSE:
		return "Install with 'sudo zypper install dux-greeter' (requires Dux Labs OBS repo — see " + site.Docs + "/dms-greeter/installation#opensuse--derivatives)"
	case distros.FamilyUbuntu:
		repo := greeterRepoURL(config)
		return fmt.Sprintf("Install with 'sudo apt install dux-greeter' (requires %s: sudo add-apt-repository %s)", repo, repo)
	case distros.FamilyFedora:
		return fmt.Sprintf("Install with 'sudo dnf install dux-greeter' (requires COPR: sudo dnf copr enable %s)", greeterRepoURL(config))
	case distros.FamilyArch:
		return "Install from AUR with 'paru -S dux-greeter-bin' or 'yay -S dux-greeter-bin'"
	case distros.FamilyVoid:
		return "Install with 'sudo xbps-install -S dux-greeter' (requires DMS XBPS repo: echo 'repository=" + distros.VoidDepsRepo + "' | sudo tee /etc/xbps.d/dux.conf)"
	default:
		return "Install the dux-greeter package for your distribution"
	}
}
