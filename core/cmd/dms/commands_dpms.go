package main

import (
	"fmt"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/spf13/cobra"
)

var dpmsCmd = &cobra.Command{
	Use:   "dpms",
	Short: "Control display power management",
}

var dpmsOnCmd = &cobra.Command{
	Use:   "on [output]",
	Short: "Turn display(s) on",
	Args:  cobra.MaximumNArgs(1),
	ValidArgsFunction: func(cmd *cobra.Command, args []string, toComplete string) ([]string, cobra.ShellCompDirective) {
		if len(args) != 0 {
			return nil, cobra.ShellCompDirectiveNoFileComp
		}
		return getDPMSOutputs(), cobra.ShellCompDirectiveNoFileComp
	},
	Run: runDPMSOn,
}

var dpmsOffCmd = &cobra.Command{
	Use:   "off [output]",
	Short: "Turn display(s) off",
	Args:  cobra.MaximumNArgs(1),
	ValidArgsFunction: func(cmd *cobra.Command, args []string, toComplete string) ([]string, cobra.ShellCompDirective) {
		if len(args) != 0 {
			return nil, cobra.ShellCompDirectiveNoFileComp
		}
		return getDPMSOutputs(), cobra.ShellCompDirectiveNoFileComp
	},
	Run: runDPMSOff,
}

var dpmsListCmd = &cobra.Command{
	Use:   "list",
	Short: "List outputs",
	Args:  cobra.NoArgs,
	Run:   runDPMSList,
}

func init() {
	dpmsCmd.AddCommand(dpmsOnCmd, dpmsOffCmd, dpmsListCmd)
}

func runDPMSOn(cmd *cobra.Command, args []string) {
	outputName := ""
	if len(args) > 0 {
		outputName = args[0]
	}

	client, err := newDPMSClient()
	if err != nil {
		log.Fatalf("%v", err)
	}
	defer client.Close()

	if err := client.SetDPMS(outputName, true); err != nil {
		log.Fatalf("%v", err)
	}
}

func runDPMSOff(cmd *cobra.Command, args []string) {
	outputName := ""
	if len(args) > 0 {
		outputName = args[0]
	}

	client, err := newDPMSClient()
	if err != nil {
		log.Fatalf("%v", err)
	}
	defer client.Close()

	if err := client.SetDPMS(outputName, false); err != nil {
		log.Fatalf("%v", err)
	}
}

func getDPMSOutputs() []string {
	client, err := newDPMSClient()
	if err != nil {
		return nil
	}
	defer client.Close()
	return client.ListOutputs()
}

func runDPMSList(cmd *cobra.Command, args []string) {
	client, err := newDPMSClient()
	if err != nil {
		log.Fatalf("%v", err)
	}
	defer client.Close()

	for _, output := range client.ListOutputs() {
		fmt.Println(output)
	}
}
