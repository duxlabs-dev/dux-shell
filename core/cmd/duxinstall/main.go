package main

import (
	"fmt"
	"os"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/duxlabs-dev/dux-shell/core/internal/headless"
	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/duxlabs-dev/dux-shell/core/internal/tui"
	"github.com/spf13/cobra"
)

var Version = "dev"

var (
	compositor        string
	term              string
	privescTool       string
	gitAll            bool
	gitDeps           []string
	allFeatures       bool
	includeDeps       []string
	excludeDeps       []string
	replaceConfigs    []string
	replaceConfigsAll bool
	yes               bool
	danksearch        bool
	dankcalendar      bool
	dmsGreeter        bool
)

var rootCmd = &cobra.Command{
	Use:   "duxinstall",
	Short: "Install Dux Shell and its dependencies",
	Long: `duxinstall sets up Dux Shell with your chosen compositor and terminal.

Without flags, it launches an interactive TUI. Providing either --compositor
or --term activates headless (unattended) mode, which requires both flags.

Headless mode requires cached credentials or a passwordless rule for your
privilege escalation tool (sudo, doas, or run0).`,
	Args:          cobra.NoArgs,
	RunE:          runDuxinstall,
	SilenceErrors: true,
	SilenceUsage:  true,
}

func init() {
	rootCmd.Flags().StringVarP(&compositor, "compositor", "c", "", "Compositor/WM to install: niri, hyprland, or mango (enables headless mode)")
	rootCmd.Flags().StringVarP(&term, "term", "t", "", "Terminal emulator to install: ghostty, kitty, or alacritty (enables headless mode)")
	rootCmd.Flags().StringVar(&privescTool, "privesc", "", "Privilege escalation tool: sudo, doas, or run0 (default: autodetect)")
	rootCmd.Flags().BoolVar(&gitAll, "git", false, "Install the git version of every dep that has one")
	rootCmd.Flags().StringSliceVar(&gitDeps, "git-deps", []string{}, "Deps to install the git version of (e.g. niri,quickshell)")
	rootCmd.Flags().BoolVar(&allFeatures, "all-features", false, "Enable all optional deps (dms-greeter, danksearch, dankcalendar)")
	rootCmd.Flags().StringSliceVar(&includeDeps, "include-deps", []string{}, "Optional deps to enable (e.g. dms-greeter)")
	rootCmd.Flags().StringSliceVar(&excludeDeps, "exclude-deps", []string{}, "Deps to skip during installation")
	rootCmd.Flags().StringSliceVar(&replaceConfigs, "replace-configs", []string{}, "Deploy only named configs (e.g. niri,ghostty)")
	rootCmd.Flags().BoolVar(&replaceConfigsAll, "replace-configs-all", false, "Deploy and replace all configurations")
	rootCmd.Flags().BoolVarP(&yes, "yes", "y", false, "Auto-confirm all prompts")
	rootCmd.Flags().BoolVar(&danksearch, "danksearch", false, "Install dsearch (dux-search) and enable its user indexing service")
	rootCmd.Flags().BoolVar(&dankcalendar, "dankcalendar", false, "Install dcal (dux-calendar)")
	rootCmd.Flags().BoolVar(&dmsGreeter, "dms-greeter", false, "Install the dms-greeter greetd greeter (dux-greeter)")
}

func main() {
	if os.Getuid() == 0 {
		fmt.Fprintln(os.Stderr, "Error: duxinstall must not be run as root")
		os.Exit(1)
	}

	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}

func runDuxinstall(cmd *cobra.Command, args []string) error {
	headlessMode := compositor != "" || term != ""

	if !headlessMode {
		headlessOnly := []string{
			"privesc",
			"git",
			"git-deps",
			"all-features",
			"include-deps",
			"exclude-deps",
			"replace-configs",
			"replace-configs-all",
			"yes",
			"danksearch",
			"dankcalendar",
			"dms-greeter",
		}
		var set []string
		for _, name := range headlessOnly {
			if cmd.Flags().Changed(name) {
				set = append(set, "--"+name)
			}
		}
		if len(set) > 0 {
			return fmt.Errorf("flags %s are only valid in headless mode (requires both --compositor and --term)", strings.Join(set, ", "))
		}
	}

	if headlessMode {
		return runHeadless()
	}
	return runTUI()
}

func runHeadless() error {
	if compositor == "" {
		return fmt.Errorf("--compositor is required for headless mode (niri, hyprland, or mango)")
	}
	if term == "" {
		return fmt.Errorf("--term is required for headless mode (ghostty, kitty, or alacritty)")
	}

	cfg := headless.Config{
		Compositor:        compositor,
		Terminal:          term,
		PrivescTool:       privescTool,
		GitAll:            gitAll,
		GitDeps:           gitDeps,
		AllFeatures:       allFeatures,
		IncludeDeps:       includeDeps,
		ExcludeDeps:       excludeDeps,
		ReplaceConfigs:    replaceConfigs,
		ReplaceConfigsAll: replaceConfigsAll,
		Yes:               yes,
		DankSearch:        danksearch,
		DankCalendar:      dankcalendar,
		DmsGreeter:        dmsGreeter,
	}

	runner := headless.NewRunner(cfg)

	fileLogger, err := log.NewFileLogger()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Warning: Failed to create log file: %v\n", err)
	}

	if fileLogger != nil {
		fmt.Printf("Logging to: %s\n", fileLogger.GetLogPath())
		fileLogger.StartListening(runner.GetLogChan())
		defer func() {
			if err := fileLogger.Close(); err != nil {
				fmt.Fprintf(os.Stderr, "Warning: Failed to close log file: %v\n", err)
			}
		}()
	} else {
		defer drainLogChan(runner.GetLogChan())()
	}

	if err := runner.Run(); err != nil {
		if fileLogger != nil {
			fmt.Fprintf(os.Stderr, "\nFull logs are available at: %s\n", fileLogger.GetLogPath())
		}
		return err
	}

	if fileLogger != nil {
		fmt.Printf("\nFull logs are available at: %s\n", fileLogger.GetLogPath())
	}
	return nil
}

func runTUI() error {
	fileLogger, err := log.NewFileLogger()
	if err != nil {
		fmt.Printf("Warning: Failed to create log file: %v\n", err)
		fmt.Println("Continuing without file logging...")
	}

	logFilePath := ""
	if fileLogger != nil {
		logFilePath = fileLogger.GetLogPath()
		fmt.Printf("Logging to: %s\n", logFilePath)
		defer func() {
			if err := fileLogger.Close(); err != nil {
				fmt.Printf("Warning: Failed to close log file: %v\n", err)
			}
		}()
	}

	model := tui.NewModel(Version, logFilePath)

	if fileLogger != nil {
		fileLogger.StartListening(model.GetLogChan())
	} else {
		defer drainLogChan(model.GetLogChan())()
	}

	p := tea.NewProgram(model, tea.WithAltScreen())
	if _, err := p.Run(); err != nil {
		if logFilePath != "" {
			fmt.Fprintf(os.Stderr, "\nFull logs are available at: %s\n", logFilePath)
		}
		return fmt.Errorf("error running program: %w", err)
	}

	if logFilePath != "" {
		fmt.Printf("\nFull logs are available at: %s\n", logFilePath)
	}
	return nil
}

// drainLogChan discards messages from logCh so blocking sends in downstream
// components cannot deadlock when no file logger is attached; the returned
// cleanup stops the drain without assuming the channel will ever close.
func drainLogChan(logCh <-chan string) func() {
	drainStop := make(chan struct{})
	drainDone := make(chan struct{})
	go func() {
		defer close(drainDone)
		for {
			select {
			case <-drainStop:
				return
			case _, ok := <-logCh:
				if !ok {
					return
				}
			}
		}
	}()
	return func() {
		close(drainStop)
		<-drainDone
	}
}
