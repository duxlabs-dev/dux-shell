package main

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"runtime"
	"strings"
	"time"

	"github.com/charmbracelet/lipgloss"
	"github.com/duxlabs-dev/dux-go/ipc"
	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/duxlabs-dev/dux-shell/core/internal/lowprio"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/sysupdate"
	"github.com/spf13/cobra"
)

var systemCmd = &cobra.Command{
	Use:   "system",
	Short: "System operations",
	Long:  "System-level operations (updates, etc.). Runs against installed package managers directly; does not require the DMS server.",
}

var systemUpdateCmd = &cobra.Command{
	Use:   "update",
	Short: "Apply or list system updates",
	Long: `Apply or list system updates across detected package managers.

Default behavior is to apply available updates after prompting for confirmation.
Use --check to list updates without applying.

Examples:
  dms system update --check                  # list available updates
  dms system update                          # apply updates (interactive prompt)
  dms system update --noconfirm              # apply updates without prompting
  dms system update --interactive            # let the package manager ask its own questions
  dms system update --dry                    # simulate without changing anything
  dms system update --no-flatpak --noconfirm # apply system updates only
  dms system update --interval 3600          # set the server poll interval to 1h`,
	Run: runSystemUpdate,
}

var (
	sysUpdateCheck       bool
	sysUpdateNoConfirm   bool
	sysUpdateInteractive bool
	sysUpdateDry         bool
	sysUpdateJSON        bool
	sysUpdateNoFlatpak   bool
	sysUpdateNoAUR       bool
	sysUpdateIgnore      []string
	sysUpdateIntervalS   int
	sysUpdateListPmTime  = 5 * time.Minute
)

func init() {
	systemUpdateCmd.Flags().BoolVar(&sysUpdateCheck, "check", false, "List available updates without applying")
	systemUpdateCmd.Flags().BoolVarP(&sysUpdateNoConfirm, "noconfirm", "y", false, "Apply updates without prompting")
	systemUpdateCmd.Flags().BoolVar(&sysUpdateInteractive, "interactive", false, "Let the package manager ask its own questions instead of answering yes")
	systemUpdateCmd.Flags().BoolVar(&sysUpdateDry, "dry", false, "Simulate the upgrade without applying changes")
	systemUpdateCmd.Flags().BoolVar(&sysUpdateJSON, "json", false, "Output as JSON (with --check)")
	systemUpdateCmd.Flags().BoolVar(&sysUpdateNoFlatpak, "no-flatpak", false, "Skip the Flatpak overlay")
	systemUpdateCmd.Flags().BoolVar(&sysUpdateNoAUR, "no-aur", false, "Skip AUR updates")
	systemUpdateCmd.Flags().StringSliceVar(&sysUpdateIgnore, "ignore", nil, "Skip specific packages (repeatable or comma-separated)")
	systemUpdateCmd.Flags().IntVar(&sysUpdateIntervalS, "interval", -1, "Set the DMS server poll interval in seconds and exit (requires running server)")

	systemCmd.AddCommand(systemUpdateCmd)
}

func runSystemUpdate(cmd *cobra.Command, args []string) {
	if sysUpdateIntervalS >= 0 {
		runSystemUpdateSetInterval(sysUpdateIntervalS)
		return
	}

	// Package managers started from this thread inherit its priority.
	runtime.LockOSThread()
	lowprio.LowerThreadPriority()
	if sysUpdateCheck {
		runSystemUpdateCheck()
		return
	}
	runSystemUpdateApply()
}

func selectBackends(ctx context.Context) []sysupdate.Backend {
	sel := sysupdate.Select(ctx)
	backends := sel.All()
	if !sysUpdateNoFlatpak {
		return backends
	}
	out := backends[:0]
	for _, b := range backends {
		if b.Repo() == sysupdate.RepoFlatpak {
			continue
		}
		out = append(out, b)
	}
	return out
}

func runSystemUpdateCheck() {
	ctx, cancel := context.WithTimeout(context.Background(), sysUpdateListPmTime)
	defer cancel()

	backends := selectBackends(ctx)
	if len(backends) == 0 {
		log.Fatal("No supported package manager found")
	}

	stopSpin := startSpinner("Checking for updates… ")
	allPkgs, firstErr := collectUpdates(ctx, backends)
	stopSpin()
	allPkgs = filterUpdateTargets(allPkgs)

	if sysUpdateJSON {
		out, _ := json.MarshalIndent(map[string]any{
			"backends": backendResults(backends, allPkgs),
			"packages": allPkgs,
			"error":    errOrEmpty(firstErr),
			"count":    len(allPkgs),
		}, "", "  ")
		fmt.Println(string(out))
		return
	}

	printBackends(backends)
	fmt.Printf("Updates: %d\n", len(allPkgs))
	if firstErr != nil {
		fmt.Printf("Error:   %v\n", firstErr)
	}
	if len(allPkgs) == 0 {
		return
	}
	fmt.Println()
	for _, p := range allPkgs {
		printPackage(p)
	}
}

type backendResult struct {
	ID       string              `json:"id"`
	Display  string              `json:"displayName"`
	Packages []sysupdate.Package `json:"packages"`
}

func backendResults(backends []sysupdate.Backend, pkgs []sysupdate.Package) []backendResult {
	results := make([]backendResult, 0, len(backends))
	for _, b := range backends {
		var backendPkgs []sysupdate.Package
		for _, p := range pkgs {
			if sysupdate.BackendHasTargets(b, []sysupdate.Package{p}, true, true) {
				backendPkgs = append(backendPkgs, p)
			}
		}
		results = append(results, backendResult{ID: b.ID(), Display: b.DisplayName(), Packages: backendPkgs})
	}
	return results
}

func runSystemUpdateApply() {
	checkCtx, checkCancel := context.WithTimeout(context.Background(), sysUpdateListPmTime)
	defer checkCancel()

	backends := selectBackends(checkCtx)
	if len(backends) == 0 {
		log.Fatal("No supported package manager found")
	}

	stopSpin := startSpinner("Checking for updates…")
	pkgs, firstErr := collectUpdates(checkCtx, backends)
	stopSpin()
	pkgs = filterUpdateTargets(pkgs)
	if firstErr != nil {
		fmt.Printf("Warning: %v\n\n", firstErr)
	}

	printBackends(backends)
	fmt.Printf("Updates: %d\n", len(pkgs))
	if len(pkgs) == 0 {
		fmt.Println("Nothing to upgrade.")
		return
	}
	fmt.Println()
	for _, p := range pkgs {
		printPackage(p)
	}
	fmt.Println()

	if !sysUpdateNoConfirm && !sysUpdateInteractive && !sysUpdateDry {
		if !promptYesNo("Proceed with upgrade? [Y/n]: ") {
			fmt.Println("Aborted.")
			return
		}
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Minute)
	defer cancel()

	opts := sysupdate.UpgradeOptions{
		Targets:        pkgs,
		IncludeFlatpak: !sysUpdateNoFlatpak,
		IncludeAUR:     !sysUpdateNoAUR,
		Ignored:        sysUpdateIgnore,
		DryRun:         sysUpdateDry,
		UseSudo:        true,
	}
	opts.AttachStdio = sysupdate.UpgradeNeedsPrivilege(backends, pkgs, opts)
	opts.Interactive = sysUpdateInteractive && opts.AttachStdio

	onLine := func(line string) { fmt.Println(line) }
	ran := false
	for _, b := range backends {
		if !sysupdate.BackendHasTargets(b, pkgs, opts.IncludeAUR, opts.IncludeFlatpak) {
			continue
		}
		ran = true
		fmt.Printf("\n== %s ==\n", b.DisplayName())
		if err := b.Upgrade(ctx, opts, onLine); err != nil {
			log.Fatalf("%s upgrade failed: %v", b.ID(), err)
		}
	}
	if !ran {
		fmt.Println("Nothing to upgrade.")
		return
	}
	if sysUpdateDry {
		fmt.Println("\nDry run complete (no changes applied).")
		return
	}
	fmt.Println("\nUpgrade complete.")
}

func collectUpdates(ctx context.Context, backends []sysupdate.Backend) ([]sysupdate.Package, error) {
	var all []sysupdate.Package
	var firstErr error
	for _, b := range backends {
		pkgs, err := b.CheckUpdates(ctx)
		if err != nil && firstErr == nil {
			firstErr = fmt.Errorf("%s: %w", b.ID(), err)
		}
		all = append(all, pkgs...)
	}
	return all, firstErr
}

func filterUpdateTargets(pkgs []sysupdate.Package) []sysupdate.Package {
	if !sysUpdateNoAUR && len(sysUpdateIgnore) == 0 {
		return pkgs
	}
	out := pkgs[:0]
	for _, p := range pkgs {
		if sysUpdateNoAUR && p.Repo == sysupdate.RepoAUR {
			continue
		}
		if sysupdate.IsPackageIgnored(p.Name, sysUpdateIgnore) {
			continue
		}
		out = append(out, p)
	}
	return out
}

func runSystemUpdateSetInterval(seconds int) {
	resp, err := sendServerRequest(ipc.Request{
		ID:     1,
		Method: "sysupdate.setInterval",
		Params: map[string]any{"seconds": float64(seconds)},
	})
	if err != nil {
		log.Fatalf("Failed: %v (is dms server running?)", err)
	}
	if resp.Error != "" {
		log.Fatalf("Error: %s", resp.Error)
	}
	fmt.Printf("Interval set to %d seconds.\n", seconds)
}

func promptYesNo(prompt string) bool {
	if !stdinIsTTY() {
		log.Fatal("Refusing to apply updates non-interactively. Re-run with --noconfirm or --check.")
	}
	fmt.Print(prompt)
	reader := bufio.NewReader(os.Stdin)
	line, err := reader.ReadString('\n')
	if err != nil {
		return false
	}
	switch strings.ToLower(strings.TrimSpace(line)) {
	case "n", "no":
		return false
	default:
		return true
	}
}

func printBackends(backends []sysupdate.Backend) {
	if len(backends) == 0 {
		return
	}
	names := make([]string, 0, len(backends))
	for _, b := range backends {
		names = append(names, b.DisplayName())
	}
	fmt.Printf("Backends: %s\n", strings.Join(names, ", "))
}

func stdinIsTTY() bool {
	fi, err := os.Stdin.Stat()
	if err != nil {
		return false
	}
	return (fi.Mode() & os.ModeCharDevice) != 0
}

func stdoutIsTTY() bool {
	fi, err := os.Stdout.Stat()
	if err != nil {
		return false
	}
	return (fi.Mode() & os.ModeCharDevice) != 0
}

// startSpinner prints an animated spinner to stdout for progress indication
func startSpinner(msg string) func() {
	if !stdoutIsTTY() {
		return func() {}
	}
	frames := []string{"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"}
	done := make(chan struct{})
	go func() {
		for i := 0; ; i++ {
			select {
			case <-done:
				fmt.Print("\r\033[K")
				return
			case <-time.After(80 * time.Millisecond):
				fmt.Printf("\r%s %s", frames[i%len(frames)], msg)
			}
		}
	}()
	return func() { close(done) }
}

var (
	styleRepo  = lipgloss.NewStyle().Foreground(lipgloss.Color("244")).Bold(false)
	styleName  = lipgloss.NewStyle().Foreground(lipgloss.Color("39")).Bold(true)
	styleFrom  = lipgloss.NewStyle().Foreground(lipgloss.Color("243"))
	styleArrow = lipgloss.NewStyle().Foreground(lipgloss.Color("244"))
	styleTo    = lipgloss.NewStyle().Foreground(lipgloss.Color("76")).Bold(true)
)

func printPackage(p sysupdate.Package) {
	if !stdoutIsTTY() {
		fmt.Printf("  [%s] %s  %s -> %s\n", p.Repo, p.Name, defaultIfEmpty(p.FromVersion, "?"), defaultIfEmpty(p.ToVersion, "?"))
		return
	}
	fmt.Printf("  %s %s  %s %s %s\n",
		styleRepo.Render("["+string(p.Repo)+"]"),
		styleName.Render(p.Name),
		styleFrom.Render(defaultIfEmpty(p.FromVersion, "?")),
		styleArrow.Render("->"),
		styleTo.Render(defaultIfEmpty(p.ToVersion, "?")),
	)
}

func errOrEmpty(err error) string {
	if err == nil {
		return ""
	}
	return err.Error()
}

func defaultIfEmpty(s, def string) string {
	if s == "" {
		return def
	}
	return s
}
