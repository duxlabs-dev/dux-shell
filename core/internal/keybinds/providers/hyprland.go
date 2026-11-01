package providers

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"

	"github.com/duxlabs-dev/dux-shell/core/internal/keybinds"
	"github.com/duxlabs-dev/dux-shell/core/internal/utils"
)

type HyprlandProvider struct {
	configPath       string
	dmsBindsIncluded bool
	parsed           bool
}

func NewHyprlandProvider(configPath string) *HyprlandProvider {
	if configPath == "" {
		configPath = defaultHyprlandConfigDir()
	}
	return &HyprlandProvider{
		configPath: configPath,
	}
}

func defaultHyprlandConfigDir() string {
	configDir, err := os.UserConfigDir()
	if err != nil {
		return ""
	}
	return filepath.Join(configDir, "hypr")
}

func (h *HyprlandProvider) Name() string {
	return "hyprland"
}

func (h *HyprlandProvider) GetCheatSheet() (*keybinds.CheatSheet, error) {
	result, err := ParseHyprlandKeysWithDMS(h.configPath)
	if err != nil {
		return nil, fmt.Errorf("failed to parse hyprland config: %w", err)
	}

	h.dmsBindsIncluded = result.DMSBindsIncluded
	h.parsed = true

	categorizedBinds := make(map[string][]keybinds.Keybind)
	h.convertSection(result.Section, "", categorizedBinds, result.ConflictingConfigs, result.DefaultDMSKeys)

	sheet := &keybinds.CheatSheet{
		Title:            "Hyprland Keybinds",
		Provider:         h.Name(),
		Binds:            categorizedBinds,
		DMSBindsIncluded: result.DMSBindsIncluded,
	}
	sheet.SetMod(keybinds.ConfiguredModKey("", result.MainMod))

	if result.DMSStatus != nil {
		sheet.DMSStatus = keybinds.DMSBindsStatusFrom(*result.DMSStatus)
	}

	return sheet, nil
}

func (h *HyprlandProvider) HasDMSBindsIncluded() bool {
	if h.parsed {
		return h.dmsBindsIncluded
	}

	result, err := ParseHyprlandKeysWithDMS(h.configPath)
	if err != nil {
		return false
	}

	h.dmsBindsIncluded = result.DMSBindsIncluded
	h.parsed = true
	return h.dmsBindsIncluded
}

func (h *HyprlandProvider) convertSection(section *HyprlandSection, subcategory string, categorizedBinds map[string][]keybinds.Keybind, conflicts map[string]*HyprlandKeyBinding, defaultKeys map[string]bool) {
	currentSubcat := subcategory
	if section.Name != "" {
		currentSubcat = section.Name
	}

	for _, kb := range section.Keybinds {
		category := h.categorizeBind(&kb)
		bind := h.convertKeybind(&kb, currentSubcat, conflicts, defaultKeys)
		categorizedBinds[category] = append(categorizedBinds[category], bind)
	}

	for _, child := range section.Children {
		h.convertSection(&child, currentSubcat, categorizedBinds, conflicts, defaultKeys)
	}
}

var luaFunctionActionPattern = regexp.MustCompile(`^(function\s*\(|[A-Za-z_][A-Za-z0-9_.]*$)`)

// A function or named-function action says nothing about what it does; its description does.
func (h *HyprlandProvider) categorizeBind(kb *HyprlandKeyBinding) string {
	if kb.Comment == "" || kb.Params != "" || !luaFunctionActionPattern.MatchString(kb.Dispatcher) {
		return h.categorizeByDispatcher(kb.Dispatcher)
	}
	if _, known := luaActionStringFromHyprlangAction(kb.Dispatcher); known {
		return h.categorizeByDispatcher(kb.Dispatcher)
	}
	return h.categorizeByDispatcher(strings.ToLower(kb.Comment))
}

func (h *HyprlandProvider) categorizeByDispatcher(dispatcher string) string {
	switch {
	case dispatcher == "exec" || strings.HasPrefix(dispatcher, "hl.dsp.exec_cmd("):
		return "Execute"
	case strings.Contains(dispatcher, "workspace"):
		return "Workspace"
	case strings.Contains(dispatcher, "monitor"):
		return "Monitor"
	case strings.Contains(dispatcher, "window") ||
		strings.Contains(dispatcher, "focus") ||
		strings.Contains(dispatcher, "move") ||
		strings.Contains(dispatcher, "swap") ||
		strings.Contains(dispatcher, "resize") ||
		dispatcher == "killactive" ||
		dispatcher == "fullscreen" ||
		dispatcher == "togglefloating" ||
		dispatcher == "pin" ||
		dispatcher == "splitratio" ||
		dispatcher == "resizeactive":
		return "Window"
	case dispatcher == "exit" || dispatcher == "reloadconfig" || strings.Contains(dispatcher, "dpms"):
		return "System"
	default:
		return "Other"
	}
}

func (h *HyprlandProvider) convertKeybind(kb *HyprlandKeyBinding, subcategory string, conflicts map[string]*HyprlandKeyBinding, defaultKeys map[string]bool) keybinds.Keybind {
	keyStr := h.formatKey(kb)
	rawAction := h.formatRawAction(kb.Dispatcher, kb.Params)
	desc := kb.Comment

	if desc == "" {
		desc = rawAction
	}

	source := "config"
	if isDMSBindsUserOverridePath(kb.Source) {
		source = "dms"
	} else if isDMSBindsPrimarySourcePath(kb.Source) {
		source = "dms-default"
	}

	hasDefault := false
	if source == "dms" && defaultKeys != nil {
		hasDefault = defaultKeys[strings.ToLower(keyStr)]
	}

	bind := keybinds.Keybind{
		Key:         keyStr,
		Description: desc,
		Action:      rawAction,
		Subcategory: subcategory,
		Source:      source,
		Flags:       kb.Flags,
		HasDefault:  hasDefault,
	}
	if expr, ok := luaActionStringFromHyprlangAction(rawAction); ok {
		bind.LuaAction = expr
	}

	if (source == "dms" || source == "dms-default") && conflicts != nil {
		normalizedKey := strings.ToLower(keyStr)
		if conflictKb, ok := conflicts[normalizedKey]; ok {
			bind.Conflict = &keybinds.Keybind{
				Key:         keyStr,
				Description: conflictKb.Comment,
				Action:      h.formatRawAction(conflictKb.Dispatcher, conflictKb.Params),
				Source:      "config",
			}
		}
	}

	return bind
}

func (h *HyprlandProvider) formatRawAction(dispatcher, params string) string {
	if params != "" {
		return dispatcher + " " + params
	}
	return dispatcher
}

func (h *HyprlandProvider) formatKey(kb *HyprlandKeyBinding) string {
	key := kb.Key
	if canonical, ok := hyprlandScrollToCanonical(key); ok {
		key = canonical
	}
	parts := make([]string, 0, len(kb.Mods)+1)
	parts = append(parts, kb.Mods...)
	parts = append(parts, key)
	return strings.Join(parts, "+")
}

func (h *HyprlandProvider) ModKey() keybinds.ModKey {
	result, err := ParseHyprlandKeysWithDMS(h.configPath)
	if err != nil {
		return keybinds.DefaultModKey()
	}
	return keybinds.ConfiguredModKey("", result.MainMod)
}

func (h *HyprlandProvider) GetOverridePath() string {
	expanded, err := utils.ExpandPath(h.configPath)
	if err != nil {
		return filepath.Join(h.configPath, "dms", "binds-user.lua")
	}
	return filepath.Join(expanded, "dms", "binds-user.lua")
}

func (h *HyprlandProvider) validateAction(action string) error {
	action = strings.TrimSpace(action)
	switch {
	case action == "":
		return fmt.Errorf("action cannot be empty")
	case action == "exec" || action == "exec ":
		return fmt.Errorf("exec dispatcher requires arguments")
	case strings.HasPrefix(action, "exec "):
		rest := strings.TrimSpace(strings.TrimPrefix(action, "exec "))
		if rest == "" {
			return fmt.Errorf("exec dispatcher requires arguments")
		}
	}
	if isRawLuaActionText(action) {
		return nil
	}
	if _, ok := luaActionStringFromHyprlangAction(action); !ok {
		return fmt.Errorf("hyprland %q is not a Lua dispatcher or is missing its arguments", action)
	}
	return nil
}

var luaExprActionPattern = regexp.MustCompile(`^(function\s*\(|hl\.)`)

// The balance check keeps malformed input from corrupting the generated file.
func isRawLuaActionText(action string) bool {
	if !luaExprActionPattern.MatchString(action) {
		return false
	}
	depth := 0
	var quote byte
	escaped := false
	for i := 0; i < len(action); i++ {
		c := action[i]
		switch {
		case escaped:
			escaped = false
		case quote != 0:
			switch c {
			case '\\':
				escaped = true
			case quote:
				quote = 0
			}
		case c == '"' || c == '\'':
			quote = c
		case c == '(':
			depth++
		case c == ')':
			depth--
			if depth < 0 {
				return false
			}
		}
	}
	return depth == 0 && quote == 0 && !escaped
}

func (h *HyprlandProvider) SetBind(key, action, description string, options map[string]any) error {
	if err := h.ensureWritableConfig(); err != nil {
		return err
	}
	if err := h.validateAction(action); err != nil {
		return err
	}

	overridePath := h.GetOverridePath()

	if err := os.MkdirAll(filepath.Dir(overridePath), 0o755); err != nil {
		return fmt.Errorf("failed to create dms directory: %w", err)
	}

	existingBinds, err := h.loadOverrideBinds()
	if err != nil {
		existingBinds = make(map[string]*hyprlandOverrideBind)
	}

	var flags string
	if options != nil {
		if f, ok := options["flags"].(string); ok {
			flags = f
		}
	}

	canonicalKey := canonicalHyprlandOverrideKey(key)
	normalizedKey := hyprlandOverrideMapKey(canonicalKey)
	var device string
	if prev := existingBinds[normalizedKey]; prev != nil {
		device = prev.Device
	} else {
		device = h.mainConfigBindDevice(normalizedKey)
	}
	existingBinds[normalizedKey] = &hyprlandOverrideBind{
		Key:          canonicalKey,
		Action:       action,
		Description:  description,
		Flags:        flags,
		Device:       device,
		Options:      options,
		RawLuaAction: isRawLuaActionText(action),
	}

	return h.writeOverrideBinds(existingBinds)
}

func (h *HyprlandProvider) mainConfigBindDevice(normalizedKey string) string {
	parser := NewHyprlandParser(h.configPath)
	if _, err := parser.ParseWithDMS(); err != nil {
		return ""
	}
	if kb := parser.bindMap[normalizedKey]; kb != nil && kb.Device != "" {
		return kb.Device
	}
	if kb := parser.conflictingConfigs[normalizedKey]; kb != nil {
		return kb.Device
	}
	return ""
}

func (h *HyprlandProvider) RemoveBind(key string) error {
	if err := h.ensureWritableConfig(); err != nil {
		return err
	}
	existingBinds, err := h.loadOverrideBinds()
	if err != nil {
		return nil
	}
	canonicalKey := canonicalHyprlandOverrideKey(key)
	normalizedKey := hyprlandOverrideMapKey(canonicalKey)
	existingBinds[normalizedKey] = &hyprlandOverrideBind{Key: canonicalKey, Unbind: true}
	return h.writeOverrideBinds(existingBinds)
}

func (h *HyprlandProvider) ResetBind(key string) error {
	if err := h.ensureWritableConfig(); err != nil {
		return err
	}
	existingBinds, err := h.loadOverrideBinds()
	if err != nil {
		return nil
	}
	normalizedKey := hyprlandOverrideMapKey(key)
	delete(existingBinds, normalizedKey)
	return h.writeOverrideBinds(existingBinds)
}

type hyprlandOverrideBind struct {
	Key         string
	Action      string
	Description string
	Flags       string // see hyprlandBindFlagOptions
	Device      string // raw hl.bind device table, written when Flags has k
	Options     map[string]any
	// Unbind: negative override (hl.unbind only, no rebind).
	Unbind bool
	// RawLuaAction: Action is a custom hl.* Lua expression round-tripped from an
	// existing Lua override; re-emit it verbatim instead of quoting it.
	RawLuaAction bool
}

// Include repair would write a stub hyprland.lua, replacing a conf-only user's whole config.
func (h *HyprlandProvider) ensureWritableConfig() error {
	_, err := hyprlandMainConfigPath(h.configPath)
	switch {
	case err == nil:
		return nil
	case errors.Is(err, os.ErrNotExist):
		return fmt.Errorf("hyprland.lua not found in %s; run `dms setup` to migrate before editing keybinds: %w", h.configPath, err)
	default:
		return fmt.Errorf("cannot read hyprland.lua in %s: %w", h.configPath, err)
	}
}

func (h *HyprlandProvider) loadOverrideBinds() (map[string]*hyprlandOverrideBind, error) {
	return readLuaOverride(h.GetOverridePath())
}

func canonicalHyprlandOverrideKey(key string) string {
	trimmed := strings.TrimSpace(key)
	normalized := luaKeyComboToInternalKey(trimmed)
	if normalized == "" {
		return trimmed
	}
	return normalized
}

func hyprlandOverrideMapKey(key string) string {
	return strings.ToLower(canonicalHyprlandOverrideKey(key))
}

func (h *HyprlandProvider) getBindSortPriority(action string) int {
	switch {
	case strings.HasPrefix(action, "exec") && strings.Contains(action, "dms"):
		return 0
	case strings.Contains(action, "workspace"):
		return 1
	case strings.Contains(action, "window") || strings.Contains(action, "focus") ||
		strings.Contains(action, "move") || strings.Contains(action, "swap") ||
		strings.Contains(action, "resize"):
		return 2
	case strings.Contains(action, "monitor"):
		return 3
	case strings.HasPrefix(action, "exec"):
		return 4
	case action == "exit" || strings.Contains(action, "dpms"):
		return 5
	default:
		return 6
	}
}

func (h *HyprlandProvider) writeOverrideBinds(binds map[string]*hyprlandOverrideBind) error {
	overridePath := h.GetOverridePath()
	content := h.generateBindsContent(binds)
	return os.WriteFile(overridePath, []byte(content), 0o644)
}

func (h *HyprlandProvider) generateBindsContent(binds map[string]*hyprlandOverrideBind) string {
	if len(binds) == 0 {
		return ""
	}

	bindList := make([]*hyprlandOverrideBind, 0, len(binds))
	for _, bind := range binds {
		bindList = append(bindList, bind)
	}

	sort.Slice(bindList, func(i, j int) bool {
		pi, pj := h.getBindSortPriority(bindList[i].Action), h.getBindSortPriority(bindList[j].Action)
		if pi != pj {
			return pi < pj
		}
		return bindList[i].Key < bindList[j].Key
	})

	var sb strings.Builder
	sb.WriteString("-- DMS user keybind overrides (edit via Control Center or dms; do not remove this header)\n\n")
	for _, bind := range bindList {
		writeLuaBindLine(&sb, bind)
	}

	return sb.String()
}

func formatLuaBindKey(internalKey string) string {
	internalKey = strings.TrimSpace(internalKey)
	parts := strings.Split(internalKey, "+")
	for i := range parts {
		parts[i] = normalizeLuaBindKeyPart(strings.TrimSpace(parts[i]))
	}
	return strings.Join(parts, " + ")
}

func normalizeLuaBindKeyPart(part string) string {
	switch strings.ToLower(part) {
	case "super", "mod4", "mainmod":
		return "SUPER"
	case "ctrl", "control":
		return "CTRL"
	case "shift":
		return "SHIFT"
	case "alt", "mod1":
		return "ALT"
	}
	if native, ok := hyprlandScrollToNative(part); ok {
		return native
	}
	if len(part) == 1 {
		return strings.ToUpper(part)
	}
	return part
}

type luaField struct {
	name  string
	value string
}

func luaDispatcherTableCall(funcName string, fields ...luaField) string {
	parts := make([]string, 0, len(fields))
	for _, field := range fields {
		if field.name == "" || field.value == "" {
			continue
		}
		parts = append(parts, field.name+" = "+field.value)
	}
	return fmt.Sprintf(`%s({ %s })`, funcName, strings.Join(parts, ", "))
}

func luaStringField(name, value string) luaField {
	return luaField{name: name, value: strconv.Quote(strings.TrimSpace(value))}
}

func luaBoolField(name string, value bool) luaField {
	if value {
		return luaField{name: name, value: "true"}
	}
	return luaField{name: name, value: "false"}
}

func luaNumberOrStringField(name, value string) luaField {
	value = strings.TrimSpace(value)
	if isBareLuaNumber(value) {
		return luaField{name: name, value: value}
	}
	return luaStringField(name, value)
}

func isBareLuaNumber(value string) bool {
	if value == "" || strings.HasPrefix(value, "+") {
		return false
	}
	if value[0] == '-' {
		value = value[1:]
	}
	if value == "" {
		return false
	}
	digitsBeforeDot := 0
	i := 0
	for i < len(value) && value[i] >= '0' && value[i] <= '9' {
		digitsBeforeDot++
		i++
	}
	digitsAfterDot := 0
	if i < len(value) && value[i] == '.' {
		i++
		for i < len(value) && value[i] >= '0' && value[i] <= '9' {
			digitsAfterDot++
			i++
		}
	}
	return i == len(value) && (digitsBeforeDot > 0 || digitsAfterDot > 0)
}

func splitHyprlandAction(action string) (dispatcher, params string) {
	action = strings.TrimSpace(action)
	if action == "" {
		return "", ""
	}
	idx := strings.IndexFunc(action, func(r rune) bool {
		return r == ' ' || r == '\t' || r == '\r' || r == '\n'
	})
	if idx < 0 {
		return strings.ToLower(action), ""
	}
	return strings.ToLower(strings.TrimSpace(action[:idx])), strings.TrimSpace(action[idx+1:])
}

func firstParam(params string) (head, rest string) {
	params = strings.TrimSpace(params)
	if params == "" {
		return "", ""
	}
	fields := strings.Fields(params)
	if len(fields) == 0 {
		return "", ""
	}
	head = fields[0]
	rest = strings.TrimSpace(strings.TrimPrefix(params, head))
	return head, rest
}

func xyParams(params string) (x, y string, relative bool, ok bool) {
	fields := strings.Fields(params)
	if len(fields) > 0 && strings.EqualFold(fields[0], "exact") {
		relative = false
		fields = fields[1:]
	} else {
		relative = true
	}
	if len(fields) < 2 {
		return "", "", relative, false
	}
	return fields[0], fields[1], relative, true
}

func dispatcherWorkspaceMove(params string, follow *bool) string {
	workspace, window := firstParam(params)
	if workspace == "" {
		return ""
	}
	fields := []luaField{luaStringField("workspace", workspace)}
	if follow != nil {
		fields = append(fields, luaBoolField("follow", *follow))
	}
	if window != "" {
		fields = append(fields, luaStringField("window", window))
	}
	return luaDispatcherTableCall("hl.dsp.window.move", fields...)
}

func dispatcherActiveMoveResize(funcName, params string) string {
	x, y, relative, ok := xyParams(params)
	if !ok {
		return ""
	}
	if !isBareLuaNumber(x) || !isBareLuaNumber(y) {
		return ""
	}
	return luaDispatcherTableCall(funcName,
		luaNumberOrStringField("x", x),
		luaNumberOrStringField("y", y),
		luaBoolField("relative", relative),
	)
}

func dispatcherWindowMoveResize(funcName, params string) string {
	geometry, window := splitCommaParams(params)
	x, y, relative, ok := xyParams(geometry)
	if !ok {
		return ""
	}
	if !isBareLuaNumber(x) || !isBareLuaNumber(y) {
		return ""
	}
	fields := []luaField{
		luaNumberOrStringField("x", x),
		luaNumberOrStringField("y", y),
		luaBoolField("relative", relative),
	}
	if window != "" {
		fields = append(fields, luaStringField("window", window))
	}
	return luaDispatcherTableCall(funcName, fields...)
}

func splitCommaParams(params string) (left, right string) {
	left = strings.TrimSpace(params)
	if idx := strings.Index(left, ","); idx >= 0 {
		right = strings.TrimSpace(left[idx+1:])
		left = strings.TrimSpace(left[:idx])
	}
	return left, right
}

func dispatcherFullscreen(params string) string {
	mode, rest := firstParam(params)
	action, _ := firstParam(rest)
	// the editor drops an empty mode, leaving "fullscreen set"
	if action == "" && (mode == "toggle" || mode == "set" || mode == "unset") {
		mode, action = "", mode
	}
	switch mode {
	case "", "0":
		mode = "fullscreen"
	case "1":
		mode = "maximized"
	default:
		return ""
	}
	switch action {
	case "":
		action = "toggle"
	case "toggle", "set", "unset":
	default:
		return ""
	}
	return luaDispatcherTableCall("hl.dsp.window.fullscreen", luaStringField("mode", mode), luaStringField("action", action))
}

// The dwindle layoutmsg wants `exact` last, unlike legacy `splitratio exact 0.5`.
func dispatcherSplitRatio(params string) string {
	fields := strings.Fields(params)
	exact := len(fields) > 0 && strings.EqualFold(fields[0], "exact")
	if exact {
		fields = fields[1:]
	}
	if len(fields) != 1 {
		return ""
	}
	msg := "splitratio " + fields[0]
	if exact {
		msg += " exact"
	}
	return fmt.Sprintf(`hl.dsp.layout(%s)`, strconv.Quote(msg))
}

func luaToggleActionValue(params string) string {
	switch strings.ToLower(strings.TrimSpace(params)) {
	case "on", "enable", "enabled", "set", "lock":
		return "on"
	case "off", "disable", "disabled", "unset", "unlock":
		return "off"
	default:
		return "toggle"
	}
}

func dispatcherToggleTableCall(funcName, params string) string {
	return luaDispatcherTableCall(funcName, luaStringField("action", luaToggleActionValue(params)))
}

func dispatcherCycleNext(params string) string {
	params = strings.TrimSpace(strings.ToLower(params))
	if params == "" {
		return `hl.dsp.window.cycle_next()`
	}
	fields := []luaField{}
	for field := range strings.FieldsSeq(params) {
		switch field {
		case "prev", "previous", "b":
			fields = append(fields, luaBoolField("next", false))
		case "next", "f":
			fields = append(fields, luaBoolField("next", true))
		case "tiled":
			fields = append(fields, luaBoolField("tiled", true))
		case "floating":
			fields = append(fields, luaBoolField("floating", true))
		}
	}
	if len(fields) == 0 {
		return ""
	}
	return luaDispatcherTableCall("hl.dsp.window.cycle_next", fields...)
}

func dispatcherSwapNext(params string) string {
	switch strings.ToLower(strings.TrimSpace(params)) {
	case "prev", "previous", "b":
		return `hl.dsp.window.swap({ prev = true })`
	default:
		return `hl.dsp.window.swap({ next = true })`
	}
}

func dispatcherGroupActive(params string) string {
	switch strings.ToLower(strings.TrimSpace(params)) {
	case "f", "next", "forward":
		return `hl.dsp.group.next()`
	case "b", "prev", "previous", "backward":
		return `hl.dsp.group.prev()`
	}
	if isBareLuaNumber(params) {
		return luaDispatcherTableCall("hl.dsp.group.active", luaNumberOrStringField("index", params))
	}
	return ""
}

func dispatcherMoveGroupWindow(params string) string {
	switch strings.ToLower(strings.TrimSpace(params)) {
	case "b", "prev", "previous", "backward":
		return `hl.dsp.group.move_window({ forward = false })`
	default:
		return `hl.dsp.group.move_window({ forward = true })`
	}
}

func dispatcherCursorMove(params string) string {
	x, y, _, ok := xyParams(params)
	if !ok || !isBareLuaNumber(x) || !isBareLuaNumber(y) {
		return ""
	}
	return luaDispatcherTableCall("hl.dsp.cursor.move", luaNumberOrStringField("x", x), luaNumberOrStringField("y", y))
}

func dispatcherSignal(params string) string {
	signal, window := firstParam(params)
	if signal == "" || !isBareLuaNumber(signal) {
		return ""
	}
	fields := []luaField{luaNumberOrStringField("signal", signal)}
	if window != "" {
		fields = append(fields, luaStringField("window", window))
	}
	return luaDispatcherTableCall("hl.dsp.window.signal", fields...)
}

func dispatcherSignalWindow(params string) string {
	window, rest := firstParam(params)
	signal, _ := firstParam(rest)
	if signal == "" || !isBareLuaNumber(signal) {
		return ""
	}
	fields := []luaField{luaNumberOrStringField("signal", signal)}
	if window != "" {
		fields = append(fields, luaStringField("window", window))
	}
	return luaDispatcherTableCall("hl.dsp.window.signal", fields...)
}

func dispatcherTagWindow(params string) string {
	tag, window := firstParam(params)
	if tag == "" {
		return ""
	}
	fields := []luaField{luaStringField("tag", tag)}
	if window != "" {
		fields = append(fields, luaStringField("window", window))
	}
	return luaDispatcherTableCall("hl.dsp.window.tag", fields...)
}

// ok is false when no hl.dsp equivalent exists: legacy text is a Lua error at press time.
func luaActionStringFromHyprlangAction(action string) (string, bool) {
	dispatcher, params := splitHyprlandAction(action)
	switch dispatcher {
	case "spawn", "exec":
		if params == "" {
			return "", false
		}
		return fmt.Sprintf(`hl.dsp.exec_cmd(%s)`, strconv.Quote(params)), true
	case "execr":
		return fmt.Sprintf(`hl.dsp.exec_raw(%s)`, strconv.Quote(params)), true
	case "killactive":
		return `hl.dsp.window.close()`, true
	case "forcekillactive":
		return `hl.dsp.window.kill()`, true
	case "closewindow":
		if params == "" {
			return `hl.dsp.window.close()`, true
		}
		return luaDispatcherTableCall("hl.dsp.window.close", luaStringField("window", params)), true
	case "killwindow":
		if params == "" {
			return `hl.dsp.window.kill()`, true
		}
		return luaDispatcherTableCall("hl.dsp.window.kill", luaStringField("window", params)), true
	case "togglefloating":
		return dispatcherToggleTableCall("hl.dsp.window.float", "toggle"), true
	case "setfloating":
		return dispatcherToggleTableCall("hl.dsp.window.float", "on"), true
	case "settiled":
		return dispatcherToggleTableCall("hl.dsp.window.float", "off"), true
	case "fullscreen":
		if expr := dispatcherFullscreen(params); expr != "" {
			return expr, true
		}
	case "fullscreenstate":
		internal, rest := firstParam(params)
		client, _ := firstParam(rest)
		if internal != "" && client != "" {
			return luaDispatcherTableCall("hl.dsp.window.fullscreen_state",
				luaNumberOrStringField("internal", internal),
				luaNumberOrStringField("client", client),
			), true
		}
	case "pin":
		if params == "" {
			return `hl.dsp.window.pin()`, true
		}
		return dispatcherToggleTableCall("hl.dsp.window.pin", params), true
	case "pseudo":
		return dispatcherToggleTableCall("hl.dsp.window.pseudo", params), true
	case "centerwindow":
		return `hl.dsp.window.center()`, true
	case "resizewindow":
		return `hl.dsp.window.resize()`, true
	case "movewindow":
		if params == "" {
			return `hl.dsp.window.drag()`, true
		}
		if monitor, ok := strings.CutPrefix(params, "mon:"); ok {
			return luaDispatcherTableCall("hl.dsp.window.move", luaStringField("monitor", monitor)), true
		}
		return luaDispatcherTableCall("hl.dsp.window.move", luaStringField("direction", params)), true
	case "swapwindow":
		if params == "" {
			return "", false
		}
		return luaDispatcherTableCall("hl.dsp.window.swap", luaStringField("direction", params)), true
	case "swapnext":
		return dispatcherSwapNext(params), true
	case "resizeactive":
		if expr := dispatcherActiveMoveResize("hl.dsp.window.resize", params); expr != "" {
			return expr, true
		}
	case "moveactive":
		if expr := dispatcherActiveMoveResize("hl.dsp.window.move", params); expr != "" {
			return expr, true
		}
	case "resizewindowpixel":
		if expr := dispatcherWindowMoveResize("hl.dsp.window.resize", params); expr != "" {
			return expr, true
		}
	case "movewindowpixel":
		if expr := dispatcherWindowMoveResize("hl.dsp.window.move", params); expr != "" {
			return expr, true
		}
	case "workspace":
		if params == "" {
			return "", false
		}
		return luaDispatcherTableCall("hl.dsp.focus", luaStringField("workspace", params)), true
	case "focusworkspaceoncurrentmonitor":
		if params == "" {
			return "", false
		}
		return luaDispatcherTableCall("hl.dsp.focus", luaStringField("workspace", params), luaBoolField("on_current_monitor", true)), true
	case "movetoworkspace":
		if expr := dispatcherWorkspaceMove(params, nil); expr != "" {
			return expr, true
		}
	case "movetoworkspacesilent":
		follow := false
		if expr := dispatcherWorkspaceMove(params, &follow); expr != "" {
			return expr, true
		}
	case "togglespecialworkspace":
		if params == "" {
			return `hl.dsp.workspace.toggle_special()`, true
		}
		return fmt.Sprintf(`hl.dsp.workspace.toggle_special(%s)`, strconv.Quote(params)), true
	case "renameworkspace":
		workspace, name := firstParam(params)
		if workspace != "" {
			fields := []luaField{luaStringField("workspace", workspace)}
			if name != "" {
				fields = append(fields, luaStringField("name", name))
			}
			return luaDispatcherTableCall("hl.dsp.workspace.rename", fields...), true
		}
	case "movecurrentworkspacetomonitor":
		if params != "" {
			return luaDispatcherTableCall("hl.dsp.workspace.move", luaStringField("monitor", params)), true
		}
	case "moveworkspacetomonitor":
		workspace, monitor := firstParam(params)
		if workspace != "" && monitor != "" {
			return luaDispatcherTableCall("hl.dsp.workspace.move", luaStringField("workspace", workspace), luaStringField("monitor", monitor)), true
		}
	case "swapactiveworkspaces":
		monitor1, rest := firstParam(params)
		monitor2, _ := firstParam(rest)
		if monitor1 != "" && monitor2 != "" {
			return luaDispatcherTableCall("hl.dsp.workspace.swap_monitors", luaStringField("monitor1", monitor1), luaStringField("monitor2", monitor2)), true
		}
	case "movefocus":
		if params != "" {
			return luaDispatcherTableCall("hl.dsp.focus", luaStringField("direction", params)), true
		}
	case "focusmonitor":
		if params != "" {
			return luaDispatcherTableCall("hl.dsp.focus", luaStringField("monitor", params)), true
		}
	case "focuswindow":
		if params != "" {
			return luaDispatcherTableCall("hl.dsp.focus", luaStringField("window", params)), true
		}
	case "focuscurrentorlast":
		return `hl.dsp.focus({ last = true })`, true
	case "focusurgentorlast":
		return `hl.dsp.focus({ urgent_or_last = true })`, true
	case "cyclenext":
		if expr := dispatcherCycleNext(params); expr != "" {
			return expr, true
		}
	case "layoutmsg":
		if params != "" {
			return fmt.Sprintf(`hl.dsp.layout(%s)`, strconv.Quote(params)), true
		}
	case "splitratio":
		if expr := dispatcherSplitRatio(params); expr != "" {
			return expr, true
		}
	case "alterzorder":
		mode, window := firstParam(params)
		if mode != "" {
			fields := []luaField{luaStringField("mode", mode)}
			if window != "" {
				fields = append(fields, luaStringField("window", window))
			}
			return luaDispatcherTableCall("hl.dsp.window.alter_zorder", fields...), true
		}
	case "setprop":
		window, rest := firstParam(params)
		prop, value := firstParam(rest)
		if window != "" && prop != "" && value != "" {
			return luaDispatcherTableCall("hl.dsp.window.set_prop",
				luaStringField("window", window),
				luaStringField("prop", prop),
				luaStringField("value", value),
			), true
		}
	case "bringactivetotop":
		return `hl.dsp.window.bring_to_top()`, true
	case "toggleswallow":
		return `hl.dsp.window.toggle_swallow()`, true
	case "signal":
		if expr := dispatcherSignal(params); expr != "" {
			return expr, true
		}
	case "signalwindow":
		if expr := dispatcherSignalWindow(params); expr != "" {
			return expr, true
		}
	case "tagwindow":
		if expr := dispatcherTagWindow(params); expr != "" {
			return expr, true
		}
	case "dpms":
		dpmsAction, monitor := firstParam(params)
		switch dpmsAction {
		case "":
			return `hl.dsp.dpms({})`, true
		case "on":
			dpmsAction = "enable"
		case "off":
			dpmsAction = "disable"
		}
		fields := []luaField{luaStringField("action", dpmsAction)}
		if monitor != "" {
			fields = append(fields, luaStringField("monitor", monitor))
		}
		return luaDispatcherTableCall("hl.dsp.dpms", fields...), true
	case "exit":
		return `hl.dsp.exit()`, true
	case "submap":
		return fmt.Sprintf(`hl.dsp.submap(%s)`, strconv.Quote(params)), true
	case "global":
		return fmt.Sprintf(`hl.dsp.global(%s)`, strconv.Quote(params)), true
	case "event":
		return fmt.Sprintf(`hl.dsp.event(%s)`, strconv.Quote(params)), true
	case "pass":
		// hl.dsp.pass requires a window selector.
		if params == "" {
			return "", false
		}
		return luaDispatcherTableCall("hl.dsp.pass", luaStringField("window", params)), true
	case "sendshortcut":
		mod, rest := firstParam(params)
		key, window := firstParam(rest)
		if mod != "" && key != "" {
			fields := []luaField{luaStringField("mods", mod), luaStringField("key", key)}
			if window != "" {
				fields = append(fields, luaStringField("window", window))
			}
			return luaDispatcherTableCall("hl.dsp.send_shortcut", fields...), true
		}
	case "sendkeystate":
		mod, rest := firstParam(params)
		key, rest := firstParam(rest)
		state, window := firstParam(rest)
		if mod != "" && key != "" && state != "" {
			fields := []luaField{luaStringField("mods", mod), luaStringField("key", key), luaStringField("state", state)}
			if window != "" {
				fields = append(fields, luaStringField("window", window))
			}
			return luaDispatcherTableCall("hl.dsp.send_key_state", fields...), true
		}
	case "movecursortocorner":
		if params != "" && isBareLuaNumber(params) {
			return luaDispatcherTableCall("hl.dsp.cursor.move_to_corner", luaNumberOrStringField("corner", params)), true
		}
	case "movecursor":
		if expr := dispatcherCursorMove(params); expr != "" {
			return expr, true
		}
	case "togglegroup":
		return `hl.dsp.group.toggle()`, true
	case "changegroupactive":
		if expr := dispatcherGroupActive(params); expr != "" {
			return expr, true
		}
	case "movegroupwindow":
		return dispatcherMoveGroupWindow(params), true
	case "moveintogroup":
		if params != "" {
			return luaDispatcherTableCall("hl.dsp.window.move", luaStringField("into_group", params)), true
		}
	case "moveintoorcreategroup":
		if params != "" {
			return luaDispatcherTableCall("hl.dsp.window.move", luaStringField("into_or_create_group", params)), true
		}
	case "moveoutofgroup":
		if params != "" {
			return luaDispatcherTableCall("hl.dsp.window.move", luaStringField("out_of_group", params)), true
		}
		return luaDispatcherTableCall("hl.dsp.window.move", luaBoolField("out_of_group", true)), true
	case "movewindoworgroup":
		if params != "" {
			return luaDispatcherTableCall("hl.dsp.window.move", luaStringField("direction", params), luaBoolField("group_aware", true)), true
		}
	case "lockgroups":
		// 0.57 locks only the active group without all; 0.56 ignores the field
		return luaDispatcherTableCall("hl.dsp.group.lock", luaBoolField("all", true), luaStringField("action", luaToggleActionValue(params))), true
	case "lockactivegroup":
		lockArg, window := firstParam(params)
		if window != "" {
			return luaDispatcherTableCall("hl.dsp.group.lock", luaStringField("action", luaToggleActionValue(lockArg)), luaStringField("window", window)), true
		}
		// lock_active is deprecated on 0.57 but still the only active-group lock on 0.56
		return dispatcherToggleTableCall("hl.dsp.group.lock_active", params), true
	case "denywindowfromgroup":
		return dispatcherToggleTableCall("hl.dsp.window.deny_from_group", params), true
	case "forcerendererreload":
		return `hl.dsp.force_renderer_reload()`, true
	case "reloadconfig":
		// hl.dsp.reload_config is 0.57-only; calling nil on 0.55/0.56 aborts loading the file
		return `hl.dsp.exec_cmd("hyprctl reload")`, true
	case "forceidle":
		if params != "" && isBareLuaNumber(params) {
			return fmt.Sprintf(`hl.dsp.force_idle(%s)`, params), true
		}
	case "releaseinputcapture":
		return `hl.dsp.release_input_capture()`, true
	}
	return "", false
}

// luaExprToInternalAction converts a parsed Lua bind expression back into
// "dispatcher params" text. isRawLua reports that expr matched no known hl.*
// shape and must be re-emitted verbatim as Lua on write-back.
func luaExprToInternalAction(expr string) (action string, isRawLua bool) {
	d, p := luaExprToDispatcherParams(expr)
	if d == expr && p == "" {
		return expr, true
	}
	action = d
	if p != "" {
		action = d + " " + p
	}
	// An unmappable legacy hyprctl wrapper stays verbatim so a rewrite never drops the bind.
	if _, ok := luaActionStringFromHyprlangAction(action); !ok {
		return expr, true
	}
	return action, false
}

func luaBindOptions(bind *hyprlandOverrideBind) []string {
	var opts []string
	for _, fo := range hyprlandBindFlagOptions {
		if strings.IndexByte(bind.Flags, fo.flag) >= 0 {
			opts = append(opts, fo.option+" = true")
		}
	}
	if bind.Device != "" && strings.Contains(bind.Flags, "k") {
		opts = append(opts, "device = "+bind.Device)
	}
	if bind.Description != "" {
		opts = append(opts, fmt.Sprintf("description = %s", strconv.Quote(bind.Description)))
	}
	return opts
}

func writeLuaBindLine(sb *strings.Builder, bind *hyprlandOverrideBind) {
	key := strconv.Quote(formatLuaBindKey(bind.Key))
	if bind.Unbind {
		fmt.Fprintf(sb, `hl.unbind(%s)`, key)
		sb.WriteByte('\n')
		return
	}
	expr := bind.Action
	if !bind.RawLuaAction {
		mapped, ok := luaActionStringFromHyprlangAction(bind.Action)
		if !ok {
			// Commented out: the bind would error at press time, but the user's action survives.
			fmt.Fprintf(sb, "-- unsupported action for %s: %s\n", key, strings.NewReplacer("\r", " ", "\n", " ").Replace(bind.Action))
			return
		}
		expr = mapped
	}
	opts := luaBindOptions(bind)
	fmt.Fprintf(sb, `hl.unbind(%s)`, key)
	sb.WriteByte('\n')
	if len(opts) > 0 {
		fmt.Fprintf(sb, `hl.bind(%s, %s, { %s })`, key, expr, strings.Join(opts, ", "))
	} else {
		fmt.Fprintf(sb, `hl.bind(%s, %s)`, key, expr)
	}
	sb.WriteByte('\n')
}

func parseLuaBindOverrideLine(line string) (*hyprlandOverrideBind, bool) {
	line = strings.TrimSpace(line)
	if line == "" || strings.HasPrefix(line, "--") {
		return nil, false
	}
	kbc, actionExpr, optSuffix, ok := parseLuaBindInvocation(line)
	if !ok {
		return nil, false
	}
	internalKey := luaKeyComboToInternalKey(kbc)

	action, isRawLua := luaExprToInternalAction(actionExpr)
	description := luaBindOptDescription(optSuffix)
	if description == "" {
		description = luaLineTrailingComment(line)
	}
	return &hyprlandOverrideBind{
		Key:          internalKey,
		Action:       action,
		Description:  description,
		Flags:        luaBindOptFlags(optSuffix),
		Device:       luaBindOptDevice(optSuffix),
		RawLuaAction: isRawLua,
	}, true
}

func parseLuaUnbindLine(line string) (string, bool) {
	line = strings.TrimSpace(line)
	if !strings.HasPrefix(line, "hl.unbind") {
		return "", false
	}
	rest := strings.TrimSpace(line[len("hl.unbind"):])
	if !strings.HasPrefix(rest, "(") {
		return "", false
	}
	rest = rest[1:]
	combo, _, ok := parseLuaStringLiteral(rest, 0)
	if !ok {
		return "", false
	}
	return luaKeyComboToInternalKey(combo), true
}

func luaKeyComboToInternalKey(combo string) string {
	parts := strings.Fields(strings.ReplaceAll(strings.ReplaceAll(combo, "+", " "), "  ", " "))
	for i, part := range parts {
		if canonical, ok := hyprlandScrollToCanonical(part); ok {
			parts[i] = canonical
		}
	}
	return strings.Join(parts, "+")
}

func readLuaOverride(path string) (map[string]*hyprlandOverrideBind, error) {
	binds := make(map[string]*hyprlandOverrideBind)
	data, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return binds, nil
	}
	if err != nil {
		return nil, err
	}
	lines := expandLuaConfigLines(strings.Split(string(data), "\n"))
	pendingUnbinds := make(map[string]string)
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "--") {
			continue
		}
		if key, ok := parseLuaUnbindLine(line); ok {
			pendingUnbinds[hyprlandOverrideMapKey(key)] = canonicalHyprlandOverrideKey(key)
			continue
		}
		if kb, ok := parseLuaBindOverrideLine(line); ok {
			kb.Key = canonicalHyprlandOverrideKey(kb.Key)
			normalizedKey := hyprlandOverrideMapKey(kb.Key)
			binds[normalizedKey] = kb
			delete(pendingUnbinds, normalizedKey)
		}
	}
	for normKey, origKey := range pendingUnbinds {
		binds[normKey] = &hyprlandOverrideBind{Key: origKey, Unbind: true}
	}
	return binds, nil
}
