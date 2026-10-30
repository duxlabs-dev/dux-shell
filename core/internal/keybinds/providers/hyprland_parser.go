package providers

import (
	"github.com/duxlabs-dev/dux-shell/core/internal/configfrag"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"

	"github.com/duxlabs-dev/dux-shell/core/internal/luaconfig"
	"github.com/duxlabs-dev/dux-shell/core/internal/utils"
)

type HyprlandKeyBinding struct {
	Mods       []string `json:"mods"`
	Key        string   `json:"key"`
	Dispatcher string   `json:"dispatcher"`
	Params     string   `json:"params"`
	Comment    string   `json:"comment"`
	Source     string   `json:"source"`
	Flags      string   `json:"flags"` // hl.bind options as letters, see hyprlandBindFlagOptions; k=device, d=description
	Device     string   `json:"-"`     // raw Lua device table
}

type HyprlandSection struct {
	Children []HyprlandSection    `json:"children"`
	Keybinds []HyprlandKeyBinding `json:"keybinds"`
	Name     string               `json:"name"`
}

type HyprlandParser struct {
	configDir          string
	currentSource      string
	dmsBindsExists     bool
	walker             *configfrag.Walker
	bindsAfterDMS      int
	dmsBindKeys        map[string]bool
	configBindKeys     map[string]bool
	conflictingConfigs map[string]*HyprlandKeyBinding
	bindMap            map[string]*HyprlandKeyBinding
	bindOrder          []string
	processedFiles     map[string]bool
	dmsProcessed       bool
	removedKeys        map[string]bool // hl.unbind targets
	// Files that unbind then rebind a removed key; only their own bind survives the removal.
	rebindSources  map[string]map[string]bool
	fileUnbinds    map[string]bool // hl.unbind targets seen so far in the file being parsed
	defaultDMSKeys map[string]bool // keys present in dms/binds.lua
	mainMod        string
}

func NewHyprlandParser(configDir string) *HyprlandParser {
	return &HyprlandParser{
		configDir:          configDir,
		walker:             configfrag.NewWalker(isDMSBindsPrimarySourcePath),
		dmsBindKeys:        make(map[string]bool),
		configBindKeys:     make(map[string]bool),
		conflictingConfigs: make(map[string]*HyprlandKeyBinding),
		bindMap:            make(map[string]*HyprlandKeyBinding),
		bindOrder:          []string{},
		processedFiles:     make(map[string]bool),
		removedKeys:        make(map[string]bool),
		rebindSources:      make(map[string]map[string]bool),
		defaultDMSKeys:     make(map[string]bool),
	}
}

var hyprlandDirectionWords = map[string]string{
	"l": "left", "left": "left",
	"r": "right", "right": "right",
	"u": "up", "up": "up", "t": "up",
	"d": "down", "down": "down", "b": "down",
}

func hyprlandAutogenerateComment(dispatcher, params string) string {
	dir, isDir := hyprlandDirectionWords[params]
	switch dispatcher {
	case "resizewindow":
		return "Resize window"

	case "movewindow":
		if params == "" {
			return "Move window"
		}
		if monitor, ok := strings.CutPrefix(params, "mon:"); ok {
			return "move to " + describeHyprlandMonitor(monitor)
		}
		if isDir {
			return "move in " + dir + " direction"
		}
		return "move window " + params

	case "movewindoworgroup":
		if isDir {
			return "move window or group " + dir
		}
		return "move window or group " + params

	case "moveintogroup":
		if isDir {
			return "move into " + dir + " group"
		}
		return "move into group " + params

	case "moveintoorcreategroup":
		if isDir {
			return "move into or create " + dir + " group"
		}
		return "move into or create group " + params

	case "moveoutofgroup":
		return "move out of group"

	case "togglegroup":
		return "toggle group"

	case "changegroupactive":
		switch params {
		case "f", "":
			return "next window in group"
		case "b":
			return "previous window in group"
		}
		return "focus group window " + params

	case "movegroupwindow":
		if params == "b" {
			return "move window back in group"
		}
		return "move window forward in group"

	case "pin":
		return "pin (show on all workspaces)"

	case "splitratio":
		return "Window split ratio " + params

	case "layoutmsg":
		switch params {
		case "togglesplit":
			return "Toggle split"
		case "swapsplit":
			return "Swap split"
		}
		if ratio, ok := strings.CutPrefix(params, "splitratio "); ok {
			return "Window split ratio " + ratio
		}
		return "Layout: " + params

	case "togglefloating":
		return "Float/unfloat window"

	case "resizeactive":
		return describeHyprlandResize(params)

	case "moveactive":
		return describeHyprlandMove(params)

	case "killactive":
		return "Close window"

	case "fullscreen":
		mode, action := firstParam(params)
		fsMap := map[string]string{
			"":  "fullscreen",
			"0": "fullscreen",
			"1": "maximization",
			"2": "fullscreen on Hyprland's side",
		}
		fs, ok := fsMap[mode]
		if !ok {
			fs = "fullscreen"
		}
		switch action {
		case "set":
			return "Enter " + fs
		case "unset":
			return "Exit " + fs
		}
		return "Toggle " + fs

	case "focuswindow":
		if class, ok := strings.CutPrefix(params, "class:"); ok {
			return "focus " + class + " window"
		}
		return "focus window " + params

	case "workspace":
		switch params {
		case "+1":
			return "focus right"
		case "-1":
			return "focus left"
		}
		return "focus " + describeHyprlandWorkspace(params)

	case "movefocus":
		if isDir {
			return "move focus " + dir
		}
		return "move focus " + params

	case "focusmonitor":
		return "focus " + describeHyprlandMonitor(params)

	case "swapwindow":
		if isDir {
			return "swap in " + dir + " direction"
		}
		return "swap window " + params

	case "movetoworkspace":
		ws, _ := firstParam(params)
		switch ws {
		case "+1":
			return "move to right workspace (non-silent)"
		case "-1":
			return "move to left workspace (non-silent)"
		}
		return "move to " + describeHyprlandWorkspace(ws) + " (non-silent)"

	case "movetoworkspacesilent":
		ws, _ := firstParam(params)
		switch ws {
		case "+1":
			return "move to right workspace"
		case "-1":
			return "move to left workspace"
		}
		return "move to " + describeHyprlandWorkspace(ws)

	case "togglespecialworkspace":
		return "toggle special"

	case "exec":
		return params

	default:
		return ""
	}
}

func describeHyprlandWorkspace(ws string) string {
	if name, ok := strings.CutPrefix(ws, "special:"); ok {
		return "special workspace " + name
	}
	if ws == "special" {
		return "special workspace"
	}
	return "workspace " + ws
}

func describeHyprlandMonitor(monitor string) string {
	if dir, ok := hyprlandDirectionWords[monitor]; ok {
		return dir + " monitor"
	}
	switch monitor {
	case "+1":
		return "next monitor"
	case "-1":
		return "previous monitor"
	}
	return "monitor " + monitor
}

func hyprlandSignedAmount(value string) (sign int, magnitude string, ok bool) {
	magnitude = strings.TrimPrefix(strings.TrimPrefix(value, "+"), "-")
	number := strings.TrimSuffix(magnitude, "%")
	f, err := strconv.ParseFloat(number, 64)
	if err != nil {
		return 0, "", false
	}
	switch {
	case f == 0:
		return 0, magnitude, true
	case strings.HasPrefix(value, "-"):
		return -1, magnitude, true
	default:
		return 1, magnitude, true
	}
}

func describeHyprlandResize(params string) string {
	x, y, relative, ok := xyParams(params)
	if !ok {
		return "Resize window by " + params
	}
	if !relative {
		return "Resize window to " + x + "x" + y
	}
	sx, mx, okX := hyprlandSignedAmount(x)
	sy, my, okY := hyprlandSignedAmount(y)
	if !okX || !okY || (sx == 0 && sy == 0) {
		return "Resize window by " + x + " " + y
	}
	verb := func(sign int) string {
		if sign < 0 {
			return "shrink"
		}
		return "grow"
	}
	var parts []string
	if sx != 0 {
		parts = append(parts, verb(sx)+" window width by "+mx)
	}
	if sy != 0 {
		noun := " window height by "
		if sx != 0 {
			noun = " height by "
		}
		parts = append(parts, verb(sy)+noun+my)
	}
	desc := strings.Join(parts, ", ")
	return strings.ToUpper(desc[:1]) + desc[1:]
}

func describeHyprlandMove(params string) string {
	x, y, relative, ok := xyParams(params)
	if !ok {
		return "Move window by " + params
	}
	if !relative {
		return "Move window to " + x + " " + y
	}
	sx, mx, okX := hyprlandSignedAmount(x)
	sy, my, okY := hyprlandSignedAmount(y)
	if !okX || !okY || (sx == 0 && sy == 0) {
		return "Move window by " + x + " " + y
	}
	var parts []string
	switch sx {
	case -1:
		parts = append(parts, "left by "+mx)
	case 1:
		parts = append(parts, "right by "+mx)
	}
	switch sy {
	case -1:
		parts = append(parts, "up by "+my)
	case 1:
		parts = append(parts, "down by "+my)
	}
	return "Move window " + strings.Join(parts, ", ")
}

type HyprlandParseResult struct {
	Section            *HyprlandSection
	DMSBindsIncluded   bool
	DMSStatus          *configfrag.Status
	ConflictingConfigs map[string]*HyprlandKeyBinding
	DefaultDMSKeys     map[string]bool // keys with a DMS default in binds.lua
	MainMod            string          // value of the mainMod Lua variable when the config defines one
}

var hyprlandBindsMessages = configfrag.Messages{
	Missing:     "dms/binds.lua does not exist",
	NotIncluded: "dms binds are not loaded from Hyprland config (require)",
	Overridden:  "Some DMS binds may be overridden by config binds",
	Active:      "DMS binds are active",
}

func (p *HyprlandParser) buildDMSStatus() *configfrag.Status {
	status := configfrag.BuildStatus(p.walker.Scan(), p.dmsBindsExists, p.bindsAfterDMS, hyprlandBindsMessages)
	return &status
}

func (p *HyprlandParser) formatBindKey(kb *HyprlandKeyBinding) string {
	key := kb.Key
	if canonical, ok := hyprlandScrollToCanonical(key); ok {
		key = canonical
	}
	parts := make([]string, 0, len(kb.Mods)+1)
	parts = append(parts, kb.Mods...)
	parts = append(parts, key)
	return strings.Join(parts, "+")
}

func (p *HyprlandParser) normalizeKey(key string) string {
	return strings.ToLower(key)
}

func (p *HyprlandParser) addBind(kb *HyprlandKeyBinding) bool {
	key := p.formatBindKey(kb)
	normalizedKey := p.normalizeKey(key)
	isDMSBind := isDMSBindsSourcePath(kb.Source)

	if isDMSBindsPrimarySourcePath(kb.Source) {
		p.defaultDMSKeys[normalizedKey] = true
	}
	if isDMSBind {
		p.dmsBindKeys[normalizedKey] = true
	} else if p.dmsBindKeys[normalizedKey] && !p.fileUnbinds[normalizedKey] {
		// Without a preceding hl.unbind both binds stay live in Hyprland, which
		// is the conflict this counts. With one, the DMS bind is gone and this
		// is the effective bind, so it belongs in the list (#3145).
		p.bindsAfterDMS++
		p.conflictingConfigs[normalizedKey] = kb
		p.configBindKeys[normalizedKey] = true
		return false
	} else {
		p.configBindKeys[normalizedKey] = true
	}

	if _, exists := p.bindMap[normalizedKey]; !exists {
		p.bindOrder = append(p.bindOrder, key)
	}
	p.bindMap[normalizedKey] = kb
	return true
}

func (p *HyprlandParser) ParseWithDMS() (*HyprlandSection, error) {
	expandedDir, err := utils.ExpandPath(p.configDir)
	if err != nil {
		return nil, err
	}

	dmsBindsPath := filepath.Join(expandedDir, "dms", "binds.lua")
	if _, err := os.Stat(dmsBindsPath); err == nil {
		p.dmsBindsExists = true
	}

	mainConfig, err := hyprlandMainConfigPath(p.configDir)
	if err != nil {
		return nil, err
	}
	section, err := p.parseFileWithSource(mainConfig, "")
	if err != nil {
		return nil, err
	}

	if p.dmsBindsExists && !p.dmsProcessed {
		p.parseDMSBindsDirectly(dmsBindsPath, section)
	}
	p.removeShadowedDMSBinds(section)
	p.removeUnboundDMSBinds(section)

	return section, nil
}

func (p *HyprlandParser) removeUnboundDMSBinds(section *HyprlandSection) {
	if len(p.removedKeys) == 0 {
		return
	}
	filtered := section.Keybinds[:0]
	for i := range section.Keybinds {
		kb := section.Keybinds[i]
		key := p.normalizeKey(p.formatBindKey(&kb))
		if isDMSBindsSourcePath(kb.Source) && p.removedKeys[key] && !p.rebindSources[key][kb.Source] {
			continue
		}
		filtered = append(filtered, kb)
	}
	section.Keybinds = filtered
	for i := range section.Children {
		p.removeUnboundDMSBinds(&section.Children[i])
	}
}

func (p *HyprlandParser) removeShadowedDMSBinds(section *HyprlandSection) {
	counts := make(map[string]int)
	p.countDMSBinds(section, counts)
	p.filterShadowedDMSBinds(section, counts)
}

func (p *HyprlandParser) countDMSBinds(section *HyprlandSection, counts map[string]int) {
	for i := range section.Keybinds {
		kb := &section.Keybinds[i]
		if isDMSBindsSourcePath(kb.Source) {
			counts[p.normalizeKey(p.formatBindKey(kb))]++
		}
	}
	for i := range section.Children {
		p.countDMSBinds(&section.Children[i], counts)
	}
}

func (p *HyprlandParser) filterShadowedDMSBinds(section *HyprlandSection, counts map[string]int) {
	filtered := section.Keybinds[:0]
	for i := range section.Keybinds {
		kb := section.Keybinds[i]
		key := p.normalizeKey(p.formatBindKey(&kb))
		if isDMSBindsSourcePath(kb.Source) && counts[key] > 1 {
			counts[key]--
			continue
		}
		filtered = append(filtered, kb)
	}
	section.Keybinds = filtered
	for i := range section.Children {
		p.filterShadowedDMSBinds(&section.Children[i], counts)
	}
}

func (p *HyprlandParser) parseFileWithSource(filePath, sectionName string) (*HyprlandSection, error) {
	absPath, err := filepath.Abs(filePath)
	if err != nil {
		return nil, err
	}

	if p.processedFiles[absPath] {
		return &HyprlandSection{Name: sectionName}, nil
	}
	p.processedFiles[absPath] = true

	data, err := os.ReadFile(absPath)
	if err != nil {
		return nil, err
	}

	return p.parseLuaLines(string(data), filepath.Dir(absPath), absPath, sectionName)
}

func (p *HyprlandParser) parseDMSBindsDirectly(dmsBindsPath string, section *HyprlandSection) {
	sub, err := p.parseLuaLinesFromPath(dmsBindsPath)
	if err != nil {
		return
	}
	section.Keybinds = append(section.Keybinds, sub.Keybinds...)
	section.Children = append(section.Children, sub.Children...)
	p.dmsProcessed = true
}

func (p *HyprlandParser) parseLuaLinesFromPath(absPath string) (*HyprlandSection, error) {
	data, err := os.ReadFile(absPath)
	if err != nil {
		return nil, err
	}
	return p.parseLuaLines(string(data), filepath.Dir(absPath), absPath, "")
}

// parseLuaLines reads a Hyprland Lua config fragment: require() includes and hl.bind keybinds.
func (p *HyprlandParser) parseLuaLines(content string, baseDir, absPath, sectionName string) (*HyprlandSection, error) {
	section := &HyprlandSection{Name: sectionName}
	prevSource := p.currentSource
	prevUnbinds := p.fileUnbinds
	p.currentSource = absPath
	p.fileUnbinds = make(map[string]bool)

	lines, env := expandLuaConfigLinesEnv(strings.Split(content, "\n"))
	if p.mainMod == "" {
		p.mainMod = env["mainMod"]
	}
	boundInFile := make(map[string]bool)
	for _, line := range lines {
		trimmed := strings.TrimSpace(line)
		if trimmed == "" || strings.HasPrefix(trimmed, "--") || !strings.Contains(trimmed, "hl.bind") {
			continue
		}
		if kbc, _, _, ok := parseLuaBindInvocation(trimmed); ok {
			boundInFile[strings.ToLower(luaKeyComboToInternalKey(kbc))] = true
		}
	}
	rootDir := baseDir
	if expanded, err := utils.ExpandPath(p.configDir); err == nil && expanded != "" {
		rootDir = expanded
	}
	for _, line := range lines {
		trimmed := strings.TrimSpace(line)
		if trimmed == "" || strings.HasPrefix(trimmed, "--") {
			continue
		}

		if modules := luaconfig.Requires(trimmed); len(modules) > 0 {
			for _, mod := range modules {
				rel := luaconfig.ModuleToRelPath(mod)
				if rel == "" {
					continue
				}
				if p.walker.Record(rel) {
					p.dmsProcessed = true
				}
				fullPath := luaconfig.ModuleToPath(rootDir, mod)
				expanded, err := utils.ExpandPath(fullPath)
				if err != nil {
					continue
				}
				includedSection, err := p.parseFileWithSource(expanded, "")
				if err != nil {
					continue
				}
				section.Children = append(section.Children, *includedSection)
			}
			continue
		}

		if strings.HasPrefix(trimmed, "hl.unbind") {
			if key, ok := parseLuaUnbindLine(trimmed); ok {
				normalized := strings.ToLower(key)
				p.removedKeys[normalized] = true
				p.fileUnbinds[normalized] = true
				if boundInFile[normalized] {
					// unbind plus rebind in one file is an override, not a
					// removal: this file's own bind has to survive
					p.noteRebindSource(normalized, absPath)
				}
			}
			continue
		}

		if !strings.Contains(trimmed, "hl.bind") {
			continue
		}

		kbc, action, optSuffix, ok := parseLuaBindInvocation(trimmed)
		if !ok {
			continue
		}
		flags := luaBindOptFlags(optSuffix)
		desc := luaBindOptDescription(optSuffix)
		if desc == "" {
			desc = luaLineTrailingComment(line)
		}
		kb := luaKeyComboToBinding(kbc, action, p.currentSource, desc)
		kb.Flags = flags
		kb.Device = luaBindOptDevice(optSuffix)
		if p.addBind(kb) {
			section.Keybinds = append(section.Keybinds, *kb)
		}
	}

	p.currentSource = prevSource
	p.fileUnbinds = prevUnbinds
	return section, nil
}

func (p *HyprlandParser) noteRebindSource(key, source string) {
	if p.rebindSources[key] == nil {
		p.rebindSources[key] = make(map[string]bool)
	}
	p.rebindSources[key][source] = true
}

// mouse and auto_consuming work in Hyprland but are missing from hl.meta.lua; separate (s) has no Lua option.
var hyprlandBindFlagOptions = []struct {
	flag   byte
	option string
}{
	{'l', "locked"},
	{'e', "repeating"},
	{'r', "release"},
	{'n', "non_consuming"},
	{'m', "mouse"},
	{'t', "transparent"},
	{'i', "ignore_mods"},
	{'o', "long_press"},
	{'u', "submap_universal"},
	{'a', "auto_consuming"},
	{'x', "allow_input_capture"},
	{'p', "dont_inhibit"},
	{'c', "click"},
	{'g', "drag"},
}

func luaBindOptFlags(optSuffix string) string {
	optSuffix = strings.TrimSpace(optSuffix)
	if optSuffix == "" {
		return ""
	}
	var flags []byte
	for _, fo := range hyprlandBindFlagOptions {
		if strings.Contains(optSuffix, fo.option) && luaTableBoolFieldValue(optSuffix, fo.option) {
			flags = append(flags, fo.flag)
		}
	}
	if luaBindOptDevice(optSuffix) != "" {
		flags = append(flags, 'k')
	}
	if luaBindOptDescription(optSuffix) != "" {
		flags = append(flags, 'd')
	}
	return string(flags)
}

// Returned raw so per-device binds survive a rewrite.
func luaBindOptDevice(optSuffix string) string {
	loc := luaDeviceOptPattern.FindStringIndex(optSuffix)
	if loc == nil {
		return ""
	}
	start := loc[1] - 1
	depth := 0
	var quote byte
	for i := start; i < len(optSuffix); i++ {
		c := optSuffix[i]
		switch {
		case quote != 0:
			switch c {
			case '\\':
				i++
			case quote:
				quote = 0
			}
		case c == '"' || c == '\'':
			quote = c
		case c == '{':
			depth++
		case c == '}':
			depth--
			if depth == 0 {
				return optSuffix[start : i+1]
			}
		}
	}
	return ""
}

var luaDeviceOptPattern = regexp.MustCompile(`\bdevice\s*=\s*\{`)

func luaBindOptDescription(optSuffix string) string {
	return luaTableStringField(optSuffix, "description")
}

func ParseHyprlandKeysWithDMS(path string) (*HyprlandParseResult, error) {
	parser := NewHyprlandParser(path)
	section, err := parser.ParseWithDMS()
	if err != nil {
		return nil, err
	}

	return &HyprlandParseResult{
		Section:            section,
		DMSBindsIncluded:   parser.walker.Included(),
		DMSStatus:          parser.buildDMSStatus(),
		ConflictingConfigs: parser.conflictingConfigs,
		DefaultDMSKeys:     parser.defaultDMSKeys,
		MainMod:            parser.mainMod,
	}, nil
}

func skipLuaWS(s string, i int) int {
	for i < len(s) && (s[i] == ' ' || s[i] == '\t' || s[i] == '\r') {
		i++
	}
	return i
}

// parseLuaStringLiteral reads a Lua "..." or '...' starting at i (first quote).
func parseLuaStringLiteral(line string, i int) (value string, next int, ok bool) {
	if i >= len(line) {
		return "", i, false
	}
	q := line[i]
	if q != '"' && q != '\'' {
		return "", i, false
	}
	i++
	var sb strings.Builder
	for i < len(line) {
		c := line[i]
		if c == '\\' && i+1 < len(line) {
			i++
			sb.WriteByte(line[i])
			i++
			continue
		}
		if c == q {
			return sb.String(), i + 1, true
		}
		sb.WriteByte(c)
		i++
	}
	return "", i, false
}

// parseLuaFirstArgExpr parses a single Lua expression starting at i, stopping at
// the next top-level comma. It handles nested calls/tables and inline functions.
func parseLuaFirstArgExpr(line string, start int) (expr string, next int, ok bool) {
	start = skipLuaWS(line, start)
	if start >= len(line) {
		return "", start, false
	}
	i := start
	parenDepth := 0
	braceDepth := 0
	bracketDepth := 0
	functionDepth := 0
	inStr := byte(0)
	esc := false
	for ; i < len(line); i++ {
		c := line[i]
		if inStr != 0 {
			if esc {
				esc = false
				continue
			}
			if c == '\\' && inStr == '"' {
				esc = true
				continue
			}
			if c == inStr {
				inStr = 0
			}
			continue
		}
		if c == '[' && i+1 < len(line) && line[i+1] == '[' {
			if end := strings.Index(line[i+2:], "]]"); end >= 0 {
				i += end + 3
				continue
			}
			return "", start, false
		}
		if luaWordAt(line, i, "function") {
			functionDepth++
			i += len("function") - 1
			continue
		}
		if luaWordAt(line, i, "end") && functionDepth > 0 {
			functionDepth--
			i += len("end") - 1
			continue
		}
		switch c {
		case '"', '\'':
			inStr = c
		case '(':
			parenDepth++
		case ')':
			if parenDepth == 0 && braceDepth == 0 && bracketDepth == 0 && functionDepth == 0 {
				// the enclosing call's close paren, e.g. the end of hl.bind(...)
				return strings.TrimSpace(line[start:i]), i, true
			}
			if parenDepth > 0 {
				parenDepth--
			}
		case '{':
			braceDepth++
		case '}':
			if braceDepth > 0 {
				braceDepth--
			}
		case '[':
			bracketDepth++
		case ']':
			if bracketDepth > 0 {
				bracketDepth--
			}
		case ',':
			if parenDepth == 0 && braceDepth == 0 && bracketDepth == 0 && functionDepth == 0 {
				return strings.TrimSpace(line[start:i]), i, true
			}
		}
	}
	expr = strings.TrimSpace(line[start:i])
	return expr, i, expr != ""
}

func luaWordAt(line string, idx int, word string) bool {
	if idx < 0 || idx+len(word) > len(line) || line[idx:idx+len(word)] != word {
		return false
	}
	before := idx == 0 || !isLuaIdentByte(line[idx-1])
	afterIdx := idx + len(word)
	after := afterIdx >= len(line) || !isLuaIdentByte(line[afterIdx])
	return before && after
}

func isLuaIdentByte(c byte) bool {
	return c == '_' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
}

// parseLuaBindInvocation parses one hl.bind("KEY", expr [, opts]) on a single line.
func parseLuaBindInvocation(line string) (keyCombo, actionExpr, optSuffix string, ok bool) {
	idx := strings.Index(line, "hl.bind")
	if idx < 0 {
		return "", "", "", false
	}
	i := idx + len("hl.bind")
	i = skipLuaWS(line, i)
	if i >= len(line) || line[i] != '(' {
		return "", "", "", false
	}
	i++
	i = skipLuaWS(line, i)
	keyCombo, i, ok = parseLuaStringLiteral(line, i)
	if !ok {
		return "", "", "", false
	}
	i = skipLuaWS(line, i)
	if i >= len(line) || line[i] != ',' {
		return "", "", "", false
	}
	i++
	i = skipLuaWS(line, i)
	actionExpr, i, ok = parseLuaFirstArgExpr(line, i)
	if !ok {
		return "", "", "", false
	}
	i = skipLuaWS(line, i)
	if i < len(line) && line[i] == ',' {
		optSuffix = strings.TrimSpace(line[i:])
	}
	return keyCombo, strings.TrimSpace(actionExpr), optSuffix, true
}

func luaKeyComboToBinding(keyCombo, actionExpr, source, lineComment string) *HyprlandKeyBinding {
	keyCombo = strings.TrimSpace(keyCombo)
	mods, leaf := luaKeyComboToModsKey(keyCombo)
	dispatcher, params := luaExprToDispatcherParams(actionExpr)
	comment := lineComment
	if comment == "" {
		comment = hyprlandAutogenerateComment(dispatcher, params)
	}
	return &HyprlandKeyBinding{
		Mods:       mods,
		Key:        leaf,
		Dispatcher: dispatcher,
		Params:     params,
		Comment:    comment,
		Source:     source,
		Flags:      "",
	}
}

func luaKeyComboToModsKey(combo string) (mods []string, leaf string) {
	parts := strings.Split(combo, "+")
	for i := range parts {
		parts[i] = strings.TrimSpace(parts[i])
	}
	switch len(parts) {
	case 0:
		return nil, ""
	case 1:
		return nil, parts[0]
	default:
		return parts[:len(parts)-1], parts[len(parts)-1]
	}
}

func luaExprToDispatcherParams(expr string) (dispatcher, params string) {
	expr = strings.TrimSpace(expr)
	switch {
	case strings.HasPrefix(expr, "hl.dsp.exec_cmd("):
		arg := extractLuaCallStringArg(expr, "hl.dsp.exec_cmd")
		if arg != "" {
			if u, err := strconv.Unquote(arg); err == nil {
				if after, ok := strings.CutPrefix(u, "hyprctl dispatch "); ok {
					return splitDispatchCommand(strings.TrimSpace(after))
				}
				if strings.TrimSpace(u) == "hyprctl reload" {
					return "reloadconfig", ""
				}
				return "exec", u
			}
		}
		// A variable argument (exec_cmd(terminal)) can't be resolved here.
		return expr, ""
	case strings.HasPrefix(expr, "hl.dsp.exec_raw("):
		return "execr", luaCallStringArgValue(expr, "hl.dsp.exec_raw")
	case strings.HasPrefix(expr, "hl.dispatch("):
		if arg := luaCallStringArgValue(expr, "hl.dispatch"); arg != "" {
			return splitDispatchCommand(arg)
		}
		return "", ""
	case strings.Contains(expr, "hl.exec_cmd("):
		if arg := luaEmbeddedCallStringArgValue(expr, "hl.exec_cmd"); strings.HasPrefix(arg, "hyprctl dispatch ") {
			return splitDispatchCommand(strings.TrimSpace(strings.TrimPrefix(arg, "hyprctl dispatch ")))
		}
	case strings.HasPrefix(expr, "hl.dsp.window.close("):
		if window := luaTableStringField(expr, "window"); window != "" {
			return "closewindow", window
		}
		if arg := luaCallStringArgValue(expr, "hl.dsp.window.close"); arg != "" {
			return "closewindow", arg
		}
		return "killactive", ""
	case strings.HasPrefix(expr, "hl.dsp.window.kill("):
		if window := luaTableStringField(expr, "window"); window != "" {
			return "killwindow", window
		}
		if arg := luaCallStringArgValue(expr, "hl.dsp.window.kill"); arg != "" {
			return "killwindow", arg
		}
		return "forcekillactive", ""
	case strings.HasPrefix(expr, "hl.dsp.window.fullscreen("):
		mode := luaTableStringField(expr, "mode")
		switch mode {
		case "maximized", "maximize":
			mode = "1"
		case "fullscreen":
			mode = "0"
		}
		switch action := luaTableStringField(expr, "action"); action {
		case "set", "unset":
			if mode == "" {
				mode = "0"
			}
			return "fullscreen", mode + " " + action
		}
		return "fullscreen", mode
	case strings.HasPrefix(expr, "hl.dsp.window.fullscreen_state("):
		internal := luaStringValue(luaTableScalarField(expr, "internal"))
		client := luaStringValue(luaTableScalarField(expr, "client"))
		return joinDispatcherParams("fullscreenstate", internal, client)
	case strings.HasPrefix(expr, "hl.dsp.window.float("):
		switch luaToggleActionToLegacy(luaTableStringField(expr, "action")) {
		case "on":
			return "setfloating", ""
		case "off":
			return "settiled", ""
		default:
			return "togglefloating", ""
		}
	case strings.HasPrefix(expr, "hl.dsp.window.pseudo("):
		action := luaToggleActionToLegacy(luaTableStringField(expr, "action"))
		if action == "" || action == "toggle" {
			return "pseudo", ""
		}
		return "pseudo", action
	case strings.HasPrefix(expr, "hl.dsp.window.pin("):
		if action := luaToggleActionToLegacy(luaTableStringField(expr, "action")); action != "" && action != "toggle" {
			return "pin", action
		}
		return "pin", ""
	case strings.Contains(expr, "hl.dsp.window.center()"):
		return "centerwindow", ""
	case strings.Contains(expr, "hl.dsp.window.bring_to_top()"):
		return "bringactivetotop", ""
	case strings.Contains(expr, "hl.dsp.window.toggle_swallow()"):
		return "toggleswallow", ""
	case strings.Contains(expr, "hl.dsp.group.toggle()"):
		return "togglegroup", ""
	case strings.Contains(expr, "hl.dsp.group.next()"):
		return "changegroupactive", "f"
	case strings.Contains(expr, "hl.dsp.group.prev()"):
		return "changegroupactive", "b"
	case strings.HasPrefix(expr, "hl.dsp.group.active("):
		return "changegroupactive", luaStringValue(luaTableScalarField(expr, "index"))
	case strings.HasPrefix(expr, "hl.dsp.group.move_window("):
		if forward, ok := luaTableBoolField(expr, "forward"); ok && !forward {
			return "movegroupwindow", "b"
		}
		return "movegroupwindow", "f"
	case strings.HasPrefix(expr, "hl.dsp.group.lock_active("):
		return "lockactivegroup", luaToggleActionToLockArg(luaTableStringField(expr, "action"))
	case strings.HasPrefix(expr, "hl.dsp.group.lock("):
		lockArg := luaToggleActionToLockArg(luaTableStringField(expr, "action"))
		window := luaTableStringField(expr, "window")
		// Before 0.57 group.lock locked every group and ignored all; 0.57 locks only the active one without it
		if all, _ := luaTableBoolField(expr, "all"); window == "" && (all || !luaconfig.HyprlandAtLeast(0, 57)) {
			return "lockgroups", lockArg
		}
		return joinDispatcherParams("lockactivegroup", lockArg, window)
	case strings.HasPrefix(expr, "hl.dsp.window.deny_from_group("):
		return "denywindowfromgroup", luaToggleActionToLegacy(luaTableStringField(expr, "action"))
	case strings.HasPrefix(expr, "hl.dsp.focus("):
		switch {
		case luaTableStringField(expr, "direction") != "":
			return "movefocus", luaTableStringField(expr, "direction")
		case luaTableStringField(expr, "monitor") != "":
			return "focusmonitor", luaTableStringField(expr, "monitor")
		case luaTableStringField(expr, "workspace") != "":
			if luaTableBoolFieldValue(expr, "on_current_monitor") {
				return "focusworkspaceoncurrentmonitor", luaTableStringField(expr, "workspace")
			}
			return "workspace", luaTableStringField(expr, "workspace")
		case luaTableStringField(expr, "window") != "":
			return "focuswindow", luaTableStringField(expr, "window")
		case luaTableBoolFieldValue(expr, "urgent_or_last"):
			return "focusurgentorlast", ""
		case luaTableBoolFieldValue(expr, "last"):
			return "focuscurrentorlast", ""
		}
	case strings.HasPrefix(expr, "hl.dsp.window.move("):
		switch {
		case luaTableScalarField(expr, "x") != "" || luaTableScalarField(expr, "y") != "":
			x := luaStringValue(luaTableScalarField(expr, "x"))
			y := luaStringValue(luaTableScalarField(expr, "y"))
			if x == "" {
				x = "0"
			}
			if y == "" {
				y = "0"
			}
			prefix := ""
			if raw, ok := luaTableBoolField(expr, "relative"); ok && !raw {
				prefix = "exact "
			}
			params := prefix + x + " " + y
			if window := luaTableStringField(expr, "window"); window != "" {
				return "movewindowpixel", params + "," + window
			}
			return "moveactive", params
		case luaTableStringField(expr, "into_group") != "":
			return "moveintogroup", luaTableStringField(expr, "into_group")
		case luaTableStringField(expr, "into_or_create_group") != "":
			return "moveintoorcreategroup", luaTableStringField(expr, "into_or_create_group")
		case luaTableBoolFieldValue(expr, "out_of_group"):
			return "moveoutofgroup", ""
		case luaTableStringField(expr, "out_of_group") != "":
			return "moveoutofgroup", luaTableStringField(expr, "out_of_group")
		case luaTableStringField(expr, "direction") != "":
			if luaTableBoolFieldValue(expr, "group_aware") {
				return "movewindoworgroup", luaTableStringField(expr, "direction")
			}
			return "movewindow", luaTableStringField(expr, "direction")
		case luaTableStringField(expr, "monitor") != "":
			return "movewindow", "mon:" + luaTableStringField(expr, "monitor")
		case luaTableStringField(expr, "workspace") != "":
			action := "movetoworkspace"
			if follow, ok := luaTableBoolField(expr, "follow"); ok && !follow {
				action = "movetoworkspacesilent"
			}
			return joinDispatcherParams(action, luaTableStringField(expr, "workspace"), luaTableStringField(expr, "window"))
		}
	case expr == "hl.dsp.window.drag()":
		return "movewindow", ""
	case expr == "hl.dsp.window.resize()":
		return "resizewindow", ""
	case strings.HasPrefix(expr, "hl.dsp.window.resize("):
		x := luaStringValue(luaTableScalarField(expr, "x"))
		y := luaStringValue(luaTableScalarField(expr, "y"))
		if x != "" || y != "" {
			if x == "" {
				x = "0"
			}
			if y == "" {
				y = "0"
			}
			prefix := ""
			if relative, ok := luaTableBoolField(expr, "relative"); ok && !relative {
				prefix = "exact "
			}
			params := prefix + x + " " + y
			if window := luaTableStringField(expr, "window"); window != "" {
				return "resizewindowpixel", params + "," + window
			}
			return "resizeactive", params
		}
	case strings.HasPrefix(expr, "hl.dsp.window.swap("):
		switch {
		case luaTableBoolFieldValue(expr, "next"):
			return "swapnext", ""
		case luaTableBoolFieldValue(expr, "prev"):
			return "swapnext", "prev"
		}
		return "swapwindow", luaTableStringField(expr, "direction")
	case strings.HasPrefix(expr, "hl.dsp.window.cycle_next("):
		parts := []string{}
		if next, ok := luaTableBoolField(expr, "next"); ok && !next {
			parts = append(parts, "prev")
		}
		if luaTableBoolFieldValue(expr, "tiled") {
			parts = append(parts, "tiled")
		}
		if luaTableBoolFieldValue(expr, "floating") {
			parts = append(parts, "floating")
		}
		return "cyclenext", strings.Join(parts, " ")
	case strings.HasPrefix(expr, "hl.dsp.window.signal("):
		signal := luaStringValue(luaTableScalarField(expr, "signal"))
		window := luaTableStringField(expr, "window")
		if window != "" {
			return joinDispatcherParams("signalwindow", window, signal)
		}
		return "signal", signal
	case strings.HasPrefix(expr, "hl.dsp.window.tag("):
		return joinDispatcherParams("tagwindow", luaTableStringField(expr, "tag"), luaTableStringField(expr, "window"))
	case strings.HasPrefix(expr, "hl.dsp.window.alter_zorder("):
		mode := luaTableStringField(expr, "mode")
		if mode == "" {
			mode = luaTableStringField(expr, "zheight")
		}
		return joinDispatcherParams("alterzorder", mode, luaTableStringField(expr, "window"))
	case strings.HasPrefix(expr, "hl.dsp.window.set_prop("):
		prop := luaTableStringField(expr, "prop")
		if prop == "" {
			prop = luaTableStringField(expr, "property")
		}
		return joinDispatcherParams("setprop", luaTableStringField(expr, "window"), prop, luaTableStringField(expr, "value"))
	case strings.HasPrefix(expr, "hl.dsp.workspace.rename("):
		return joinDispatcherParams("renameworkspace", luaTableStringField(expr, "workspace"), luaTableStringField(expr, "name"))
	case strings.HasPrefix(expr, "hl.dsp.workspace.move("):
		workspace := luaTableStringField(expr, "workspace")
		monitor := luaTableStringField(expr, "monitor")
		if workspace != "" {
			return joinDispatcherParams("moveworkspacetomonitor", workspace, monitor)
		}
		return "movecurrentworkspacetomonitor", monitor
	case strings.HasPrefix(expr, "hl.dsp.workspace.swap_monitors("):
		return joinDispatcherParams("swapactiveworkspaces", luaTableStringField(expr, "monitor1"), luaTableStringField(expr, "monitor2"))
	case strings.HasPrefix(expr, "hl.dsp.workspace.toggle_special("):
		return "togglespecialworkspace", luaCallStringArgValue(expr, "hl.dsp.workspace.toggle_special")
	case strings.HasPrefix(expr, "hl.dsp.layout("):
		if arg := luaCallStringArgValue(expr, "hl.dsp.layout"); arg != "" {
			return "layoutmsg", arg
		}
	case strings.HasPrefix(expr, "hl.dsp.dpms("):
		action := luaTableStringField(expr, "action")
		switch action {
		case "enable":
			action = "on"
		case "disable":
			action = "off"
		}
		monitor := luaTableStringField(expr, "monitor")
		if action == "" && monitor != "" {
			action = "toggle"
		}
		return joinDispatcherParams("dpms", action, monitor)
	case strings.HasPrefix(expr, "hl.dsp.submap("):
		return "submap", luaCallStringArgValue(expr, "hl.dsp.submap")
	case strings.HasPrefix(expr, "hl.dsp.global("):
		return "global", luaCallStringArgValue(expr, "hl.dsp.global")
	case strings.HasPrefix(expr, "hl.dsp.event("):
		return "event", luaCallStringArgValue(expr, "hl.dsp.event")
	case strings.HasPrefix(expr, "hl.dsp.pass("):
		if window := luaTableStringField(expr, "window"); window != "" {
			return "pass", window
		}
		return "pass", luaCallStringArgValue(expr, "hl.dsp.pass")
	case strings.HasPrefix(expr, "hl.dsp.send_shortcut("):
		return joinDispatcherParams("sendshortcut", luaTableModsField(expr), luaTableStringField(expr, "key"), luaTableStringField(expr, "window"))
	case strings.HasPrefix(expr, "hl.dsp.send_key_state("):
		return joinDispatcherParams("sendkeystate", luaTableModsField(expr), luaTableStringField(expr, "key"), luaTableStringField(expr, "state"), luaTableStringField(expr, "window"))
	case strings.HasPrefix(expr, "hl.dsp.cursor.move_to_corner("):
		return "movecursortocorner", luaStringValue(luaTableScalarField(expr, "corner"))
	case strings.HasPrefix(expr, "hl.dsp.cursor.move("):
		return joinDispatcherParams("movecursor", luaStringValue(luaTableScalarField(expr, "x")), luaStringValue(luaTableScalarField(expr, "y")))
	case expr == "hl.dsp.release_input_capture()":
		return "releaseinputcapture", ""
	case strings.Contains(expr, "hl.dsp.force_renderer_reload()"):
		return "forcerendererreload", ""
	case strings.Contains(expr, "hl.dsp.reload_config()"):
		return "reloadconfig", ""
	case strings.HasPrefix(expr, "hl.dsp.force_idle("):
		return "forceidle", luaCallScalarArgValue(expr, "hl.dsp.force_idle")
	case strings.Contains(expr, "hl.dsp.exit()"):
		return "exit", ""
	default:
		return expr, ""
	}
	return expr, ""
}

func splitDispatchCommand(command string) (dispatcher, params string) {
	command = strings.TrimSpace(command)
	if command == "" {
		return "", ""
	}
	parts := strings.SplitN(command, " ", 2)
	if len(parts) == 1 {
		return parts[0], ""
	}
	return parts[0], strings.TrimSpace(parts[1])
}

func joinDispatcherParams(dispatcher string, values ...string) (string, string) {
	parts := make([]string, 0, len(values))
	for _, value := range values {
		value = strings.TrimSpace(value)
		if value != "" {
			parts = append(parts, value)
		}
	}
	return dispatcher, strings.Join(parts, " ")
}

func luaEmbeddedCallStringArgValue(expr, funcName string) string {
	idx := strings.Index(expr, funcName+"(")
	if idx < 0 {
		return ""
	}
	return luaCallStringArgValue(expr[idx:], funcName)
}

func luaCallScalarArgValue(callExpr, funcName string) string {
	callExpr = strings.TrimSpace(callExpr)
	prefix := funcName + "("
	if !strings.HasPrefix(callExpr, prefix) {
		return ""
	}
	inner := strings.TrimSpace(callExpr[len(prefix):])
	if inner == "" {
		return ""
	}
	if s := luaCallStringArgValue(callExpr, funcName); s != "" {
		return s
	}
	re := regexp.MustCompile(`^-?\d+(?:\.\d+)?`)
	return re.FindString(inner)
}

func luaToggleActionToLegacy(action string) string {
	switch strings.ToLower(strings.TrimSpace(action)) {
	case "on", "enable", "enabled", "set", "lock":
		return "on"
	case "off", "disable", "disabled", "unset", "unlock":
		return "off"
	default:
		return "toggle"
	}
}

func luaToggleActionToLockArg(action string) string {
	switch luaToggleActionToLegacy(action) {
	case "on":
		return "lock"
	case "off":
		return "unlock"
	default:
		return "toggle"
	}
}

func extractLuaCallStringArg(callExpr, funcName string) string {
	callExpr = strings.TrimSpace(callExpr)
	prefix := funcName + "("
	if !strings.HasPrefix(callExpr, prefix) {
		return ""
	}
	inner := callExpr[len(prefix):]
	inner = strings.TrimSpace(inner)
	if len(inner) == 0 {
		return ""
	}
	switch inner[0] {
	case '"', '\'':
		s, _, ok := parseLuaStringLiteral(inner, 0)
		if ok {
			return strconv.Quote(s)
		}
	case '[':
		if strings.HasPrefix(inner, "[[") {
			if end := strings.Index(inner[2:], "]]"); end >= 0 {
				return strconv.Quote(inner[2 : 2+end])
			}
		}
	}
	return ""
}

func luaCallStringArgValue(callExpr, funcName string) string {
	arg := extractLuaCallStringArg(callExpr, funcName)
	if arg == "" {
		return ""
	}
	u, err := strconv.Unquote(arg)
	if err != nil {
		return ""
	}
	return u
}

func luaTableStringField(expr, field string) string {
	return luaStringValue(luaTableScalarField(expr, field))
}

func luaTableModsField(expr string) string {
	if mods := luaTableStringField(expr, "mods"); mods != "" {
		return mods
	}
	return luaTableStringField(expr, "mod")
}

func luaTableBoolFieldValue(expr, field string) bool {
	value, ok := luaTableBoolField(expr, field)
	return ok && value
}

func luaTableBoolField(expr, field string) (bool, bool) {
	raw := strings.ToLower(luaTableScalarField(expr, field))
	switch raw {
	case "true":
		return true, true
	case "false":
		return false, true
	default:
		return false, false
	}
}

func luaTableScalarField(expr, field string) string {
	re := regexp.MustCompile(`(?s)\b` + regexp.QuoteMeta(field) + `\s*=\s*("(?:\\.|[^"])*"|'(?:\\.|[^'])*'|\[\[.*?\]\]|-?\d+(?:\.\d+)?|true|false)`)
	m := re.FindStringSubmatch(expr)
	if len(m) < 2 {
		return ""
	}
	return strings.TrimSpace(m[1])
}

func luaStringValue(raw string) string {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return ""
	}
	if strings.HasPrefix(raw, "[[") && strings.HasSuffix(raw, "]]") {
		return raw[2 : len(raw)-2]
	}
	if len(raw) >= 2 {
		q := raw[0]
		if (q == '"' || q == '\'') && raw[len(raw)-1] == q {
			if q == '"' {
				if u, err := strconv.Unquote(raw); err == nil {
					return u
				}
			}
			return strings.ReplaceAll(raw[1:len(raw)-1], `\'`, `'`)
		}
	}
	return raw
}

func luaLineTrailingComment(line string) string {
	inString := byte(0)
	escaped := false
	for i := 0; i < len(line)-1; i++ {
		c := line[i]
		if inString != 0 {
			if escaped {
				escaped = false
				continue
			}
			if c == '\\' && inString == '"' {
				escaped = true
				continue
			}
			if c == inString {
				inString = 0
			}
			continue
		}
		if c == '"' || c == '\'' {
			inString = c
			continue
		}
		if c == '[' && line[i+1] == '[' {
			if end := strings.Index(line[i+2:], "]]"); end >= 0 {
				i += end + 3
				continue
			}
			return ""
		}
		if c == '-' && line[i+1] == '-' {
			return strings.TrimSpace(line[i+2:])
		}
	}
	return ""
}

func isDMSBindsSourcePath(p string) bool {
	p = filepath.ToSlash(strings.TrimSpace(p))
	if isDMSBindsPrimarySourcePath(p) {
		return true
	}
	return isDMSBindsUserOverridePath(p)
}

func isDMSBindsUserOverridePath(p string) bool {
	p = filepath.ToSlash(strings.TrimSpace(p))
	return p == "dms/binds-user.lua" || p == "./dms/binds-user.lua" ||
		strings.HasSuffix(p, "/dms/binds-user.lua")
}

func isDMSBindsPrimarySourcePath(p string) bool {
	p = filepath.ToSlash(strings.TrimSpace(p))
	return strings.Contains(p, "/dms/binds.lua") || strings.HasSuffix(p, "dms/binds.lua")
}

func hyprlandMainConfigPath(dir string) (string, error) {
	expandedDir, err := utils.ExpandPath(dir)
	if err != nil {
		return "", err
	}
	luaPath := filepath.Join(expandedDir, "hyprland.lua")
	st, err := os.Stat(luaPath)
	if err != nil {
		return "", err
	}
	if !st.Mode().IsRegular() {
		return "", os.ErrNotExist
	}
	return luaPath, nil
}
