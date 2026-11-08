package main

import (
	"context"
	"errors"
	"fmt"
	"os"
	"strings"

	"github.com/duxlabs-dev/dux-shell/core/internal/distros"
	"github.com/duxlabs-dev/dux-shell/core/internal/privesc"
	"github.com/spf13/cobra"
)

const migrateDuxCommand = "dms migrate dux"

var (
	migrateDryRun    bool
	migrateAssumeYes bool
)

var migrateCmd = &cobra.Command{
	Use:   "migrate",
	Short: "One-time migrations for existing installs",
}

var migrateDuxCmd = &cobra.Command{
	Use:   "dux",
	Short: "Move DMS package repositories to the Dux Labs owner",
	Long: `Move the DMS package repositories from the legacy AvengeMedia owner to Dux Labs.

Adds the Dux Labs repository for every legacy one found, then removes the legacy
one. On openSUSE the installed packages are switched to the new repositories,
which zypper does not do on its own; on Debian the renamed packages are installed
under their new names. Elsewhere the next update comes from the new repo.`,
	Args: cobra.NoArgs,
	Run: func(cmd *cobra.Command, args []string) {
		if err := runMigrateDux(); err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}
	},
}

func init() {
	migrateDuxCmd.Flags().BoolVar(&migrateDryRun, "dry-run", false, "Print the commands without running them")
	migrateDuxCmd.Flags().BoolVarP(&migrateAssumeYes, "yes", "y", false, "Do not ask for confirmation")
	migrateCmd.AddCommand(migrateDuxCmd)
}

func runMigrateDux() error {
	osInfo, err := distros.GetOSInfo()
	if err != nil {
		return fmt.Errorf("detecting distribution: %w", err)
	}
	distro, err := distros.NewDistribution(osInfo.Distribution.ID, nil)
	if err != nil {
		return err
	}

	moves, ok := distros.PlanRepoMoves(distro)
	if !ok {
		fmt.Printf("Nothing to migrate on %s.\n", osInfo.PrettyName)
		return nil
	}
	mover := distro.(distros.RepoMover)
	commands := mover.RepoMoveCommands(moves)
	if len(commands) == 0 {
		fmt.Println("Already migrated.")
		return nil
	}
	if osInfo.Immutable {
		imageMover, ok := distro.(distros.ImageRepoMover)
		if !ok {
			return fmt.Errorf("%s is an image-based system; move the repositories with your image tooling", osInfo.PrettyName)
		}
		printRepoMoves(moves, imageMover.ImageRepoMoveCommands(moves))
		fmt.Printf("\n%s is image-based, so run these yourself.\n", osInfo.PrettyName)
		return nil
	}

	printRepoMoves(moves, commands)
	if migrateDryRun {
		return nil
	}
	if !migrateAssumeYes && !askYes("\nContinue? [y/N] ") {
		return errors.New("cancelled")
	}

	ctx := context.Background()
	if privesc.CheckCached(ctx) != nil {
		if err := privesc.Run(ctx, "", "true"); err != nil {
			return fmt.Errorf("authentication failed: %w", err)
		}
	}
	err = runWithProgressOutput(func(progressChan chan<- distros.InstallProgressMsg) error {
		return mover.ApplyRepoMoves(ctx, moves, "", progressChan)
	})
	if err != nil {
		return err
	}
	fmt.Println("Done. 'dms doctor' shows the result; the shell notice clears on its next start.")
	return nil
}

// Rows with neither repo present still carry a default NewPath, so only a row without a legacy side is an add.
func repoMoveRows(moves []distros.RepoMove) []string {
	var rows []string
	for _, move := range moves {
		switch {
		case move.OldPresent:
			rows = append(rows, fmt.Sprintf("  %s → %s", move.Old, move.New))
		case move.Old == "" && !move.NewPresent && move.NewPath != "":
			rows = append(rows, "  add "+move.New)
		}
	}
	return rows
}

func printRepoMoves(moves []distros.RepoMove, commands []string) {
	// Repos moved by hand can still leave packages to switch.
	if rows := repoMoveRows(moves); len(rows) > 0 {
		fmt.Println("Repositories to move:")
		fmt.Println(strings.Join(rows, "\n"))
		fmt.Println()
	}
	fmt.Println("Commands:")
	for _, command := range commands {
		fmt.Printf("  %s\n", command)
	}
}
