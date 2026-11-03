package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/duxlabs-dev/dux-shell/core/internal/qsipc"
	"github.com/duxlabs-dev/dux-shell/core/internal/site"
)

type ipcTargets map[string]map[string][]string

var qsHasAnyDisplay = sync.OnceValue(func() bool {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "qs", "ipc", "--help")
	cmd.WaitDelay = 500 * time.Millisecond
	out, err := cmd.Output()
	if err != nil {
		return false
	}
	return strings.Contains(string(out), "--any-display")
})

func parseTargetsFromIPCShowOutput(output string) ipcTargets {
	targets := make(ipcTargets)
	var currentTarget string
	for line := range strings.SplitSeq(output, "\n") {
		if after, ok := strings.CutPrefix(line, "target "); ok {
			currentTarget = strings.TrimSpace(after)
			targets[currentTarget] = make(map[string][]string)
		}
		if strings.HasPrefix(line, "  function") && currentTarget != "" {
			argsList := []string{}
			currentFunc := strings.TrimPrefix(line, "  function ")
			funcDef := strings.SplitN(currentFunc, "(", 2)
			argList := strings.SplitN(funcDef[1], ")", 2)[0]
			args := strings.Split(argList, ",")
			if len(args) > 0 && strings.TrimSpace(args[0]) != "" {
				argsList = append(argsList, funcDef[0])
				for _, arg := range args {
					argName := strings.SplitN(strings.TrimSpace(arg), ":", 2)[0]
					argsList = append(argsList, argName)
				}
				targets[currentTarget][funcDef[0]] = argsList
			} else {
				targets[currentTarget][funcDef[0]] = make([]string, 0)
			}
		}
	}
	return targets
}

func buildQsIPCBaseArgs() ([]string, error) {
	cmdArgs := []string{"ipc"}
	switch pid, ok := shellApp.SessionPID(); {
	case ok:
		cmdArgs = append(cmdArgs, "--pid", strconv.Itoa(pid))
	default:
		if err := shellApp.ResolveConfig(nil, nil); err != nil {
			return nil, err
		}
		if qsHasAnyDisplay() {
			cmdArgs = append(cmdArgs, "--any-display")
		}
		cmdArgs = append(cmdArgs, "-p", shellApp.ConfigPath())
	}
	return cmdArgs, nil
}

func getShellIPCCompletions(args []string, _ string) []string {
	baseArgs, err := buildQsIPCBaseArgs()
	if err != nil {
		log.Debugf("Error building IPC args for completions: %v", err)
		return nil
	}
	cmdArgs := append(baseArgs, "show")
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "qs", cmdArgs...)
	cmd.WaitDelay = 500 * time.Millisecond
	var targets ipcTargets

	if output, err := cmd.Output(); err == nil {
		targets = parseTargetsFromIPCShowOutput(string(output))
	} else {
		log.Debugf("Error getting IPC show output for completions: %v", err)
		return nil
	}

	if len(args) > 0 && args[0] == "call" {
		args = args[1:]
	}

	if len(args) == 0 {
		targetNames := make([]string, 0)
		targetNames = append(targetNames, "call", "list")
		for k := range targets {
			targetNames = append(targetNames, k)
		}
		return targetNames
	}
	if len(args) == 1 {
		if targetFuncs, ok := targets[args[0]]; ok {
			funcNames := make([]string, 0)
			for k := range targetFuncs {
				funcNames = append(funcNames, k)
			}
			return funcNames
		}
		return nil
	}
	if len(args) <= len(targets[args[0]]) {
		funcArgs := targets[args[0]][args[1]]
		if len(funcArgs) >= len(args) {
			return []string{fmt.Sprintf("[%s]", funcArgs[len(args)-1])}
		}
	}

	return nil
}

func runShellIPCCommand(args []string) {
	if len(args) == 0 {
		printIPCHelp()
		return
	}

	if args[0] != "call" {
		args = append([]string{"call"}, args...)
	}
	args = fillOptionalIPCArgs(args)
	if tryDirectIPCCall(args) {
		return
	}

	baseArgs, err := buildQsIPCBaseArgs()
	if err != nil {
		log.Fatalf("Error finding config: %v", err)
	}
	cmdArgs := append(baseArgs, args...)
	cmd := exec.Command("qs", cmdArgs...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	if err := cmd.Run(); err != nil {
		log.Fatalf("Error running IPC command: %v", err)
	}
}

// fillOptionalIPCArgs adds the empty device argument the brightness IPC handlers
// treat as the preferred device. Quickshell's IpcHandler has no optional arguments.
func fillOptionalIPCArgs(args []string) []string {
	if len(args) < 3 || args[1] != "brightness" {
		return args
	}
	withoutDevice := 0
	switch args[2] {
	case "set", "increment", "decrement":
		withoutDevice = 1
	case "enableExponential", "disableExponential", "toggleExponential":
	default:
		return args
	}
	if len(args)-3 != withoutDevice {
		return args
	}
	return append(args[:len(args):len(args)], "")
}

// tryDirectIPCCall invokes the shell over its IPC socket without spawning qs.
// Any failure falls back to the qs child process path, which owns error output.
func tryDirectIPCCall(args []string) bool {
	if len(args) < 3 {
		return false
	}
	pid, ok := shellApp.SessionPID()
	if !ok {
		return false
	}
	result, isVoid, err := qsipc.Call(qsipc.SocketPathForPID(pid), args[1], args[2], args[3:])
	if err != nil {
		log.Debugf("Direct Quickshell IPC failed, falling back to qs: %v", err)
		return false
	}
	if !isVoid {
		fmt.Println(result)
	}
	return true
}

func printIPCHelp() {
	fmt.Println("Usage: dms ipc call <target> <function> [args...]")
	fmt.Println()

	baseArgs, err := buildQsIPCBaseArgs()
	if err != nil {
		printIPCHelpFailure(err)
		return
	}
	cmdArgs := append(baseArgs, "show")
	cmd := exec.Command("qs", cmdArgs...)

	output, err := cmd.Output()
	if err != nil {
		printIPCHelpFailure(err)
		return
	}

	targets := parseTargetsFromIPCShowOutput(string(output))
	if len(targets) == 0 {
		fmt.Println("No IPC targets available")
		return
	}

	fmt.Println("Targets:")

	targetNames := make([]string, 0, len(targets))
	for name := range targets {
		targetNames = append(targetNames, name)
	}
	slices.Sort(targetNames)

	for _, targetName := range targetNames {
		funcs := targets[targetName]
		funcNames := make([]string, 0, len(funcs))
		for fn := range funcs {
			funcNames = append(funcNames, fn)
		}
		slices.Sort(funcNames)
		fmt.Printf("  %-16s %s\n", targetName, strings.Join(funcNames, ", "))
	}
}

func printIPCHelpFailure(err error) {
	fmt.Println("Could not retrieve IPC targets.")
	if err != nil {
		fmt.Printf("  %v\n", err)
	}
	fmt.Println()
	fmt.Println("  Full docs:  " + site.Docs + "/dms/keybinds-ipc")
	fmt.Println("  Try:        dms ipc call <target> <function>")
}

func ensureFontCache() {
	if _, err := exec.LookPath("fc-list"); err != nil {
		return
	}
	if _, err := exec.LookPath("fc-cache"); err != nil {
		return
	}

	var fontsToCheck []string

	if configDir, err := os.UserConfigDir(); err == nil {
		settingsPath := filepath.Join(configDir, "dms", "settings.json")
		if data, err := os.ReadFile(settingsPath); err == nil {
			var settings struct {
				FontFamily        string `json:"fontFamily"`
				MonoFontFamily    string `json:"monoFontFamily"`
				DisplayFontFamily string `json:"displayFontFamily"`
			}
			if err := json.Unmarshal(data, &settings); err == nil {
				for _, family := range []string{settings.FontFamily, settings.MonoFontFamily, settings.DisplayFontFamily} {
					if family == "" || isBundledDefaultFont(family) {
						continue
					}
					fontsToCheck = append(fontsToCheck, family)
				}
			}
		}
	}

	if len(fontsToCheck) == 0 {
		return
	}

	output, err := exec.Command("fc-list", ":", "family").Output()
	if err != nil || len(strings.TrimSpace(string(output))) == 0 {
		log.Warnf("Font cache appears empty or corrupt, rebuilding...")
		rebuildFontCache()
		return
	}

	cacheFonts := strings.ToLower(string(output))
	var missing []string
	for _, font := range fontsToCheck {
		if !fontInCache(strings.ToLower(font), cacheFonts) {
			missing = append(missing, font)
		}
	}

	if len(missing) > 0 {
		log.Warnf("Font(s) not found in cache: %s — rebuilding...", strings.Join(missing, ", "))
		rebuildFontCache()
	}
}

func fontInCache(target, cache string) bool {
	for line := range strings.SplitSeq(cache, "\n") {
		for fam := range strings.SplitSeq(strings.TrimSpace(line), ",") {
			if strings.TrimSpace(fam) == target {
				return true
			}
		}
	}
	return false
}

func rebuildFontCache() {
	cmd := exec.Command("fc-cache", "-f")
	if output, err := cmd.CombinedOutput(); err != nil {
		log.Warnf("Failed to rebuild font cache: %v\n%s", err, string(output))
	} else {
		log.Infof("Font cache rebuilt successfully")
	}
}

// logStartupFailure logs diagnostic advice if qs crashes within 5s of launch.
func logStartupFailure(exitCode int, uptime time.Duration, stderrTail string) {
	if uptime >= 5*time.Second || exitCode == 0 || exitCode > 128 {
		return
	}
	if containsFontCrashSignature(stderrTail) {
		log.Errorf("DMS startup failed due to a potential font/rendering crash. Try running 'fc-cache -fv' and restarting DMS.")
	} else {
		log.Errorf("DMS startup failed (exit code %d). Run 'dms doctor' for more diagnostics.", exitCode)
	}
}

func containsFontCrashSignature(logStr string) bool {
	logStr = strings.ToLower(logStr)
	signatures := []string{
		"fontconfig",
		"freetype",
		"ft_load_glyph",
		"ft_face",
		"fc-list",
		"fc-cache",
		"glyph",
		"typeface",
	}
	for _, sig := range signatures {
		if strings.Contains(logStr, sig) {
			return true
		}
	}
	return false
}
