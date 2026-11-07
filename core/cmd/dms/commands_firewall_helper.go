package main

import (
	"os"

	"github.com/duxlabs-dev/dux-shell/core/internal/server/firewall"
	"github.com/spf13/cobra"
)

// Started through pkexec when the firewall page is unlocked; exits when stdin closes.
var firewallHelperCmd = &cobra.Command{
	Use:    "firewall-helper",
	Short:  "Privileged ufw access for the firewall settings (started through pkexec)",
	Hidden: true,
	Args:   cobra.NoArgs,
	Run: func(cmd *cobra.Command, args []string) {
		go exitWhenOrphaned()
		serveSysmonHelper(os.Stdin, os.Stdout, firewall.NewHelper().Call)
	},
}
