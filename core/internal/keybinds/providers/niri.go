package providers

import (
	"bufio"
	"encoding/json"
	"fmt"
	"maps"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/internal/keybinds"
	"github.com/sblinch/kdl-go/document"
)

type NiriProvider struct {
	configDir        string
	dmsBindsIncluded bool
	parsed           bool
}

type niriActionPart struct {
	value  string
	quoted bool
}

var niriActionPropertyOrder = []string{"focus", "show-pointer", "write-to-disk", "skip-confirmation", "delay-ms", "filter", "scope"}
var niriActionProperties = map[string]struct{}{
	"focus":             {},
	"show-pointer":      {},
	"write-to-disk":     {},
	"skip-confirmation": {},
	"delay-ms":          {},
	"filter":            {},
	"scope":             {},
}

func NewNiriProvider(configDir string) *NiriProvider {
	if configDir == "" {
		configDir = defaultNiriConfigDir()
	}
	return &NiriProvider{
		configDir: configDir,
	}
}

func defaultNiriConfigDir() string {
	configDir, err := os.UserConfigDir()
	if err != nil {
		return ""
	}
	return filepath.Join(configDir, "niri")
}

func (n *NiriProvider) Name() string {
	return "niri"
}

func (n *NiriProvider) GetCheatSheet() (*keybinds.CheatSheet, error) {
	result, err := ParseNiriKeys(n.configDir)
	if err != nil {
		return nil, fmt.Errorf("failed to parse niri config: %w", err)
	}

	n.dmsBindsIncluded = result.DMSBindsIncluded
	n.parsed = true

	categorizedBinds := make(map[string][]keybinds.Keybind)
	n.convertSection(result.Section, "", categorizedBinds, result.ConflictingConfigs)

	sheet := &keybinds.CheatSheet{
		Title:            "Niri Keybinds",
		Provider:         n.Name(),
		Binds:            categorizedBinds,
		DMSBindsIncluded: result.DMSBindsIncluded,
	}
	sheet.SetMod(niriModKey(result, niriNested()))

	if result.DMSStatus != nil {
		sheet.DMSStatus = keybinds.DMSBindsStatusFrom(*result.DMSStatus)
	}

	return sheet, nil
}

func (n *NiriProvider) HasDMSBindsIncluded() bool {
	if n.parsed {
		return n.dmsBindsIncluded
	}

	result, err := ParseNiriKeys(n.configDir)
	if err != nil {
		return false
	}

	n.dmsBindsIncluded = result.DMSBindsIncluded
	n.parsed = true
	return n.dmsBindsIncluded
}

func (n *NiriProvider) convertSection(section *NiriSection, subcategory string, categorizedBinds map[string][]keybinds.Keybind, conflicts map[string]*NiriKeyBinding) {
	currentSubcat := subcategory
	if section.Name != "" {
		currentSubcat = section.Name
	}

	for _, kb := range section.Keybinds {
		category := n.categorizeByAction(kb.Action)
		bind := n.convertKeybind(&kb, currentSubcat, conflicts)
		categorizedBinds[category] = append(categorizedBinds[category], bind)
	}

	for _, child := range section.Children {
		n.convertSection(&child, currentSubcat, categorizedBinds, conflicts)
	}
}

func (n *NiriProvider) categorizeByAction(action string) string {
	switch {
	case action == "next-window" || action == "previous-window":
		return "Alt-Tab"
	case strings.Contains(action, "screenshot"):
		return "Screenshot"
	case action == "show-hotkey-overlay" || action == "toggle-overview":
		return "Overview"
	case action == "quit" ||
		action == "power-off-monitors" ||
		action == "power-on-monitors" ||
		action == "suspend" ||
		action == "do-screen-transition" ||
		action == "toggle-keyboard-shortcuts-inhibit" ||
		action == "toggle-touchpad" ||
		strings.Contains(action, "dpms"):
		return "System"
	case action == "spawn":
		return "Execute"
	case strings.Contains(action, "workspace"):
		return "Workspace"
	case strings.HasPrefix(action, "focus-monitor") ||
		strings.HasPrefix(action, "move-column-to-monitor") ||
		strings.HasPrefix(action, "move-window-to-monitor"):
		return "Monitor"
	case strings.Contains(action, "window") ||
		strings.Contains(action, "focus") ||
		strings.Contains(action, "move") ||
		strings.Contains(action, "swap") ||
		strings.Contains(action, "resize") ||
		strings.Contains(action, "column"):
		return "Window"
	default:
		return "Other"
	}
}

func (n *NiriProvider) convertKeybind(kb *NiriKeyBinding, subcategory string, conflicts map[string]*NiriKeyBinding) keybinds.Keybind {
	rawAction := n.formatRawAction(kb.Action, kb.Args)
	keyStr := n.formatKey(kb)

	source := "config"
	if strings.Contains(kb.Source, "dms/binds.kdl") {
		source = "dms-default"
	}

	bind := keybinds.Keybind{
		Key:             keyStr,
		Description:     kb.Description,
		Action:          rawAction,
		Subcategory:     subcategory,
		Source:          source,
		HideOnOverlay:   kb.HideOnOverlay,
		CooldownMs:      kb.CooldownMs,
		AllowWhenLocked: kb.AllowWhenLocked,
		AllowInhibiting: kb.AllowInhibiting,
		Repeat:          kb.Repeat,
		Trigger:         kb.Trigger,
		PassThrough:     kb.PassThrough,
	}
	// Sent back verbatim as --release-action, so argument boundaries must survive.
	if kb.ReleaseAction != "" {
		bind.ReleaseAction = formatNiriAction(kb.ReleaseAction, kb.ReleaseArgs)
	}

	if source == "dms-default" && conflicts != nil {
		if conflictKb, ok := conflicts[normalizeNiriBindKey(keyStr)]; ok {
			bind.Conflict = &keybinds.Keybind{
				Key:         keyStr,
				Description: conflictKb.Description,
				Action:      n.formatRawAction(conflictKb.Action, conflictKb.Args),
				Source:      "config",
			}
		}
	}

	return bind
}

// Sent back verbatim to SetBind, so argument boundaries must survive.
func (n *NiriProvider) formatRawAction(action string, args []string) string {
	// The shell field rebuilds this quoted, so a bare one-word command would read as edited.
	if action == "spawn" && len(args) == 3 && args[1] == "-c" && (args[0] == "sh" || args[0] == "bash") {
		return "spawn " + args[0] + ` -c "` + niriActionArgEscaper.Replace(args[2]) + `"`
	}
	return formatNiriAction(action, args)
}

func (n *NiriProvider) formatKey(kb *NiriKeyBinding) string {
	parts := make([]string, 0, len(kb.Mods)+1)
	parts = append(parts, kb.Mods...)
	parts = append(parts, kb.Key)
	return strings.Join(parts, "+")
}

func (n *NiriProvider) ModKey() keybinds.ModKey {
	result, err := ParseNiriKeys(n.configDir)
	if err != nil {
		return keybinds.DefaultModKey()
	}
	return niriModKey(result, niriNested())
}

// Mirrors niri's Backend::mod_key: nested (winit) sessions use mod-key-nested,
// falling back to Alt, or to Super when mod-key itself is Alt.
func niriModKey(result *NiriParseResult, nested bool) keybinds.ModKey {
	if !nested {
		return keybinds.ConfiguredModKey("Mod", result.ModKey)
	}
	if result.ModKeyNested != "" {
		return keybinds.ConfiguredModKey("Mod", result.ModKeyNested)
	}
	resolved := "Alt"
	if keybinds.CanonicalModifier(result.ModKey) == "Alt" {
		resolved = "Super"
	}
	return keybinds.ModKey{Symbol: "Mod", Resolved: resolved, Source: keybinds.ModSourceRuntime}
}

var niriNested = detectNiriNested

// The winit backend exposes a single output named "winit"; niri has no IPC query for its backend.
func detectNiriNested() bool {
	socket := os.Getenv("NIRI_SOCKET")
	if socket == "" {
		return false
	}
	conn, err := net.DialTimeout("unix", socket, time.Second)
	if err != nil {
		return false
	}
	defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(time.Second))
	if _, err := conn.Write([]byte("\"Outputs\"\n")); err != nil {
		return false
	}
	line, err := bufio.NewReader(conn).ReadBytes('\n')
	if err != nil {
		return false
	}
	var reply struct {
		Ok struct {
			Outputs map[string]json.RawMessage `json:"Outputs"`
		} `json:"Ok"`
	}
	if err := json.Unmarshal(line, &reply); err != nil {
		return false
	}
	_, nested := reply.Ok.Outputs["winit"]
	return nested
}

func (n *NiriProvider) GetOverridePath() string {
	return filepath.Join(n.configDir, "dms", "binds.kdl")
}

func (n *NiriProvider) validateAction(action string) error {
	action = strings.TrimSpace(action)
	switch {
	case action == "":
		return fmt.Errorf("action cannot be empty")
	case action == "spawn" || action == "spawn ":
		return fmt.Errorf("spawn command requires arguments")
	case strings.HasPrefix(action, "spawn "):
		rest := strings.TrimSpace(strings.TrimPrefix(action, "spawn "))
		switch rest {
		case "":
			return fmt.Errorf("spawn command requires arguments")
		case "sh -c \"\"", "sh -c ''", "bash -c \"\"", "bash -c ''":
			return fmt.Errorf("shell command cannot be empty")
		}
	}
	return nil
}

func (n *NiriProvider) SetBind(key, action, description string, options map[string]any) error {
	if err := n.validateAction(action); err != nil {
		return err
	}

	overridePath := n.GetOverridePath()

	if err := os.MkdirAll(filepath.Dir(overridePath), 0o755); err != nil {
		return fmt.Errorf("failed to create dms directory: %w", err)
	}

	existingBinds, err := n.loadOverrideBinds()
	if err != nil {
		existingBinds = make(map[string]*overrideBind)
	}

	normalizedKey := normalizeNiriBindKey(key)
	opts := maps.Clone(options)
	if opts == nil {
		opts = make(map[string]any)
	}
	// A trigger-unaware edit must not make a release-only Mod bind swallow every Mod chord.
	if old, ok := existingBinds[normalizedKey]; ok {
		if _, set := opts["trigger"]; !set {
			for _, name := range []string{"trigger", "release-action", "pass-through"} {
				if _, set := opts[name]; set {
					continue
				}
				if v, ok := old.Options[name]; ok {
					opts[name] = v
				}
			}
		}
	}
	if err := n.validateBindOptions(key, opts); err != nil {
		return err
	}

	existingBinds[normalizedKey] = &overrideBind{
		Key:         key,
		Action:      action,
		Description: description,
		Options:     opts,
	}

	return n.writeOverrideBinds(existingBinds)
}

func (n *NiriProvider) validateBindOptions(key string, opts map[string]any) error {
	trigger, _ := opts["trigger"].(string)
	releaseAction, _ := opts["release-action"].(string)
	switch trigger {
	case "", "press", niriTriggerRelease:
		if releaseAction != "" {
			return fmt.Errorf("a release action requires trigger %q", niriTriggerBoth)
		}
	case niriTriggerBoth:
		if releaseAction == "" {
			return fmt.Errorf("trigger %q requires a release action", niriTriggerBoth)
		}
		if err := n.validateAction(releaseAction); err != nil {
			return fmt.Errorf("release action: %w", err)
		}
	default:
		return fmt.Errorf("unknown trigger %q (want press, release or both)", trigger)
	}
	if (trigger == niriTriggerRelease || trigger == niriTriggerBoth) && isNiriScrollTrigger(key) {
		return fmt.Errorf("release actions are not supported for scroll binds")
	}
	if _, ok := opts["pass-through"]; ok && !isNiriKeyboardTrigger(key) {
		return fmt.Errorf("pass-through is only supported for keyboard binds")
	}
	return nil
}

func (n *NiriProvider) RemoveBind(key string) error {
	existingBinds, err := n.loadOverrideBinds()
	if err != nil {
		return nil
	}

	delete(existingBinds, normalizeNiriBindKey(key))
	return n.writeOverrideBinds(existingBinds)
}

func (n *NiriProvider) ResetBind(key string) error {
	return n.RemoveBind(key)
}

type overrideBind struct {
	Key         string
	Action      string
	Description string
	Options     map[string]any
}

func (n *NiriProvider) loadOverrideBinds() (map[string]*overrideBind, error) {
	overridePath := n.GetOverridePath()
	binds := make(map[string]*overrideBind)

	data, err := os.ReadFile(overridePath)
	if os.IsNotExist(err) {
		return binds, nil
	}
	if err != nil {
		return nil, err
	}

	parser := NewNiriParser(filepath.Dir(overridePath))
	parser.currentSource = overridePath

	doc, err := parseKDL(data)
	if err != nil {
		return nil, err
	}

	for _, node := range doc.Nodes {
		if node.Name.String() != "binds" || node.Children == nil {
			continue
		}
		for _, child := range node.Children {
			kb := parser.parseKeybindNode(child, "")
			if kb == nil {
				continue
			}
			keyStr := parser.formatBindKey(kb)

			pressNode, releaseNode := niriBoundActions(child)
			if pressNode == nil {
				pressNode = releaseNode
			}
			action := n.buildActionFromNode(pressNode)
			if action == "" {
				action = n.formatRawAction(kb.Action, kb.Args)
			}

			binds[normalizeNiriBindKey(keyStr)] = &overrideBind{
				Key:         keyStr,
				Action:      action,
				Description: kb.Description,
				Options:     n.extractOptions(child),
			}
		}
	}

	return binds, nil
}

func (n *NiriProvider) buildActionFromNode(actionNode *document.Node) string {
	if actionNode == nil {
		return ""
	}

	actionName, args := niriActionNameArgs(actionNode)
	if actionName == "" {
		return ""
	}
	return formatNiriAction(actionName, args)
}

// Inverse of parseActionParts: positional args are quoted so they split back exactly.
func formatNiriAction(action string, args []string) string {
	parts := []string{action}
	for _, arg := range args {
		if name, _, ok := strings.Cut(arg, "="); ok {
			if _, isProp := niriActionProperties[name]; isProp {
				parts = append(parts, arg)
				continue
			}
		}
		parts = append(parts, quoteNiriActionArg(arg))
	}
	return strings.Join(parts, " ")
}

var niriActionArgEscaper = strings.NewReplacer(`\`, `\\`, `"`, `\"`)

func quoteNiriActionArg(arg string) string {
	if arg != "" && !strings.ContainsAny(arg, " \t\"\\") {
		return arg
	}
	return `"` + niriActionArgEscaper.Replace(arg) + `"`
}

func (n *NiriProvider) extractOptions(node *document.Node) map[string]any {
	opts := make(map[string]any)
	switch pressNode, releaseNode := niriBoundActions(node); {
	case pressNode != nil && releaseNode != nil:
		opts["trigger"] = niriTriggerBoth
		opts["release-action"] = n.buildActionFromNode(releaseNode)
	case releaseNode != nil:
		opts["trigger"] = niriTriggerRelease
	}

	if node.Properties == nil {
		return opts
	}

	if val, ok := node.Properties.Get("repeat"); ok {
		opts["repeat"] = val.String() == "true"
	}
	if val, ok := node.Properties.Get("pass-through"); ok {
		opts["pass-through"] = val.String() == "true"
	}
	if val, ok := node.Properties.Get("cooldown-ms"); ok {
		if ms, err := strconv.Atoi(val.String()); err == nil {
			opts["cooldown-ms"] = ms
		}
	}
	if val, ok := node.Properties.Get("allow-when-locked"); ok {
		opts["allow-when-locked"] = val.String() == "true"
	}
	if val, ok := node.Properties.Get("allow-inhibiting"); ok {
		opts["allow-inhibiting"] = val.String() == "true"
	}
	return opts
}

func (n *NiriProvider) isRecentWindowsAction(action string) bool {
	switch action {
	case "next-window", "previous-window":
		return true
	default:
		return false
	}
}

func (n *NiriProvider) buildBindNode(bind *overrideBind) *document.Node {
	node := document.NewNode()
	node.SetName(bind.Key)

	trigger, _ := bind.Options["trigger"].(string)
	releaseAction, _ := bind.Options["release-action"].(string)
	if isNiriScrollTrigger(bind.Key) || (trigger == niriTriggerBoth && releaseAction == "") {
		trigger = ""
	}

	if bind.Options != nil {
		switch v, ok := bind.Options["repeat"]; {
		case ok && v == false:
			node.AddProperty("repeat", false, "")
		case ok && v == true && trigger != niriTriggerRelease:
			node.AddProperty("repeat", true, "")
		}
		if v, ok := bind.Options["pass-through"].(bool); ok {
			node.AddProperty("pass-through", v, "")
		}
		if v, ok := bind.Options["cooldown-ms"]; ok {
			switch val := v.(type) {
			case int:
				node.AddProperty("cooldown-ms", val, "")
			case string:
				if ms, err := strconv.Atoi(val); err == nil {
					node.AddProperty("cooldown-ms", ms, "")
				}
			}
		}
		if v, ok := bind.Options["allow-when-locked"]; ok && v == true {
			node.AddProperty("allow-when-locked", true, "")
		}
		if v, ok := bind.Options["allow-inhibiting"]; ok && v == false {
			node.AddProperty("allow-inhibiting", false, "")
		}
	}

	if bind.Description != "" {
		node.AddProperty("hotkey-overlay-title", bind.Description, "")
	}

	switch trigger {
	case niriTriggerRelease:
		node.AddNode(n.wrapActionNode("release", bind.Action))
	case niriTriggerBoth:
		node.AddNode(n.wrapActionNode("press", bind.Action))
		node.AddNode(n.wrapActionNode("release", releaseAction))
	default:
		node.AddNode(n.buildActionNode(bind.Action))
	}

	return node
}

func (n *NiriProvider) wrapActionNode(section, action string) *document.Node {
	node := document.NewNode()
	node.SetName(section)
	node.AddNode(n.buildActionNode(action))
	return node
}

func (n *NiriProvider) buildActionNode(action string) *document.Node {
	action = strings.TrimSpace(action)
	node := document.NewNode()

	parts := n.parseActionParts(action)
	if len(parts) == 0 {
		node.SetName(action)
		return node
	}

	node.SetName(parts[0].value)
	for _, arg := range parts[1:] {
		if n.isNiriActionPropertyToken(arg) {
			kv := strings.SplitN(arg.value, "=", 2)
			switch kv[1] {
			case "true":
				node.AddProperty(kv[0], true, "")
			case "false":
				node.AddProperty(kv[0], false, "")
			default:
				node.AddProperty(kv[0], kv[1], "")
			}
			continue
		}
		node.AddArgument(arg.value, "")
	}
	return node
}

func (n *NiriProvider) isNiriActionPropertyToken(part niriActionPart) bool {
	if !strings.Contains(part.value, "=") {
		return false
	}
	key, _, ok := strings.Cut(part.value, "=")
	if !ok {
		return false
	}
	_, ok = niriActionProperties[key]
	return ok
}

func (n *NiriProvider) parseActionParts(action string) []niriActionPart {
	var parts []niriActionPart
	var current strings.Builder
	var inQuote, escaped, wasQuoted bool

	for _, r := range action {
		switch {
		case escaped:
			current.WriteRune(r)
			escaped = false
		case r == '\\':
			escaped = true
		case r == '"':
			wasQuoted = true
			inQuote = !inQuote
		case r == ' ' && !inQuote:
			if current.Len() > 0 || wasQuoted {
				parts = append(parts, niriActionPart{value: current.String(), quoted: wasQuoted})
				current.Reset()
				wasQuoted = false
			}
		default:
			current.WriteRune(r)
		}
	}
	if current.Len() > 0 || wasQuoted {
		parts = append(parts, niriActionPart{value: current.String(), quoted: wasQuoted})
	}
	return parts
}

func (n *NiriProvider) writeOverrideBinds(binds map[string]*overrideBind) error {
	overridePath := n.GetOverridePath()
	content := n.generateBindsContent(binds)

	if err := n.validateBindsContent(content); err != nil {
		return err
	}

	return os.WriteFile(overridePath, []byte(content), 0o644)
}

func (n *NiriProvider) getBindSortPriority(action string) int {
	switch {
	case strings.HasPrefix(action, "spawn") && strings.Contains(action, "dms"):
		return 0
	case strings.Contains(action, "workspace"):
		return 1
	case strings.Contains(action, "window") || strings.Contains(action, "column") ||
		strings.Contains(action, "focus") || strings.Contains(action, "move") ||
		strings.Contains(action, "swap") || strings.Contains(action, "resize"):
		return 2
	case strings.HasPrefix(action, "focus-monitor") || strings.Contains(action, "monitor"):
		return 3
	case strings.Contains(action, "screenshot"):
		return 4
	case action == "quit" || action == "power-off-monitors" || strings.Contains(action, "dpms"):
		return 5
	case strings.HasPrefix(action, "spawn"):
		return 6
	default:
		return 7
	}
}

func (n *NiriProvider) generateBindsContent(binds map[string]*overrideBind) string {
	if len(binds) == 0 {
		return "binds {}\n"
	}

	var regularBinds, recentWindowsBinds []*overrideBind
	for _, bind := range binds {
		switch {
		case n.isRecentWindowsAction(bind.Action):
			recentWindowsBinds = append(recentWindowsBinds, bind)
		default:
			regularBinds = append(regularBinds, bind)
		}
	}

	sort.Slice(regularBinds, func(i, j int) bool {
		pi, pj := n.getBindSortPriority(regularBinds[i].Action), n.getBindSortPriority(regularBinds[j].Action)
		if pi != pj {
			return pi < pj
		}
		return regularBinds[i].Key < regularBinds[j].Key
	})

	sort.Slice(recentWindowsBinds, func(i, j int) bool {
		return recentWindowsBinds[i].Key < recentWindowsBinds[j].Key
	})

	var sb strings.Builder

	sb.WriteString("binds {\n")
	for _, bind := range regularBinds {
		n.writeBindNode(&sb, bind, "    ")
	}
	sb.WriteString("}\n")

	if len(recentWindowsBinds) > 0 {
		sb.WriteString("\nrecent-windows {\n")
		sb.WriteString("    binds {\n")
		for _, bind := range recentWindowsBinds {
			n.writeBindNode(&sb, bind, "        ")
		}
		sb.WriteString("    }\n")
		sb.WriteString("}\n")
	}

	return sb.String()
}

func (n *NiriProvider) writeBindNode(sb *strings.Builder, bind *overrideBind, indent string) {
	node := n.buildBindNode(bind)

	sb.WriteString(indent)
	sb.WriteString(node.Name.String())

	if node.Properties.Exist() {
		sb.WriteString(" ")
		sb.WriteString(strings.TrimLeft(node.Properties.String(), " "))
	}

	pressNode, releaseNode := niriBoundActions(node)
	if releaseNode == nil {
		sb.WriteString(" { ")
		n.writeActionNode(sb, pressNode)
		sb.WriteString("; }\n")
		return
	}

	// niri rejects the one-line `Mod { release { x; } }`; the section must close on its own line.
	sb.WriteString(" {\n")
	if pressNode != nil {
		sb.WriteString(indent + "    press { ")
		n.writeActionNode(sb, pressNode)
		sb.WriteString("; }\n")
	}
	sb.WriteString(indent + "    release { ")
	n.writeActionNode(sb, releaseNode)
	sb.WriteString("; }\n")
	sb.WriteString(indent + "}\n")
}

func (n *NiriProvider) writeActionNode(sb *strings.Builder, actionNode *document.Node) {
	if actionNode == nil {
		return
	}
	actionName := actionNode.Name.String()
	sb.WriteString(actionName)
	forceQuote := actionName == "spawn"
	for _, arg := range actionNode.Arguments {
		sb.WriteString(" ")
		n.writeArg(sb, arg.ValueString(), forceQuote)
	}
	if actionNode.Properties.Exist() {
		sb.WriteString(" ")
		sb.WriteString(strings.TrimLeft(actionNode.Properties.String(), " "))
	}
}

func (n *NiriProvider) writeArg(sb *strings.Builder, val string, forceQuote bool) {
	if !forceQuote && n.isNumericArg(val) {
		sb.WriteString(val)
		return
	}
	sb.WriteString("\"")
	sb.WriteString(niriActionArgEscaper.Replace(val))
	sb.WriteString("\"")
}

func (n *NiriProvider) isNumericArg(val string) bool {
	if val == "" {
		return false
	}
	start := 0
	if val[0] == '-' || val[0] == '+' {
		if len(val) == 1 {
			return false
		}
		start = 1
	}
	for i := start; i < len(val); i++ {
		if val[i] < '0' || val[i] > '9' {
			return false
		}
	}
	return true
}

func (n *NiriProvider) validateBindsContent(content string) error {
	tmpFile, err := os.CreateTemp("", "dms-binds-*.kdl")
	if err != nil {
		return fmt.Errorf("failed to create temp file: %w", err)
	}
	defer os.Remove(tmpFile.Name())

	if _, err := tmpFile.WriteString(content); err != nil {
		tmpFile.Close()
		return fmt.Errorf("failed to write temp file: %w", err)
	}
	tmpFile.Close()

	if output, err := niriValidate(tmpFile.Name()); err != nil {
		return fmt.Errorf("invalid config: %s", strings.TrimSpace(string(output)))
	}

	return nil
}

var niriValidate = func(path string) ([]byte, error) {
	return exec.Command("niri", "validate", "-c", path).CombinedOutput()
}
