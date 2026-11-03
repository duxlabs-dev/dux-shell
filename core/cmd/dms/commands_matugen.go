package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"time"

	"github.com/duxlabs-dev/dux-go/ipc"
	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/duxlabs-dev/dux-shell/core/internal/matugen"
	"github.com/spf13/cobra"
)

var matugenCmd = &cobra.Command{
	Use:   "matugen",
	Short: "Generate Material Design themes",
	Long:  "Generate Material Design themes using matugen with dank16 color integration",
}

var matugenGenerateCmd = &cobra.Command{
	Use:   "generate",
	Short: "Generate theme synchronously",
	Run:   runMatugenGenerate,
}

var matugenQueueCmd = &cobra.Command{
	Use:   "queue",
	Short: "Queue theme generation (uses socket if available)",
	Run:   runMatugenQueue,
}

var matugenCheckCmd = &cobra.Command{
	Use:   "check",
	Short: "Check which template apps are detected",
	Run:   runMatugenCheck,
}

var matugenPreviewCmd = &cobra.Command{
	Use:   "preview",
	Short: "Preview Matugen scheme colors without applying them",
	Run:   runMatugenPreview,
}

var matugenQtengineCmd = &cobra.Command{
	Use:   "qtengine",
	Short: "Sync qtengine's config with the current DMS theme",
	Run:   runMatugenQtengine,
}

func init() {
	matugenCmd.AddCommand(matugenGenerateCmd)
	matugenCmd.AddCommand(matugenQueueCmd)
	matugenCmd.AddCommand(matugenCheckCmd)
	matugenCmd.AddCommand(matugenPreviewCmd)
	matugenCmd.AddCommand(matugenQtengineCmd)

	for _, cmd := range []*cobra.Command{matugenGenerateCmd, matugenQueueCmd} {
		cmd.Flags().String("state-dir", "", "State directory for cache files")
		cmd.Flags().String("shell-dir", "", "DMS shell installation directory")
		cmd.Flags().String("config-dir", "", "User config directory")
		cmd.Flags().String("kind", "image", "Source type: image or hex")
		cmd.Flags().String("value", "", "Wallpaper path or hex color")
		cmd.Flags().String("mode", "dark", "Color mode: dark, light, or smart (smart requires matugen 4.2+ and an image source)")
		cmd.Flags().String("icon-theme", "System Default", "Icon theme name")
		cmd.Flags().String("matugen-type", "scheme-tonal-spot", "Matugen scheme type (supports scheme-smart on matugen 4.2+)")
		cmd.Flags().Bool("run-user-templates", true, "Run user matugen templates")
		cmd.Flags().String("stock-colors", "", "Stock theme colors JSON")
		cmd.Flags().Bool("sync-mode-with-portal", false, "Sync color scheme with GNOME portal")
		cmd.Flags().Bool("terminals-always-dark", false, "Force terminal themes to dark variant")
		cmd.Flags().Int("terminal-opacity", 0, "Terminal background opacity percent, 1-99 (0 or 100 leaves the terminal's own setting)")
		cmd.Flags().String("terminal-palette", "", "Terminal palette: default, low, medium or high")
		cmd.Flags().String("skip-templates", "", "Comma-separated list of templates to skip")
		cmd.Flags().Float64("contrast", 0, "Contrast value from -1 to 1 (0 = standard)")
		cmd.Flags().String("source-mode", "", "Source color selection: dominant, colorful, darkness, lightness, saturation, less-saturation, value")
		cmd.Flags().String("seed-color", "", "Hex color to build the palette from instead of extracting one from the wallpaper")
		cmd.Flags().String("spec", "", "Material color spec: 2021 (matugen native, default), 2025 (Material 3 Expressive) or dms (2025 accents on neutral surfaces)")
	}

	matugenQueueCmd.Flags().Bool("wait", true, "Wait for completion")
	matugenQueueCmd.Flags().Duration("timeout", 90*time.Second, "Timeout for waiting")
	matugenPreviewCmd.Flags().String("source-color", "", "Source color used to generate previews")
	matugenPreviewCmd.Flags().String("image", "", "Wallpaper image used to resolve the scheme-smart preview")
	matugenPreviewCmd.Flags().Float64("contrast", 0, "Contrast value from -1 to 1 (0 = standard)")
	matugenPreviewCmd.Flags().String("spec", "", "Material color spec: 2021 (matugen native, default), 2025 (Material 3 Expressive) or dms (2025 accents on neutral surfaces)")
	matugenQtengineCmd.Flags().String("config-dir", "", "User config directory")
	matugenQtengineCmd.Flags().String("icon-theme", "", "Icon theme name")
}

func buildMatugenOptions(cmd *cobra.Command) matugen.Options {
	stateDir, _ := cmd.Flags().GetString("state-dir")
	shellDir, _ := cmd.Flags().GetString("shell-dir")
	configDir, _ := cmd.Flags().GetString("config-dir")
	kind, _ := cmd.Flags().GetString("kind")
	value, _ := cmd.Flags().GetString("value")
	mode, _ := cmd.Flags().GetString("mode")
	iconTheme, _ := cmd.Flags().GetString("icon-theme")
	matugenType, _ := cmd.Flags().GetString("matugen-type")
	runUserTemplates, _ := cmd.Flags().GetBool("run-user-templates")
	stockColors, _ := cmd.Flags().GetString("stock-colors")
	syncModeWithPortal, _ := cmd.Flags().GetBool("sync-mode-with-portal")
	terminalsAlwaysDark, _ := cmd.Flags().GetBool("terminals-always-dark")
	terminalOpacity, _ := cmd.Flags().GetInt("terminal-opacity")
	terminalPalette, _ := cmd.Flags().GetString("terminal-palette")
	skipTemplates, _ := cmd.Flags().GetString("skip-templates")
	contrast, _ := cmd.Flags().GetFloat64("contrast")
	sourceMode, _ := cmd.Flags().GetString("source-mode")
	seedColor, _ := cmd.Flags().GetString("seed-color")
	spec, _ := cmd.Flags().GetString("spec")

	return matugen.Options{
		StateDir:            stateDir,
		ShellDir:            shellDir,
		ConfigDir:           configDir,
		Kind:                kind,
		Value:               value,
		Mode:                matugen.ColorMode(mode),
		IconTheme:           iconTheme,
		MatugenType:         matugenType,
		Contrast:            contrast,
		RunUserTemplates:    runUserTemplates,
		StockColors:         stockColors,
		SyncModeWithPortal:  syncModeWithPortal,
		TerminalsAlwaysDark: terminalsAlwaysDark,
		TerminalOpacity:     terminalOpacity,
		TerminalPalette:     terminalPalette,
		SkipTemplates:       skipTemplates,
		SourceMode:          sourceMode,
		SeedColor:           seedColor,
		Spec:                spec,
	}
}

func runMatugenGenerate(cmd *cobra.Command, args []string) {
	opts := buildMatugenOptions(cmd)
	err := matugen.Run(opts)
	switch {
	case errors.Is(err, matugen.ErrNoChanges):
		os.Exit(2)
	case err != nil:
		log.Fatalf("Theme generation failed: %v", err)
	}
}

func runMatugenQueue(cmd *cobra.Command, args []string) {
	opts := buildMatugenOptions(cmd)
	wait, _ := cmd.Flags().GetBool("wait")
	timeout, _ := cmd.Flags().GetDuration("timeout")

	request := ipc.Request{
		ID:     1,
		Method: "matugen.queue",
		Params: map[string]any{
			"stateDir":            opts.StateDir,
			"shellDir":            opts.ShellDir,
			"configDir":           opts.ConfigDir,
			"kind":                opts.Kind,
			"value":               opts.Value,
			"mode":                opts.Mode,
			"iconTheme":           opts.IconTheme,
			"matugenType":         opts.MatugenType,
			"runUserTemplates":    opts.RunUserTemplates,
			"stockColors":         opts.StockColors,
			"syncModeWithPortal":  opts.SyncModeWithPortal,
			"terminalsAlwaysDark": opts.TerminalsAlwaysDark,
			"terminalOpacity":     opts.TerminalOpacity,
			"terminalPalette":     opts.TerminalPalette,
			"skipTemplates":       opts.SkipTemplates,
			"contrast":            opts.Contrast,
			"sourceMode":          opts.SourceMode,
			"seedColor":           opts.SeedColor,
			"spec":                opts.Spec,
			"wait":                wait,
		},
	}

	if !wait {
		if err := sendServerRequestFireAndForget(request); err != nil {
			log.Info("Server unavailable, running synchronously")
			err := matugen.Run(opts)
			switch {
			case errors.Is(err, matugen.ErrNoChanges):
				os.Exit(2)
			case err != nil:
				log.Fatalf("Theme generation failed: %v", err)
			}
			return
		}
		fmt.Println("Theme generation queued")
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	resultCh := make(chan error, 1)
	go func() {
		resp, ok := tryServerRequest(request)
		if !ok {
			log.Info("Server unavailable, running synchronously")
			err := matugen.Run(opts)
			switch {
			case errors.Is(err, matugen.ErrNoChanges):
				resultCh <- matugen.ErrNoChanges
			case err != nil:
				resultCh <- err
			default:
				resultCh <- nil
			}
			return
		}
		if resp.Error != "" {
			resultCh <- fmt.Errorf("server error: %s", resp.Error)
			return
		}
		resultCh <- nil
	}()

	select {
	case err := <-resultCh:
		switch {
		case errors.Is(err, matugen.ErrNoChanges):
			os.Exit(2)
		case err != nil:
			log.Fatalf("Theme generation failed: %v", err)
		}
		fmt.Println("Theme generation completed")
	case <-ctx.Done():
		log.Fatalf("Timeout waiting for theme generation")
	}
}

func runMatugenCheck(cmd *cobra.Command, args []string) {
	checks := matugen.CheckTemplates(nil)
	data, err := json.Marshal(checks)
	if err != nil {
		log.Fatalf("Failed to marshal check results: %v", err)
	}
	fmt.Println(string(data))
}

func runMatugenPreview(cmd *cobra.Command, args []string) {
	sourceColor, _ := cmd.Flags().GetString("source-color")
	imagePath, _ := cmd.Flags().GetString("image")
	contrast, _ := cmd.Flags().GetFloat64("contrast")
	spec, _ := cmd.Flags().GetString("spec")
	previews, err := matugen.PreviewSchemes(sourceColor, contrast, imagePath, spec)
	if err != nil {
		log.Fatalf("Failed to generate Matugen previews: %v", err)
	}
	data, err := json.Marshal(previews)
	if err != nil {
		log.Fatalf("Failed to marshal Matugen previews: %v", err)
	}
	fmt.Println(string(data))
}

func runMatugenQtengine(cmd *cobra.Command, args []string) {
	configDir, _ := cmd.Flags().GetString("config-dir")
	iconTheme, _ := cmd.Flags().GetString("icon-theme")

	if err := matugen.SyncQtengineConfigAt(configDir, iconTheme); err != nil {
		log.Fatalf("Failed to sync qtengine config: %v", err)
	}
}
