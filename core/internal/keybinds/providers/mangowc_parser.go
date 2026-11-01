package providers

import (
	"cmp"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strings"

	"github.com/duxlabs-dev/dux-shell/core/internal/configfrag"
	"github.com/duxlabs-dev/dux-shell/core/internal/mangoconf"
	"github.com/duxlabs-dev/dux-shell/core/internal/utils"
)

const (
	MangoWCHideComment = "[hidden]"
)

var MangoWCModSeparators = []rune{'+', ' '}

func isMangoWCSectionComment(comment string) bool {
	return strings.HasPrefix(strings.TrimSpace(comment), "===")
}

type MangoWCKeyBinding struct {
	Mods    []string `json:"mods"`
	Key     string   `json:"key"`
	Command string   `json:"command"`
	Params  string   `json:"params"`
	Comment string   `json:"comment"`
	Source  string   `json:"source"`
	Mode    string   `json:"mode"`

	allowConflict bool
}

type MangoWCParser struct {
	contentLines       []string
	readingLine        int
	configDir          string
	currentMode        string
	vars               mangoconf.Vars
	dmsBindsExists     bool
	walker             *configfrag.Walker
	bindsAfterDMS      int
	conflictingConfigs map[string]*MangoWCKeyBinding
	binds              []*MangoWCKeyBinding
	seen               map[string][]mangoBindRecord
	dmsProcessed       bool
}

type mangoBindRecord struct {
	bind *MangoWCKeyBinding
	// slot is -1 for a shadowed bind the cheatsheet does not list.
	slot int
}

func NewMangoWCParser(configDir string) *MangoWCParser {
	return &MangoWCParser{
		contentLines:       []string{},
		readingLine:        0,
		configDir:          configDir,
		walker:             configfrag.NewWalker(isDMSMangoBindsSourcePath),
		currentMode:        mangoDefaultMode,
		vars:               mangoconf.Vars{},
		conflictingConfigs: make(map[string]*MangoWCKeyBinding),
		seen:               make(map[string][]mangoBindRecord),
	}
}

func (p *MangoWCParser) ReadContent(path string) error {
	expandedPath, err := utils.ExpandPath(path)
	if err != nil {
		return err
	}

	info, err := os.Stat(expandedPath)
	if err != nil {
		return err
	}

	var files []string
	if info.IsDir() {
		confFiles, err := filepath.Glob(filepath.Join(expandedPath, "*.conf"))
		if err != nil {
			return err
		}
		if len(confFiles) == 0 {
			return os.ErrNotExist
		}
		files = confFiles
	} else {
		files = []string{expandedPath}
	}

	var combinedContent []string
	for _, file := range files {
		if fileInfo, err := os.Stat(file); err == nil && fileInfo.Mode().IsRegular() {
			data, err := os.ReadFile(file)
			if err == nil {
				combinedContent = append(combinedContent, string(data))
			}
		}
	}

	if len(combinedContent) == 0 {
		return os.ErrNotExist
	}

	fullContent := strings.Join(combinedContent, "\n")
	p.contentLines = strings.Split(fullContent, "\n")
	return nil
}

func mangowcAutogenerateComment(command, params string) string {
	switch command {
	case "spawn", "spawn_shell":
		return params
	case "killclient":
		return "Close window"
	case "quit":
		return "Exit MangoWC"
	case "reload_config":
		return "Reload configuration"
	case "focusstack":
		if params == "next" {
			return "Focus next window"
		}
		if params == "prev" {
			return "Focus previous window"
		}
		return "Focus stack " + params
	case "focusdir":
		dirMap := map[string]string{
			"left":  "left",
			"right": "right",
			"up":    "up",
			"down":  "down",
		}
		if dir, ok := dirMap[params]; ok {
			return "Focus " + dir
		}
		return "Focus " + params
	case "exchange_client":
		dirMap := map[string]string{
			"left":  "left",
			"right": "right",
			"up":    "up",
			"down":  "down",
		}
		if dir, ok := dirMap[params]; ok {
			return "Swap window " + dir
		}
		return "Swap window " + params
	case "move_client":
		return "Move window " + params
	case "scroller_stack":
		return "Stack window " + params
	case "togglejump":
		return "Jump to window"
	case "dwindle_toggle_split_direction":
		return "Toggle split direction"
	case "togglefloating":
		return "Float/unfloat window"
	case "togglefullscreen":
		return "Toggle fullscreen"
	case "togglefakefullscreen":
		return "Toggle fake fullscreen"
	case "togglemaximizescreen":
		return "Toggle maximize"
	case "toggleglobal":
		return "Toggle global"
	case "toggleoverview":
		return "Toggle overview"
	case "toggleoverlay":
		return "Toggle overlay"
	case "minimized":
		return "Minimize window"
	case "restore_minimized":
		return "Restore minimized"
	case "toggle_scratchpad":
		return "Toggle scratchpad"
	case "setlayout":
		return "Set layout " + params
	case "switch_layout":
		return "Switch layout"
	case "view":
		parts := strings.Split(params, ",")
		if len(parts) > 0 {
			return "View tag " + parts[0]
		}
		return "View tag"
	case "tag":
		parts := strings.Split(params, ",")
		if len(parts) > 0 {
			return "Move to tag " + parts[0]
		}
		return "Move to tag"
	case "toggleview":
		parts := strings.Split(params, ",")
		if len(parts) > 0 {
			return "Toggle tag " + parts[0]
		}
		return "Toggle tag"
	case "viewtoleft", "viewtoleft_have_client":
		return "View left tag"
	case "viewtoright", "viewtoright_have_client":
		return "View right tag"
	case "tagtoleft":
		return "Move to left tag"
	case "tagtoright":
		return "Move to right tag"
	case "focusmon":
		return "Focus monitor " + params
	case "tagmon":
		return "Move to monitor " + params
	case "incgaps":
		if strings.HasPrefix(params, "-") {
			return "Decrease gaps"
		}
		return "Increase gaps"
	case "togglegaps":
		return "Toggle gaps"
	case "movewin":
		return "Move window by " + params
	case "resizewin":
		return "Resize window by " + params
	case "set_proportion":
		return "Set proportion " + params
	case "switch_proportion_preset":
		return "Switch proportion preset"
	default:
		return ""
	}
}

func (p *MangoWCParser) getKeybindAtLine(lineNumber int, precedingComment string) *MangoWCKeyBinding {
	if lineNumber >= len(p.contentLines) {
		return nil
	}
	return p.getKeybindAtLineContent(p.contentLines[lineNumber], precedingComment)
}

func (p *MangoWCParser) ParseKeys() []MangoWCKeyBinding {
	var keybinds []MangoWCKeyBinding
	var pendingComment string

	for lineNumber := 0; lineNumber < len(p.contentLines); lineNumber++ {
		trimmed := strings.TrimSpace(p.contentLines[lineNumber])
		if trimmed == "" {
			pendingComment = ""
			continue
		}
		if after, ok := strings.CutPrefix(trimmed, "#"); ok {
			pendingComment = strings.TrimSpace(after)
			if isMangoWCSectionComment(pendingComment) {
				pendingComment = ""
			}
			continue
		}
		if !strings.HasPrefix(trimmed, "bind") && !strings.HasPrefix(trimmed, mangowcAxisBindPrefix) {
			pendingComment = ""
			continue
		}

		keybind := p.getKeybindAtLine(lineNumber, pendingComment)
		if keybind != nil {
			keybinds = append(keybinds, *keybind)
		}
		pendingComment = ""
	}

	return keybinds
}

func ParseMangoWCKeys(path string) ([]MangoWCKeyBinding, error) {
	parser := NewMangoWCParser(path)
	if err := parser.ReadContent(path); err != nil {
		return nil, err
	}
	return parser.ParseKeys(), nil
}

type MangoWCParseResult struct {
	Keybinds           []MangoWCKeyBinding
	DMSBindsIncluded   bool
	DMSStatus          *configfrag.Status
	ConflictingConfigs map[string]*MangoWCKeyBinding
}

var mangowcBindsMessages = configfrag.Messages{
	Missing:     "dms/binds.conf does not exist",
	NotIncluded: "dms/binds.conf is not sourced in config",
	Overridden:  "Some DMS binds may be overridden by config binds",
	Active:      "DMS binds are active",
}

func (p *MangoWCParser) buildDMSStatus() *configfrag.Status {
	status := configfrag.BuildStatus(p.walker.Scan(), p.dmsBindsExists, p.bindsAfterDMS, mangowcBindsMessages)
	return &status
}

func (p *MangoWCParser) formatBindKey(kb *MangoWCKeyBinding) string {
	parts := make([]string, 0, len(kb.Mods)+1)
	parts = append(parts, kb.Mods...)
	parts = append(parts, kb.Key)
	return strings.Join(parts, "+")
}

func (p *MangoWCParser) normalizeKey(key string) string {
	return strings.ToLower(key)
}

const (
	mangoDefaultMode = "default"
	mangoCommonMode  = "common"
)

func isDMSMangoBind(kb *MangoWCKeyBinding) bool {
	return strings.Contains(kb.Source, "dms/binds.conf") || strings.Contains(kb.Source, "dms"+string(os.PathSeparator)+"binds.conf")
}

// One key can be bound once per mode.
func mangoConflictKey(mode, normalizedKey string) string {
	return mode + ":" + normalizedKey
}

// mangoModesMeet mirrors upstream conflict_check.c: binds meet within one key mode, and a common bind meets every mode.
func mangoModesMeet(a, b string) bool {
	return a == b || a == mangoCommonMode || b == mangoCommonMode
}

func (p *MangoWCParser) addBind(kb *MangoWCKeyBinding) {
	key := p.normalizeKey(p.formatBindKey(kb))

	// Mango (>= 0.15.5) applies the first matching bind, so the earliest bind meeting kb shadows it,
	// even one that is itself shadowed in another mode.
	slot := len(p.binds)
	for _, earlier := range p.seen[key] {
		// Mango runs a c-flagged bind and keeps matching.
		if earlier.bind.allowConflict || !mangoModesMeet(earlier.bind.Mode, kb.Mode) {
			continue
		}
		slot = -1
		if isDMSMangoBind(kb) && !isDMSMangoBind(earlier.bind) {
			p.bindsAfterDMS++
			p.conflictingConfigs[mangoConflictKey(kb.Mode, key)] = earlier.bind
			slot = len(p.binds)
			if earlier.slot >= 0 && p.binds[earlier.slot] == earlier.bind {
				slot = earlier.slot
			}
		}
		break
	}
	switch {
	case slot == len(p.binds):
		p.binds = append(p.binds, kb)
	case slot >= 0:
		p.binds[slot] = kb
	}
	p.seen[key] = append(p.seen[key], mangoBindRecord{bind: kb, slot: slot})
}

func (p *MangoWCParser) ParseWithDMS() ([]MangoWCKeyBinding, error) {
	expandedDir, err := utils.ExpandPath(p.configDir)
	if err != nil {
		return nil, err
	}
	if expandedDir, err = filepath.Abs(expandedDir); err != nil {
		return nil, err
	}

	dmsBindsPath := filepath.Join(expandedDir, "dms", "binds.conf")
	if _, err := os.Stat(dmsBindsPath); err == nil {
		p.dmsBindsExists = true
	}

	if err := mangoconf.Walk(expandedDir, mangoconf.MainConfig(expandedDir), p.vars, p.visit); err != nil {
		return nil, err
	}
	if p.dmsBindsExists && !p.dmsProcessed {
		_ = mangoconf.Walk(expandedDir, dmsBindsPath, p.vars, p.visit)
	}

	keybinds := make([]MangoWCKeyBinding, 0, len(p.binds))
	for _, kb := range p.binds {
		keybinds = append(keybinds, *kb)
	}
	return keybinds, nil
}

func (p *MangoWCParser) visit(file string, e mangoconf.Entry) {
	switch {
	case e.IsSource():
		if p.walker.RecordMatch(e.Value != "" && isDMSMangoBindsSourcePath(e.Value)) {
			p.dmsProcessed = true
		}
	case e.Key == "key_mode":
		p.currentMode = e.Value
	case mangowcBindKeyword.MatchString(e.Key):
		comment := e.Comment
		if isMangoWCSectionComment(comment) {
			comment = ""
		}
		kb := mangowcBind(e.Key, e.Value, comment)
		if kb == nil {
			return
		}
		kb.Source = file
		kb.Mode = cmp.Or(e.Mode, p.currentMode)
		kb.allowConflict = strings.Contains(strings.TrimPrefix(strings.TrimPrefix(e.Key, "axis"), "bind"), "c")
		p.addBind(kb)
	}
}

func isDMSMangoBindsSourcePath(sourcePath string) bool {
	return strings.HasSuffix(sourcePath, "/dms/binds.conf")
}

var (
	mangowcBindLine    = regexp.MustCompile(`^((?:axis)?bind[lsrpc]*)\s*=\s*(.+)$`)
	mangowcBindKeyword = regexp.MustCompile(`^(axis)?bind[lsrpc]*$`)
)

func (p *MangoWCParser) getKeybindAtLineContent(line string, precedingComment string) *MangoWCKeyBinding {
	matches := mangowcBindLine.FindStringSubmatch(line)
	if len(matches) < 3 {
		return nil
	}

	content := matches[2]
	parts := strings.SplitN(content, "#", 2)
	keys := parts[0]

	var comment string
	if len(parts) > 1 {
		comment = strings.TrimSpace(parts[1])
	}
	if comment == "" {
		comment = strings.TrimSpace(precedingComment)
		if isMangoWCSectionComment(comment) {
			comment = ""
		}
	}
	return mangowcBind(matches[1], keys, comment)
}

func mangowcBind(keyword, value, comment string) *MangoWCKeyBinding {
	if strings.HasPrefix(comment, MangoWCHideComment) {
		return nil
	}

	keyFields := strings.SplitN(value, ",", 4)
	if len(keyFields) < 3 {
		return nil
	}

	mods := strings.TrimSpace(keyFields[0])
	key := strings.TrimSpace(keyFields[1])
	command := strings.TrimSpace(keyFields[2])

	if strings.HasPrefix(keyword, mangowcAxisBindPrefix) {
		if canonical, ok := mangowcDirectionToScroll(key); ok {
			key = canonical
		}
	}

	var params string
	if len(keyFields) > 3 {
		params = strings.TrimSpace(keyFields[3])
	}

	if comment == "" {
		comment = mangowcAutogenerateComment(command, params)
	}

	var modList []string
	if mods != "" && !strings.EqualFold(mods, "none") {
		modstring := mods + string(MangoWCModSeparators[0])
		idx := 0
		for index, char := range modstring {
			isModSep := slices.Contains(MangoWCModSeparators, char)
			if isModSep {
				if index-idx > 1 {
					modList = append(modList, modstring[idx:index])
				}
				idx = index + 1
			}
		}
	}

	return &MangoWCKeyBinding{
		Mods:    modList,
		Key:     key,
		Command: command,
		Params:  params,
		Comment: comment,
	}
}

func ParseMangoWCKeysWithDMS(path string) (*MangoWCParseResult, error) {
	parser := NewMangoWCParser(path)
	keybinds, err := parser.ParseWithDMS()
	if err != nil {
		return nil, err
	}

	return &MangoWCParseResult{
		Keybinds:           keybinds,
		DMSBindsIncluded:   parser.walker.Included(),
		DMSStatus:          parser.buildDMSStatus(),
		ConflictingConfigs: parser.conflictingConfigs,
	}, nil
}
