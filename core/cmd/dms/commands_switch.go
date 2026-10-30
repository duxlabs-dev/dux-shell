package main

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"
	"syscall"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/internal/backup"
	"github.com/duxlabs-dev/dux-shell/core/internal/deps"
	"github.com/duxlabs-dev/dux-shell/core/internal/distros"
	"github.com/duxlabs-dev/dux-shell/core/internal/privesc"
	"github.com/spf13/cobra"
)

const switchDMSDep = "dms (Dux Shell)"

// The greeter runs the shell's QML, so it moves with dms or the login screen can break.
var switchFamily = []string{switchDMSDep, "quickshell", "dms-greeter"}

var switchAliases = map[string]string{
	"dms":          switchDMSDep,
	"quickshell":   "quickshell",
	"dms-greeter":  "dms-greeter",
	"greeter":      "dms-greeter",
	"dankcalendar": "dankcalendar",
	"danksearch":   "danksearch",
}

var switchAssumeYes bool

var switchCmd = &cobra.Command{
	Use:   "switch <stable|beta> [package...]",
	Short: "Switch DMS packages between stable and beta builds",
	Long: `Switch installed DMS packages between stable releases and beta builds.

With no packages, dms, quickshell and dms-greeter switch together. Name packages
(dms, quickshell, greeter, dankcalendar, danksearch) to switch only those.

Settings, plugins, themes and session state are backed up before anything changes.
Settings written by beta can lose options on stable, so switching back to stable
offers to restore the backup taken the last time you left stable.`,
	Args:      cobra.MinimumNArgs(1),
	ValidArgs: []string{"stable", "beta"},
	Run: func(cmd *cobra.Command, args []string) {
		if err := runSwitch(args[0], args[1:]); err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}
	},
}

func init() {
	switchCmd.Flags().BoolVarP(&switchAssumeYes, "yes", "y", false, "Do not ask for confirmation; keeps current settings when switching to stable")
}

func runSwitch(channel string, packages []string) error {
	var target deps.PackageVariant
	switch channel {
	case "stable":
		target = deps.VariantStable
	case "beta":
		target = deps.VariantGit
	default:
		return fmt.Errorf("unknown channel %q: use stable or beta", channel)
	}

	explicit := len(packages) > 0
	names := switchFamily
	if explicit {
		names = nil
		for _, pkg := range packages {
			name, ok := switchAliases[strings.ToLower(pkg)]
			if !ok {
				return fmt.Errorf("unknown package %q", pkg)
			}
			names = append(names, name)
		}
	}

	osInfo, err := distros.GetOSInfo()
	if err != nil {
		return fmt.Errorf("detecting distribution: %w", err)
	}
	distro, err := distros.NewDistribution(osInfo.Distribution.ID, nil)
	if err != nil {
		return err
	}

	// The package names are compositor independent, so any window manager works here.
	var wm deps.WindowManager
	var swaps []distros.VariantSwap
	for _, name := range names {
		swap, status := distros.PlanVariantSwap(distro, wm, name, target)
		switch status {
		case distros.SwapNeeded:
			swaps = append(swaps, swap)
		case distros.SwapUnsupported:
			return fmt.Errorf("switching packages is not supported on %s", osInfo.PrettyName)
		case distros.SwapAlreadyOnTarget:
			fmt.Printf("%s is already on %s\n", name, channel)
		case distros.SwapNoVariant:
			if explicit {
				fmt.Printf("%s has no separate beta build on %s\n", name, osInfo.PrettyName)
			}
		case distros.SwapNotInstalled:
			if explicit {
				fmt.Printf("%s is not installed from a package\n", name)
			}
		}
	}
	if len(swaps) == 0 {
		fmt.Println("Nothing to switch.")
		return nil
	}

	shellChanges := false
	snapshotLabel := ""
	fmt.Printf("\nSwitching to %s:\n", channel)
	for _, swap := range swaps {
		fmt.Printf("  %s → %s\n", switchLabel(swap.From), switchLabel(swap.To))
		switch swap.Dep {
		case switchDMSDep:
			shellChanges = true
			snapshotLabel = "stable"
			if target == deps.VariantStable {
				snapshotLabel = "beta"
			}
		case "quickshell":
			shellChanges = true
		}
	}
	if snapshotLabel != "" {
		dir, _ := backup.SnapshotDir()
		fmt.Printf("\nYour DMS settings will be backed up to %s first.\n", dir)
	}
	if shellChanges {
		fmt.Println("The shell restarts when the switch is done.")
	}
	if !switchAssumeYes && !askYes("\nContinue? [y/N] ") {
		return errors.New("cancelled")
	}

	if snapshotLabel != "" {
		path, err := backup.Snapshot(snapshotLabel)
		if err != nil {
			return fmt.Errorf("backing up settings, nothing was changed: %w", err)
		}
		if path != "" {
			fmt.Printf("Backed up settings to %s\n", path)
		}
	}

	ctx := context.Background()
	if privesc.CheckCached(ctx) != nil {
		if err := privesc.Run(ctx, "", "true"); err != nil {
			return fmt.Errorf("authentication failed: %w", err)
		}
	}

	if err := runSwaps(ctx, distro.(distros.VariantSwapper), swaps); err != nil {
		return err
	}

	restore := ""
	if snapshotLabel == "beta" && !switchAssumeYes {
		if path, ok := backup.LatestSnapshot("stable"); ok {
			fmt.Printf("\nSettings saved by beta may lose options on stable. Restore the backup from your last\nstable run (%s)? Your beta settings stay in the beta backup. [y/N] ", path)
			if askYes("") {
				restore = path
			}
		}
	}

	if shellChanges || restore != "" {
		return restartShellAfterSwitch(restore)
	}
	fmt.Println("Done.")
	return nil
}

func runSwaps(ctx context.Context, swapper distros.VariantSwapper, swaps []distros.VariantSwap) error {
	return runWithProgressOutput(func(progressChan chan<- distros.InstallProgressMsg) error {
		return swapper.SwapVariants(ctx, swaps, "", progressChan)
	})
}

func runWithProgressOutput(run func(chan<- distros.InstallProgressMsg) error) error {
	return runWithProgressOutputTo(os.Stdout, run)
}

func runWithProgressOutputTo(out io.Writer, run func(chan<- distros.InstallProgressMsg) error) error {
	progressChan := make(chan distros.InstallProgressMsg, 100)
	runErr := make(chan error, 1)
	go func() {
		defer close(progressChan)
		runErr <- run(progressChan)
	}()

	// runWithProgress repeats the step and the last output line on every tick, so only print changes.
	lastStep, lastLog := "", ""
	for msg := range progressChan {
		switch {
		case msg.Error != nil:
			fmt.Fprintf(os.Stderr, "Error: %v\n", msg.Error)
		case msg.Step != "" && msg.Step != lastStep:
			fmt.Fprintln(out, msg.Step)
			lastStep = msg.Step
		}
		if msg.LogOutput != "" && msg.LogOutput != lastLog {
			fmt.Fprintf(out, "    %s\n", msg.LogOutput)
			lastLog = msg.LogOutput
		}
	}
	return <-runErr
}

// restartShellAfterSwitch stops the shell before restoring, or the running one would migrate the
// restored settings and save them back. A plain restart would also reload the old binary's QML.
func restartShellAfterSwitch(restore string) error {
	managed := runSystemctl("--user", "is-active", "--quiet", dmsSystemdUnit) == nil
	if managed {
		if err := runSystemctl("--user", "stop", dmsSystemdUnit); err != nil {
			return fmt.Errorf("stopping the shell: %w", err)
		}
	} else {
		stopShellForSwitch()
	}

	if restore != "" {
		if err := backup.RestoreSnapshot(restore); err != nil {
			fmt.Fprintf(os.Stderr, "Restoring settings failed: %v\n", err)
		} else {
			fmt.Printf("Restored settings from %s\n", restore)
		}
	}

	if managed {
		if err := runSystemctl("--user", "start", dmsSystemdUnit); err != nil {
			return fmt.Errorf("starting the shell: %w", err)
		}
	} else {
		dmsPath, err := exec.LookPath("dms")
		if err != nil {
			return fmt.Errorf("switch done, but dms was not found to start the shell: %w", err)
		}
		if err := exec.Command(dmsPath, "run", "-d").Run(); err != nil {
			return fmt.Errorf("switch done, but starting the shell failed (run 'dms run -d'): %w", err)
		}
	}
	fmt.Println("Done. The shell has restarted.")
	return nil
}

// stopShellForSwitch terminates the supervisors and waits for them: Kill() would SIGKILL them,
// orphaning quickshell in its own session, which then keeps saving settings over the restore.
func stopShellForSwitch() {
	for _, pid := range shellApp.PIDs() {
		if proc, err := os.FindProcess(pid); err == nil {
			proc.Signal(syscall.SIGTERM)
		}
	}
	deadline := time.Now().Add(5 * time.Second)
	for len(shellApp.PIDs()) > 0 && time.Now().Before(deadline) {
		time.Sleep(100 * time.Millisecond)
	}
	shellApp.Kill()
}

func switchLabel(m distros.PackageMapping) string {
	if m.RepoURL == "" {
		return m.Name
	}
	return m.RepoURL + "/" + m.Name
}

func askYes(prompt string) bool {
	if !stdinIsTTY() {
		return false
	}
	fmt.Print(prompt)
	line, err := bufio.NewReader(os.Stdin).ReadString('\n')
	if err != nil {
		return false
	}
	answer := strings.ToLower(strings.TrimSpace(line))
	return answer == "y" || answer == "yes"
}
