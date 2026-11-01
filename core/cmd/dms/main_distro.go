//go:build distro_binary

package main

import (
	"os"

	"github.com/duxlabs-dev/dux-shell/core/internal/clipboard"
	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/duxlabs-dev/dux-shell/core/internal/utils"
)

var Version = "dev"

func init() {
	authCmd.AddCommand(authSyncCmd, authResolveLockCmd, authListServicesCmd, authValidateCmd)
	setupCmd.AddCommand(setupHeadlessCmd, setupBindsCmd, setupLayoutCmd, setupColorsCmd, setupAlttabCmd, setupOutputsCmd, setupCursorCmd, setupWindowrulesCmd)
	pluginsCmd.AddCommand(pluginsBrowseCmd, pluginsListCmd, pluginsInstallCmd, pluginsUninstallCmd, pluginsUpdateCmd, pluginsLockCmd, pluginsRestoreCmd)
	rootCmd.AddCommand(getCommonCommands()...)
	rootCmd.AddCommand(authCmd)

	rootCmd.SetHelpTemplate(getHelpTemplate())
}

func main() {
	disableMemProfilingUnlessRequested()
	clipboard.MaybeServeAndExit()

	if os.Geteuid() == 0 && !isReadOnlyCommand(os.Args) && !isRootHelper(os.Args) {
		log.Fatal("This program should not be run as root. Exiting.")
	}

	if os.Geteuid() != 0 {
		for _, err := range utils.MigrateLegacyDirs() {
			log.Warnf("dms dir migration: %v", err)
		}
	}

	os.Args = normalizeDmenuArgv(os.Args)
	if err := rootCmd.Execute(); err != nil {
		log.Fatal(err)
	}
}
