package providers

import (
	"fmt"
	"maps"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"

	"github.com/duxlabs-dev/dux-shell/core/internal/config"
	"github.com/duxlabs-dev/dux-shell/core/internal/keybinds"
	"github.com/duxlabs-dev/dux-shell/core/internal/mangoconf"
	"github.com/duxlabs-dev/dux-shell/core/internal/utils"
)

type MangoWCProvider struct {
	configPath       string
	dmsBindsIncluded bool
	parsed           bool
}

func NewMangoWCProvider(configPath string) *MangoWCProvider {
	if configPath == "" {
		configPath = defaultMangoWCConfigDir()
	}
	return &MangoWCProvider{
		configPath: configPath,
	}
}

func defaultMangoWCConfigDir() string {
	return mangoconf.Dir()
}

func (m *MangoWCProvider) Name() string {
	return "mangowc"
}

func (m *MangoWCProvider) ModKey() keybinds.ModKey {
	return keybinds.DefaultModKey()
}

func (m *MangoWCProvider) GetCheatSheet() (*keybinds.CheatSheet, error) {
	result, err := ParseMangoWCKeysWithDMS(m.configPath)
	if err != nil {
		return nil, fmt.Errorf("failed to parse mangowc config: %w", err)
	}

	m.dmsBindsIncluded = result.DMSBindsIncluded
	m.parsed = true

	categorizedBinds := make(map[string][]keybinds.Keybind)
	for _, kb := range result.Keybinds {
		category := m.categorizeByCommand(kb.Command)
		bind := m.convertKeybind(&kb, result.ConflictingConfigs)
		categorizedBinds[category] = append(categorizedBinds[category], bind)
	}

	sheet := &keybinds.CheatSheet{
		Title:            "MangoWC Keybinds",
		Provider:         m.Name(),
		Binds:            categorizedBinds,
		DMSBindsIncluded: result.DMSBindsIncluded,
	}
	sheet.SetMod(m.ModKey())

	if result.DMSStatus != nil {
		sheet.DMSStatus = keybinds.DMSBindsStatusFrom(*result.DMSStatus)
	}

	return sheet, nil
}

func (m *MangoWCProvider) HasDMSBindsIncluded() bool {
	if m.parsed {
		return m.dmsBindsIncluded
	}

	result, err := ParseMangoWCKeysWithDMS(m.configPath)
	if err != nil {
		return false
	}

	m.dmsBindsIncluded = result.DMSBindsIncluded
	m.parsed = true
	return m.dmsBindsIncluded
}

func (m *MangoWCProvider) categorizeByCommand(command string) string {
	switch {
	case strings.Contains(command, "mon"):
		return "Monitor"
	case command == "toggleoverview" || command == "togglejump":
		return "Overview"
	case command == "toggle_scratchpad":
		return "Scratchpad"
	case strings.Contains(command, "layout") || strings.Contains(command, "proportion") ||
		strings.Contains(command, "scroller") || strings.HasPrefix(command, "dwindle"):
		return "Layout"
	case strings.Contains(command, "gaps"):
		return "Gaps"
	case strings.Contains(command, "view") || strings.Contains(command, "tag"):
		return "Tags"
	case command == "focusstack" ||
		command == "focusdir" ||
		command == "exchange_client" ||
		command == "move_client" ||
		command == "killclient" ||
		command == "togglefloating" ||
		command == "togglefullscreen" ||
		command == "togglefakefullscreen" ||
		command == "togglemaximizescreen" ||
		command == "toggleglobal" ||
		command == "toggleoverlay" ||
		command == "minimized" ||
		command == "restore_minimized" ||
		command == "movewin" ||
		command == "resizewin":
		return "Window"
	case command == "spawn" || command == "spawn_shell":
		return "Execute"
	case command == "quit" || command == "reload_config":
		return "System"
	default:
		return "Other"
	}
}

func (m *MangoWCProvider) convertKeybind(kb *MangoWCKeyBinding, conflicts map[string]*MangoWCKeyBinding) keybinds.Keybind {
	keyStr := m.formatKey(kb)
	rawAction := m.formatRawAction(kb.Command, kb.Params)
	desc := kb.Comment

	if desc == "" {
		desc = rawAction
	}

	source := "config"
	if strings.Contains(kb.Source, "dms/binds.conf") || strings.Contains(kb.Source, "dms"+string(filepath.Separator)+"binds.conf") {
		source = "dms-default"
	}

	bind := keybinds.Keybind{
		Key:         keyStr,
		Description: desc,
		Action:      rawAction,
		Source:      source,
	}

	if source == "dms-default" && conflicts != nil {
		normalizedKey := strings.ToLower(keyStr)
		if conflictKb, ok := conflicts[normalizedKey]; ok {
			bind.Conflict = &keybinds.Keybind{
				Key:         keyStr,
				Description: conflictKb.Comment,
				Action:      m.formatRawAction(conflictKb.Command, conflictKb.Params),
				Source:      "config",
			}
		}
	}

	return bind
}

func (m *MangoWCProvider) formatRawAction(command, params string) string {
	if params != "" {
		return command + " " + params
	}
	return command
}

func (m *MangoWCProvider) formatKey(kb *MangoWCKeyBinding) string {
	parts := make([]string, 0, len(kb.Mods)+1)
	parts = append(parts, kb.Mods...)
	parts = append(parts, kb.Key)
	return strings.Join(parts, "+")
}

func (m *MangoWCProvider) GetOverridePath() string {
	expanded, err := utils.ExpandPath(m.configPath)
	if err != nil {
		return filepath.Join(m.configPath, "dms", "binds.conf")
	}
	return filepath.Join(expanded, "dms", "binds.conf")
}

func (m *MangoWCProvider) validateAction(action string) error {
	action = strings.TrimSpace(action)
	switch {
	case action == "":
		return fmt.Errorf("action cannot be empty")
	case action == "spawn" || action == "spawn ":
		return fmt.Errorf("spawn command requires arguments")
	case action == "spawn_shell" || action == "spawn_shell ":
		return fmt.Errorf("spawn_shell command requires arguments")
	case strings.HasPrefix(action, "spawn "):
		rest := strings.TrimSpace(strings.TrimPrefix(action, "spawn "))
		if rest == "" {
			return fmt.Errorf("spawn command requires arguments")
		}
	case strings.HasPrefix(action, "spawn_shell "):
		rest := strings.TrimSpace(strings.TrimPrefix(action, "spawn_shell "))
		if rest == "" {
			return fmt.Errorf("spawn_shell command requires arguments")
		}
	}
	return nil
}

func (m *MangoWCProvider) SetBind(key, action, description string, options map[string]any) error {
	if err := m.validateAction(action); err != nil {
		return err
	}

	overridePath := m.GetOverridePath()

	if err := os.MkdirAll(filepath.Dir(overridePath), 0o755); err != nil {
		return fmt.Errorf("failed to create dms directory: %w", err)
	}

	existingBinds, err := m.loadOverrideBinds()
	if err != nil {
		existingBinds = make(map[string]*mangowcOverrideBind)
	}

	normalizedKey := strings.ToLower(key)
	prefix := "bind"
	if existing, ok := existingBinds[normalizedKey]; ok && existing.Prefix != "" {
		prefix = existing.Prefix
	}
	if optionPrefix := m.bindPrefixFromOptions(options); optionPrefix != "" {
		prefix = optionPrefix
	}
	if _, leaf := m.parseKeyString(key); isScrollKey(leaf) {
		prefix = mangowcAxisBindPrefix
	}

	bind := &mangowcOverrideBind{
		Key:         key,
		Action:      action,
		Description: description,
		Options:     options,
		Prefix:      prefix,
	}
	var line strings.Builder
	m.writeBindLine(&line, bind)
	for l := range strings.SplitSeq(line.String(), "\n") {
		if strings.HasPrefix(l, "#") {
			continue
		}
		if err := mangoconf.CheckLine(l); err != nil {
			return err
		}
	}
	existingBinds[normalizedKey] = bind

	return m.writeOverrideBinds(existingBinds)
}

func (m *MangoWCProvider) RemoveBind(key string) error {
	existingBinds, err := m.loadOverrideBinds()
	if err != nil {
		return nil
	}

	normalizedKey := strings.ToLower(key)
	delete(existingBinds, normalizedKey)
	return m.writeOverrideBindsWithRemoved(existingBinds, map[string]bool{normalizedKey: true})
}

func (m *MangoWCProvider) ResetBind(key string) error {
	return m.RemoveBind(key)
}

type mangowcOverrideBind struct {
	Key         string
	Action      string
	Description string
	Options     map[string]any
	Prefix      string
}

func (m *MangoWCProvider) loadOverrideBinds() (map[string]*mangowcOverrideBind, error) {
	overridePath := m.GetOverridePath()
	binds := make(map[string]*mangowcOverrideBind)

	data, err := os.ReadFile(overridePath)
	if os.IsNotExist(err) {
		return binds, nil
	}
	if err != nil {
		return nil, err
	}

	var pendingComment string
	for line := range strings.SplitSeq(string(data), "\n") {
		trimmed := strings.TrimSpace(line)
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

		bind, ok := m.parseOverrideBindLine(line, pendingComment)
		pendingComment = ""
		if !ok || bind == nil {
			continue
		}

		binds[strings.ToLower(bind.Key)] = bind
	}

	return binds, nil
}

func (m *MangoWCProvider) parseOverrideBindLine(line, precedingComment string) (*mangowcOverrideBind, bool) {
	trimmed := strings.TrimSpace(line)
	parts := strings.SplitN(trimmed, "=", 2)
	if len(parts) < 2 {
		return nil, false
	}

	prefix := strings.TrimSpace(parts[0])
	if !m.isBindPrefix(prefix) {
		return nil, false
	}

	content := strings.TrimSpace(parts[1])
	commentParts := strings.SplitN(content, "#", 2)
	bindContent := strings.TrimSpace(commentParts[0])

	description := strings.TrimSpace(precedingComment)
	if isMangoWCSectionComment(description) {
		description = ""
	}
	if len(commentParts) > 1 {
		description = strings.TrimSpace(commentParts[1])
	}
	if strings.HasPrefix(description, MangoWCHideComment) {
		return nil, true
	}

	fields := strings.SplitN(bindContent, ",", 4)
	if len(fields) < 3 {
		return nil, false
	}

	mods := strings.TrimSpace(fields[0])
	keyName := strings.TrimSpace(fields[1])
	command := strings.TrimSpace(fields[2])

	if prefix == mangowcAxisBindPrefix {
		if canonical, ok := mangowcDirectionToScroll(keyName); ok {
			keyName = canonical
		}
	}

	var params string
	if len(fields) > 3 {
		params = strings.TrimSpace(fields[3])
	}

	action := command
	if params != "" {
		action = command + " " + params
	}

	return &mangowcOverrideBind{
		Key:         m.buildKeyString(mods, keyName),
		Action:      action,
		Description: description,
		Prefix:      prefix,
	}, true
}

func (m *MangoWCProvider) isBindPrefix(prefix string) bool {
	if prefix == mangowcAxisBindPrefix {
		return true
	}
	if !strings.HasPrefix(prefix, "bind") {
		return false
	}
	for _, ch := range strings.TrimPrefix(prefix, "bind") {
		if !strings.ContainsRune("lsrp", ch) {
			return false
		}
	}
	return true
}

func (m *MangoWCProvider) buildKeyString(mods, key string) string {
	if mods == "" || strings.EqualFold(mods, "none") {
		return key
	}

	modList := strings.FieldsFunc(mods, func(r rune) bool {
		return r == '+' || r == ' '
	})

	parts := append(modList, key)
	return strings.Join(parts, "+")
}

func (m *MangoWCProvider) getBindSortPriority(action string) int {
	switch {
	case strings.HasPrefix(action, "spawn") && strings.Contains(action, "dms"):
		return 0
	case strings.Contains(action, "view") || strings.Contains(action, "tag"):
		return 1
	case strings.Contains(action, "focus") || strings.Contains(action, "exchange") ||
		strings.Contains(action, "resize") || strings.Contains(action, "move"):
		return 2
	case strings.Contains(action, "mon"):
		return 3
	case strings.HasPrefix(action, "spawn"):
		return 4
	case action == "quit" || action == "reload_config":
		return 5
	default:
		return 6
	}
}

func (m *MangoWCProvider) writeOverrideBinds(binds map[string]*mangowcOverrideBind) error {
	return m.writeOverrideBindsWithRemoved(binds, nil)
}

func (m *MangoWCProvider) writeOverrideBindsWithRemoved(binds map[string]*mangowcOverrideBind, removed map[string]bool) error {
	overridePath := m.GetOverridePath()
	existingContent := ""
	if data, err := os.ReadFile(overridePath); err == nil {
		existingContent = string(data)
	}

	content := m.generatePreservedBindsContent(existingContent, binds, removed)
	return os.WriteFile(overridePath, []byte(content), 0o644)
}

func (m *MangoWCProvider) generatePreservedBindsContent(existingContent string, binds map[string]*mangowcOverrideBind, removed map[string]bool) string {
	useStockScaffold := m.shouldUseStockScaffold(existingContent)
	source := existingContent
	if useStockScaffold {
		source = m.stockBindsScaffold(binds)
	}

	remaining := make(map[string]*mangowcOverrideBind, len(binds))
	maps.Copy(remaining, binds)
	if useStockScaffold {
		m.dropReplacedStockBinds(remaining)
	}

	var lines []string
	for line := range strings.SplitSeq(source, "\n") {
		templateBind, ok := m.parseOverrideBindLine(line, m.previousComment(lines))
		if !ok || templateBind == nil {
			lines = append(lines, line)
			continue
		}

		normalizedKey := strings.ToLower(templateBind.Key)
		m.dropPreviousDescriptionComment(&lines)

		if bind, exists := remaining[normalizedKey]; exists {
			if useStockScaffold && bind.Description == "" {
				bind = m.copyBindWithDescription(bind, templateBind.Description)
			}
			m.writeBindLineToLines(&lines, bind)
			delete(remaining, normalizedKey)
			continue
		}

		if useStockScaffold && !removed[normalizedKey] {
			m.writeBindLineToLines(&lines, templateBind)
		}
	}

	if len(remaining) > 0 {
		m.trimTrailingEmptyLines(&lines)
		if len(lines) > 0 {
			lines = append(lines, "")
		}
		lines = append(lines, "# === Custom Keybinds ===")
		for _, bind := range m.sortedBinds(remaining) {
			m.writeBindLineToLines(&lines, bind)
		}
	}

	m.trimTrailingEmptyLines(&lines)
	if len(lines) == 0 {
		return ""
	}
	return strings.Join(lines, "\n") + "\n"
}

// Only a stripped stock file is rebuilt; a file setup kept or moved, or with keymodes or mouse binds, is the user's.
func (m *MangoWCProvider) shouldUseStockScaffold(content string) bool {
	if strings.TrimSpace(content) == "" {
		return true
	}
	if mangoconf.HasUserBindsHeader(content) || mangoUserBindLine.MatchString(content) {
		return false
	}
	if strings.Contains(content, "gesturebind=") && strings.Contains(content, "# ===") {
		return false
	}
	return !strings.Contains(content, "gesturebind=") && (strings.Count(content, "\nbind=")+strings.Count(content, "\nbindl=")+strings.Count(content, "\nbinds=")+strings.Count(content, "\nbindr=")+strings.Count(content, "\nbindp=") >= 10 || strings.Contains(content, "dms ipc call"))
}

var mangoUserBindLine = regexp.MustCompile(`(?m)^\s*(keymode|key_mode|mousebind|mouse_bind|axisbind|axis_bind|switchbind|switch_bind)\s*=`)

func (m *MangoWCProvider) stockBindsScaffold(binds map[string]*mangowcOverrideBind) string {
	terminalCommand := "ghostty"
	for _, key := range []string{"super+t", "super+return"} {
		if bind, ok := binds[key]; ok {
			command, params := m.parseAction(bind.Action)
			if command == "spawn" && strings.TrimSpace(params) != "" && !strings.Contains(params, "dms ") {
				terminalCommand = params
				break
			}
		}
	}
	return strings.ReplaceAll(config.MangoBindsConfig, "{{TERMINAL_COMMAND}}", terminalCommand)
}

func (m *MangoWCProvider) dropReplacedStockBinds(binds map[string]*mangowcOverrideBind) {
	if bind, ok := binds["super+j"]; ok && bind.Action == "switch_layout" {
		delete(binds, "super+j")
	}
}

func (m *MangoWCProvider) sortedBinds(binds map[string]*mangowcOverrideBind) []*mangowcOverrideBind {
	bindList := make([]*mangowcOverrideBind, 0, len(binds))
	for _, bind := range binds {
		bindList = append(bindList, bind)
	}
	sort.Slice(bindList, func(i, j int) bool {
		pi, pj := m.getBindSortPriority(bindList[i].Action), m.getBindSortPriority(bindList[j].Action)
		if pi != pj {
			return pi < pj
		}
		return bindList[i].Key < bindList[j].Key
	})
	return bindList
}

func (m *MangoWCProvider) writeBindLineToLines(lines *[]string, bind *mangowcOverrideBind) {
	var sb strings.Builder
	m.writeBindLine(&sb, bind)
	text := strings.TrimSuffix(sb.String(), "\n")
	if text == "" {
		return
	}
	*lines = append(*lines, strings.Split(text, "\n")...)
}

func (m *MangoWCProvider) previousComment(lines []string) string {
	if len(lines) == 0 {
		return ""
	}
	trimmed := strings.TrimSpace(lines[len(lines)-1])
	if !strings.HasPrefix(trimmed, "#") {
		return ""
	}
	comment := strings.TrimSpace(strings.TrimPrefix(trimmed, "#"))
	if isMangoWCSectionComment(comment) {
		return ""
	}
	return comment
}

func (m *MangoWCProvider) dropPreviousDescriptionComment(lines *[]string) {
	if len(*lines) == 0 {
		return
	}
	trimmed := strings.TrimSpace((*lines)[len(*lines)-1])
	if !strings.HasPrefix(trimmed, "#") || strings.HasPrefix(trimmed, "# ===") {
		return
	}
	*lines = (*lines)[:len(*lines)-1]
}

func (m *MangoWCProvider) trimTrailingEmptyLines(lines *[]string) {
	for len(*lines) > 0 && strings.TrimSpace((*lines)[len(*lines)-1]) == "" {
		*lines = (*lines)[:len(*lines)-1]
	}
}

func (m *MangoWCProvider) copyBindWithDescription(bind *mangowcOverrideBind, description string) *mangowcOverrideBind {
	copy := *bind
	copy.Description = description
	return &copy
}

func (m *MangoWCProvider) writeBindLine(sb *strings.Builder, bind *mangowcOverrideBind) {
	mods, key := m.parseKeyString(bind.Key)
	command, params := m.parseAction(bind.Action)

	// Description goes on the line ABOVE the bind: mango doesn't strip inline `#`
	// comments from a value, so a trailing comment would break spawn (extra argv).
	if bind.Description != "" {
		sb.WriteString("# ")
		sb.WriteString(bind.Description)
		sb.WriteString("\n")
	}

	prefix := bind.Prefix
	if prefix == "" {
		prefix = "bind"
	}
	if prefix == mangowcAxisBindPrefix {
		if direction, ok := mangowcScrollToDirection(key); ok {
			key = direction
		}
	}
	sb.WriteString(prefix)
	sb.WriteString("=")
	if mods == "" {
		sb.WriteString("none")
	} else {
		sb.WriteString(mods)
	}
	sb.WriteString(",")
	sb.WriteString(key)
	sb.WriteString(",")
	sb.WriteString(command)

	if params != "" {
		sb.WriteString(",")
		sb.WriteString(params)
	}

	sb.WriteString("\n")
}

func (m *MangoWCProvider) bindPrefixFromOptions(options map[string]any) string {
	if options == nil {
		return ""
	}
	value, ok := options["flags"]
	if !ok {
		return ""
	}
	flags := ""
	switch v := value.(type) {
	case string:
		flags = v
	case fmt.Stringer:
		flags = v.String()
	default:
		return ""
	}
	flags = strings.TrimSpace(flags)
	if flags == "" {
		return "bind"
	}
	var clean strings.Builder
	for _, ch := range flags {
		if strings.ContainsRune("lsrp", ch) && !strings.ContainsRune(clean.String(), ch) {
			clean.WriteRune(ch)
		}
	}
	return "bind" + clean.String()
}

func (m *MangoWCProvider) parseKeyString(keyStr string) (mods, key string) {
	parts := strings.Split(keyStr, "+")
	switch len(parts) {
	case 0:
		return "", keyStr
	case 1:
		return "", parts[0]
	default:
		return strings.Join(parts[:len(parts)-1], "+"), parts[len(parts)-1]
	}
}

func (m *MangoWCProvider) parseAction(action string) (command, params string) {
	parts := strings.SplitN(action, " ", 2)
	switch len(parts) {
	case 0:
		return action, ""
	case 1:
		return parts[0], ""
	default:
		return parts[0], parts[1]
	}
}
