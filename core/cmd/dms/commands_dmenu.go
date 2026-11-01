package main

import (
	"bufio"
	"bytes"
	"fmt"
	"os"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/internal/dmenuipc"
	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/duxlabs-dev/dux-shell/core/internal/qsipc"
	"github.com/spf13/cobra"
	"github.com/spf13/pflag"
)

const dmenuConnectTimeout = 5 * time.Second

var (
	dmenuPrompt       string
	dmenuLines        int
	dmenuPlaceholder  string
	dmenuPromptOnly   bool
	dmenuSep          string
	dmenuActiveSpec   string
	dmenuUrgentSpec   string
	dmenuOnlyMatch    bool
	dmenuNoCustom     bool
	dmenuSelect       string
	dmenuMesg         string
	dmenuInput        string
	dmenuPassword     bool
	dmenuMarkupRows   bool
	dmenuSync         bool
	dmenuNoRunIfEmpty bool
	dmenuFormat       string
	dmenuMultiSelect  bool
	dmenuDump         bool
	dmenuKeybindSpecs []string
	dmenuPrintInfo    bool
	dmenuView         string
	dmenuSize         string
	dmenuIcon         string
	dmenuCaseInsens   bool
	dmenuDisableHist  bool
)

var dmenuCmd = &cobra.Command{
	Use:   "dmenu",
	Short: "dmenu-compatible picker backed by the DMS app launcher",
	Long: `Read newline-separated items from stdin, show them in the DMS launcher,
and print the selected item to stdout

Examples:
  printf '%s\n' opt1 opt2 opt3 | dms dmenu -p "Pick one:"
  dms dmenu --prompt-only -p "Rename to:"

Matching is always case-insensitive; -i/--case-insensitive is accepted for
dmenu script compatibility but has no effect.

Most, but not all, rofi flags are implemented.
Long-form flags also accept rofi's single-dash form
(e.g. -only-match as well as --only-match).

Exit codes: 0 on accept, 1 if the user cancelled (or stdin was empty),
2 if the shell was unreachable.`,
	Run: runDmenu,
}

func init() {
	dmenuCmd.Flags().BoolVarP(&dmenuCaseInsens, "case-insensitive", "i", false, "No effect: matching is always case-insensitive. Accepted for dmenu/rofi script compatibility")
	dmenuCmd.Flags().StringVarP(&dmenuPrompt, "prompt", "p", "dmenu", "Prompt label")
	dmenuCmd.Flags().IntVarP(&dmenuLines, "lines", "l", 0, "Max visible result rows (0 = shell default)")
	dmenuCmd.Flags().StringVar(&dmenuPlaceholder, "placeholder", "", "Input placeholder text")
	dmenuCmd.Flags().BoolVar(&dmenuPromptOnly, "prompt-only", false, "No piped item list — pure free-text prompt")

	dmenuCmd.Flags().StringVar(&dmenuSep, "sep", "\n", "Input item separator")
	dmenuCmd.Flags().StringVarP(&dmenuActiveSpec, "active", "a", "", "Mark rows active by index (e.g. \"1,3,7:11,-3:\")")
	dmenuCmd.Flags().StringVarP(&dmenuUrgentSpec, "urgent", "u", "", "Mark rows urgent by index (same spec syntax as --active)")
	dmenuCmd.Flags().BoolVar(&dmenuOnlyMatch, "only-match", false, "Reject free text; only a listed item may be returned; also blocks Escape/click-outside cancel, forcing a real pick")
	dmenuCmd.Flags().BoolVar(&dmenuNoCustom, "no-custom", false, "Reject free text; only a listed item may be returned (unlike --only-match, Escape/cancel still works normally)")
	dmenuCmd.Flags().StringVar(&dmenuSelect, "select", "", "Pre-select the first row matching this string (or, with --dump, filter to matching rows)")
	dmenuCmd.Flags().StringVar(&dmenuMesg, "mesg", "", "Extra message line shown alongside the list")
	dmenuCmd.Flags().StringVar(&dmenuInput, "input", "", "Read items from this file instead of stdin")
	dmenuCmd.Flags().BoolVar(&dmenuPassword, "password", false, "Mask typed input (cosmetic only, not a security boundary)")
	dmenuCmd.Flags().BoolVar(&dmenuMarkupRows, "markup-rows", false, "Render each row's text as rich markup")
	dmenuCmd.Flags().BoolVar(&dmenuSync, "sync", false, "Read all input to EOF before showing the picker (default: stream as items arrive)")
	dmenuCmd.Flags().BoolVar(&dmenuNoRunIfEmpty, "no-run-if-empty", false, "If stdin is empty, exit 1 immediately with no UI shown")
	dmenuCmd.Flags().StringVar(&dmenuFormat, "format", "s", "What to print on accept: s=text (default), i=0-based index, d=1-based index, q=shell-quoted, p=markup-stripped, f=typed filter text, F=quoted filter text")
	dmenuCmd.Flags().BoolVar(&dmenuMultiSelect, "multi-select", false, "Allow selecting multiple rows; each is printed on its own line on accept")
	dmenuCmd.Flags().BoolVar(&dmenuDump, "dump", false, "Apply --select against the item list and print the result immediately; no UI is ever shown")
	dmenuCmd.Flags().StringArrayVar(&dmenuKeybindSpecs, "keybind", nil, "Bind a custom accept key (repeatable): N=keyspec, e.g. --keybind 1=ctrl+e (N is 1-19); exits 9+N (10-28) instead of 0 when accepted that way")
	dmenuCmd.Flags().BoolVar(&dmenuPrintInfo, "print-info", false, "Also print an accepted row's info metadata (the per-row \\0info\\x1f... field, see the per-row metadata protocol) on a second line")
	dmenuCmd.Flags().BoolVar(&dmenuDisableHist, "disable-history", false, "Don't add this session's search query to the launcher's persistent history (default: recorded, like other launcher modes)")

	dmenuCmd.Flags().StringVar(&dmenuView, "view", "", "Override the result view mode for this invocation: list, grid, or tile (default: list)")
	dmenuCmd.Flags().StringVar(&dmenuSize, "size", "", "Override the popup size preset for this invocation: 1-4, matching the Appearance settings size buttons (default: the shell's own launcher size setting)")
	dmenuCmd.Flags().StringVar(&dmenuIcon, "icon", "", "Show a Material Symbols icon next to the prompt badge (default: no icon)")
}

var dmenuLongFlagToken = regexp.MustCompile(`^-([a-zA-Z][a-zA-Z0-9-]+)(=.*)?$`)

func dmenuAliasableLongFlags() map[string]bool {
	set := map[string]bool{}
	dmenuCmd.Flags().VisitAll(func(f *pflag.Flag) {
		if len(f.Name) > 1 {
			set[f.Name] = true
		}
	})
	return set
}

func normalizeDmenuArgv(args []string) []string {
	if len(args) < 2 || args[1] != "dmenu" {
		return args
	}
	aliasable := dmenuAliasableLongFlags()
	out := make([]string, len(args))
	copy(out, args)
	for i := 2; i < len(out); i++ {
		tok := out[i]
		if tok == "--" {
			break
		}
		m := dmenuLongFlagToken.FindStringSubmatch(tok)
		if m == nil {
			continue
		}
		name, valueSuffix := m[1], m[2]
		if aliasable[name] {
			out[i] = "--" + name + valueSuffix
		}
	}
	return out
}

func dmenuSplitFunc(sep string) bufio.SplitFunc {
	if sep == "\n" {
		return bufio.ScanLines
	}
	sepBytes := []byte(sep)
	return func(data []byte, atEOF bool) (advance int, token []byte, err error) {
		if atEOF && len(data) == 0 {
			return 0, nil, nil
		}
		if i := bytes.Index(data, sepBytes); i >= 0 {
			return i + len(sepBytes), data[0:i], nil
		}
		if atEOF {
			return len(data), data, nil
		}
		return 0, nil, nil
	}
}

func parseIndexSpec(spec string) ([]dmenuipc.Range, error) {
	spec = strings.TrimSpace(spec)
	if spec == "" {
		return nil, nil
	}
	var ranges []dmenuipc.Range
	for _, tok := range strings.Split(spec, ",") {
		tok = strings.TrimSpace(tok)
		if tok == "" {
			continue
		}
		if idx := strings.Index(tok, ":"); idx >= 0 {
			startStr, endStr := strings.TrimSpace(tok[:idx]), strings.TrimSpace(tok[idx+1:])
			start, end := 0, -1
			if startStr != "" {
				n, err := strconv.Atoi(startStr)
				if err != nil {
					return nil, fmt.Errorf("invalid range start %q in spec %q", startStr, spec)
				}
				start = n
			}
			if endStr != "" {
				n, err := strconv.Atoi(endStr)
				if err != nil {
					return nil, fmt.Errorf("invalid range end %q in spec %q", endStr, spec)
				}
				end = n
			}
			ranges = append(ranges, dmenuipc.Range{Start: start, End: end})
			continue
		}
		n, err := strconv.Atoi(tok)
		if err != nil {
			return nil, fmt.Errorf("invalid index %q in spec %q", tok, spec)
		}
		ranges = append(ranges, dmenuipc.Range{Start: n, End: n + 1})
	}
	return ranges, nil
}

func parseDmenuKeybinds(specs []string) ([]dmenuipc.Keybind, error) {
	var out []dmenuipc.Keybind
	seen := map[int]bool{}
	for _, s := range specs {
		eq := strings.IndexByte(s, '=')
		if eq <= 0 {
			return nil, fmt.Errorf("invalid --keybind %q (expected N=keyspec, e.g. 1=ctrl+e)", s)
		}
		n, err := strconv.Atoi(strings.TrimSpace(s[:eq]))
		if err != nil || n < 1 || n > 19 {
			return nil, fmt.Errorf("invalid --keybind index in %q (expected 1-19)", s)
		}
		key := strings.TrimSpace(s[eq+1:])
		if key == "" {
			return nil, fmt.Errorf("invalid --keybind %q: empty key spec", s)
		}
		if seen[n] {
			return nil, fmt.Errorf("duplicate --keybind index %d", n)
		}
		seen[n] = true
		out = append(out, dmenuipc.Keybind{N: n, Key: key})
	}
	return out, nil
}

func dmenuParseBool(val string) bool {
	switch strings.ToLower(strings.TrimSpace(val)) {
	case "", "0", "false", "no":
		return false
	default:
		return true
	}
}

func parseDmenuRow(line string) (text string, meta *dmenuipc.ItemMeta) {
	idx := strings.IndexByte(line, 0)
	if idx < 0 {
		return line, nil
	}
	text = line[:idx]
	fields := strings.Split(line[idx+1:], "\x1f")
	m := dmenuipc.ItemMeta{}
	any := false
	for i := 0; i+1 < len(fields); i += 2 {
		key, val := fields[i], fields[i+1]
		switch key {
		case "icon":
			m.Icon = val
		case "display":
			m.Display = val
		case "meta":
			m.Meta = val
		case "info":
			m.Info = val
		case "nonselectable":
			m.NonSelectable = dmenuParseBool(val)
		case "urgent":
			m.Urgent = dmenuParseBool(val)
		case "active":
			m.Active = dmenuParseBool(val)
		case "permanent":
			m.Permanent = dmenuParseBool(val)
		case "header":
			m.Header = dmenuParseBool(val)
		default:
			continue
		}
		any = true
	}
	if !any {
		return text, nil
	}
	return text, &m
}

func validateDmenuFormat(format string) error {
	switch format {
	case "", "s", "i", "d", "q", "p", "f", "F":
		return nil
	default:
		return fmt.Errorf("invalid --format %q (expected one of s,i,d,q,p,f,F)", format)
	}
}

func validateDmenuView(view string) error {
	switch view {
	case "", "list", "grid", "tile":
		return nil
	default:
		return fmt.Errorf("invalid --view %q (expected one of list,grid,tile)", view)
	}
}

func dmenuSizePreset(size string) (string, error) {
	switch size {
	case "":
		return "", nil
	case "1":
		return "micro", nil
	case "2":
		return "compact", nil
	case "3":
		return "medium", nil
	case "4":
		return "large", nil
	default:
		return "", fmt.Errorf("invalid --size %q (expected one of 1,2,3,4)", size)
	}
}

var dmenuMarkupTagRe = regexp.MustCompile(`<[^>]*>`)

func dmenuShellQuote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
}

func dmenuFormatOutput(format string, index int, text, filterText string) (string, error) {
	switch format {
	case "", "s":
		return text, nil
	case "i":
		return strconv.Itoa(index), nil
	case "d":
		if index < 0 {
			return strconv.Itoa(index), nil
		}
		return strconv.Itoa(index + 1), nil
	case "q":
		return dmenuShellQuote(text), nil
	case "p":
		return dmenuMarkupTagRe.ReplaceAllString(text, ""), nil
	case "f":
		return filterText, nil
	case "F":
		return dmenuShellQuote(filterText), nil
	default:
		return "", fmt.Errorf("invalid --format %q (expected one of s,i,d,q,p,f,F)", format)
	}
}

func dmenuOpenInput() *os.File {
	if dmenuPromptOnly {
		return nil
	}
	if dmenuInput != "" {
		f, err := os.Open(dmenuInput)
		if err != nil {
			log.Fatalf("Error opening --input file: %v", err)
		}
		return f
	}
	return os.Stdin
}

type dmenuRow struct {
	Text string
	Meta *dmenuipc.ItemMeta
}

func dmenuReadAll(input *os.File) []dmenuRow {
	if input == nil {
		return nil
	}
	scanner := bufio.NewScanner(input)
	scanner.Buffer(make([]byte, 64*1024), 1<<20)
	scanner.Split(dmenuSplitFunc(dmenuSep))
	var rows []dmenuRow
	for scanner.Scan() {
		text, meta := parseDmenuRow(scanner.Text())
		rows = append(rows, dmenuRow{Text: text, Meta: meta})
	}
	if err := scanner.Err(); err != nil {
		log.Fatalf("Error reading items: %v", err)
	}
	return rows
}

func dmenuDumpLines(rows []dmenuRow, select_, format string, printInfo bool) ([]string, error) {
	var lower string
	filtering := select_ != ""
	if filtering {
		lower = strings.ToLower(select_)
	}
	var lines []string
	for i, row := range rows {
		if row.Meta != nil && (row.Meta.NonSelectable || row.Meta.Header) {
			continue
		}
		if filtering && !strings.Contains(strings.ToLower(row.Text), lower) {
			continue
		}
		out, err := dmenuFormatOutput(format, i, row.Text, select_)
		if err != nil {
			return nil, err
		}
		lines = append(lines, out)
		if printInfo && row.Meta != nil && row.Meta.Info != "" {
			lines = append(lines, row.Meta.Info)
		}
	}
	return lines, nil
}

func runDmenuDump(rows []dmenuRow, format string) {
	lines, err := dmenuDumpLines(rows, dmenuSelect, format, dmenuPrintInfo)
	if err != nil {
		log.Fatalf("Error formatting output: %v", err)
	}
	for _, l := range lines {
		fmt.Println(l)
	}
	os.Exit(0)
}

func runDmenu(cmd *cobra.Command, args []string) {
	if cmd.Flags().Changed("case-insensitive") {
		fmt.Fprintln(os.Stderr, "dms dmenu: warning: -i/--case-insensitive has no effect (matching is always case-insensitive)")
	}
	os.Exit(dmenuSession())
}

func dmenuSession() int {
	format := dmenuFormat
	if format == "" {
		format = "s"
	}
	if err := validateDmenuFormat(format); err != nil {
		log.Fatalf("Error in --format: %v", err)
	}

	if dmenuDump {
		input := dmenuOpenInput()
		if input != nil && input != os.Stdin {
			defer input.Close()
		}
		runDmenuDump(dmenuReadAll(input), format)
		return 0
	}

	activeRanges, err := parseIndexSpec(dmenuActiveSpec)
	if err != nil {
		log.Fatalf("Error parsing --active: %v", err)
	}
	urgentRanges, err := parseIndexSpec(dmenuUrgentSpec)
	if err != nil {
		log.Fatalf("Error parsing --urgent: %v", err)
	}
	keybinds, err := parseDmenuKeybinds(dmenuKeybindSpecs)
	if err != nil {
		log.Fatalf("Error parsing --keybind: %v", err)
	}
	if err := validateDmenuView(dmenuView); err != nil {
		log.Fatalf("Error in --view: %v", err)
	}
	dmenuSizePresetName, err := dmenuSizePreset(dmenuSize)
	if err != nil {
		log.Fatalf("Error in --size: %v", err)
	}

	input := dmenuOpenInput()
	if input != nil && input != os.Stdin {
		defer input.Close()
	}

	var scanner *bufio.Scanner
	if input != nil {
		scanner = bufio.NewScanner(input)
		scanner.Buffer(make([]byte, 64*1024), 1<<20)
		scanner.Split(dmenuSplitFunc(dmenuSep))
	}

	var bufferedItems []string
	streaming := scanner != nil && !dmenuSync
	if scanner != nil && !streaming {
		for scanner.Scan() {
			bufferedItems = append(bufferedItems, scanner.Text())
		}
		if err := scanner.Err(); err != nil {
			log.Errorf("Error reading items: %v", err)
			return 1
		}
	}

	var pendingFirstItem string
	havePendingFirstItem := false
	if dmenuNoRunIfEmpty {
		if streaming {
			if !scanner.Scan() {
				if err := scanner.Err(); err != nil {
					log.Errorf("Error reading items: %v", err)
					return 1
				}
				return 1
			}
			pendingFirstItem = scanner.Text()
			havePendingFirstItem = true
		} else if len(bufferedItems) == 0 {
			return 1
		}
	}

	release, err := dmenuipc.AcquireQueueSlot(func() {
		fmt.Fprintln(os.Stderr, "dms dmenu: waiting for another dmenu session to finish...")
	})
	if err != nil {
		log.Fatalf("Error acquiring dmenu queue slot: %v", err)
	}
	defer release()

	sess, err := dmenuipc.Listen()
	if err != nil {
		log.Fatalf("Error creating dmenu socket: %v", err)
	}
	defer sess.Close()

	pid, ok := shellApp.SessionPID()
	if !ok {
		log.Errorf("DMS shell is not running")
		return 1
	}

	mode := "dmenu:" + sess.Path()
	if _, _, err := qsipc.Call(qsipc.SocketPathForPID(pid), "launcher", "openWith", []string{mode}); err != nil {
		log.Errorf("Error opening launcher: %v", err)
		return 1
	}

	conn, err := sess.Accept(dmenuConnectTimeout)
	if err != nil {
		log.Debugf("dmenu: shell never connected: %v", err)
		return 2
	}
	defer conn.Close()

	header := dmenuipc.Header{
		Prompt:         dmenuPrompt,
		Placeholder:    dmenuPlaceholder,
		Lines:          dmenuLines,
		PromptOnly:     dmenuPromptOnly,
		Select:         dmenuSelect,
		Mesg:           dmenuMesg,
		Password:       dmenuPassword,
		MarkupRows:     dmenuMarkupRows,
		OnlyMatch:      dmenuOnlyMatch,
		NoCustom:       dmenuNoCustom,
		MultiSelect:    dmenuMultiSelect,
		Active:         activeRanges,
		Urgent:         urgentRanges,
		Keybinds:       keybinds,
		View:           dmenuView,
		Size:           dmenuSizePresetName,
		Icon:           dmenuIcon,
		DisableHistory: dmenuDisableHist,
	}
	if err := conn.SendHeader(header); err != nil {
		log.Debugf("dmenu: failed to send header: %v", err)
		return 2
	}

	var sendErr error
	sendItem := func(line string) {
		text, meta := parseDmenuRow(line)
		if err := conn.SendItem(text, meta); err != nil {
			log.Debugf("dmenu: failed to send item: %v", err)
			sendErr = err
		}
	}

	if streaming {
		if havePendingFirstItem && sendErr == nil {
			sendItem(pendingFirstItem)
		}
		for sendErr == nil && scanner.Scan() {
			sendItem(scanner.Text())
		}
		if err := scanner.Err(); err != nil {
			log.Debugf("dmenu: error reading items mid-stream: %v", err)
			return 2
		}
	} else {
		for _, item := range bufferedItems {
			if sendErr != nil {
				break
			}
			sendItem(item)
		}
	}
	if sendErr != nil {
		return 2
	}
	if err := conn.SendEnd(); err != nil {
		log.Debugf("dmenu: failed to send end marker: %v", err)
		return 2
	}

	sel, selected, err := conn.ReadSelection()
	if err != nil {
		log.Debugf("dmenu: failed to read result: %v", err)
		return 2
	}
	if !selected {
		return 1
	}

	switch sel.Kind {
	case "multi":
		for _, item := range sel.Items {
			out, err := dmenuFormatOutput(format, item.Index, item.Text, sel.FilterText)
			if err != nil {
				log.Errorf("Error formatting output: %v", err)
				return 1
			}
			fmt.Println(out)
			if dmenuPrintInfo && item.Info != "" {
				fmt.Println(item.Info)
			}
		}
	case "freetext":
		out, err := dmenuFormatOutput(format, -1, sel.Text, sel.FilterText)
		if err != nil {
			log.Errorf("Error formatting output: %v", err)
			return 1
		}
		fmt.Println(out)
	default: // "row"
		out, err := dmenuFormatOutput(format, sel.Index, sel.Text, sel.FilterText)
		if err != nil {
			log.Errorf("Error formatting output: %v", err)
			return 1
		}
		fmt.Println(out)
		if dmenuPrintInfo && sel.Info != "" {
			fmt.Println(sel.Info)
		}
	}

	return dmenuKeybindExitCode(sel.KeybindN)
}

func dmenuKeybindExitCode(keybindN int) int {
	if keybindN <= 0 {
		return 0
	}
	return 9 + keybindN
}
