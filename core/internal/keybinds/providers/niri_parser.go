package providers

import (
	"fmt"
	"github.com/duxlabs-dev/dux-shell/core/internal/configfrag"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/sblinch/kdl-go"
	"github.com/sblinch/kdl-go/document"
)

type NiriKeyBinding struct {
	Mods            []string
	Key             string
	Action          string
	Args            []string
	Description     string
	HideOnOverlay   bool
	CooldownMs      int
	AllowWhenLocked bool
	AllowInhibiting *bool
	Repeat          *bool
	Source          string
}

type NiriSection struct {
	Name     string
	Keybinds []NiriKeyBinding
	Children []NiriSection
}

type NiriParser struct {
	configDir          string
	modKey             string
	modKeyNested       string
	processedFiles     map[string]bool
	bindMap            map[string]*NiriKeyBinding
	bindOrder          []string
	currentSource      string
	dmsBindsIncluded   bool
	dmsBindsExists     bool
	includeCount       int
	dmsIncludePos      int
	bindsBeforeDMS     int
	bindsAfterDMS      int
	dmsBindKeys        map[string]bool
	configBindKeys     map[string]bool
	dmsProcessed       bool
	dmsBindMap         map[string]*NiriKeyBinding
	conflictingConfigs map[string]*NiriKeyBinding
}

func parseKDL(data []byte) (*document.Document, error) {
	return kdl.Parse(strings.NewReader(normalizeKDLBraces(quoteLeadingUnderscoreIdents(string(data)))))
}

func normalizeKDLBraces(input string) string {
	var sb strings.Builder
	sb.Grow(len(input))

	var prev byte
	n := len(input)
	for i := 0; i < n; {
		c := input[i]

		switch {
		case c == '"':
			end := findStringEnd(input, i)
			sb.WriteString(input[i:end])
			prev = '"'
			i = end
		case c == '/' && i+1 < n && input[i+1] == '/':
			end := findLineCommentEnd(input, i)
			sb.WriteString(input[i:end])
			prev = '\n'
			i = end
		case c == '/' && i+1 < n && input[i+1] == '*':
			end := findBlockCommentEnd(input, i)
			sb.WriteString(input[i:end])
			prev = '/'
			i = end
		case c == '{' && prev != 0 && !isBraceAdjacentSpace(prev):
			sb.WriteByte(' ')
			sb.WriteByte(c)
			prev = c
			i++
		default:
			sb.WriteByte(c)
			prev = c
			i++
		}
	}

	return sb.String()
}

// quoteLeadingUnderscoreIdents wraps bare KDL identifiers that begin with '_'
// in double quotes. kdl-go rejects '_' as the first character of a bare
// identifier (e.g. the common `_JAVA_AWT_WM_NONREPARENTING "1"` environment
// node), even though niri's own parser and the KDL spec accept it — so without
// this the whole config fails to parse and no keybinds load. Quoting lets
// kdl-go parse it; this is safe because the niri parser only dispatches on
// fixed node/section names (binds, recent-windows, include, ...) that never
// start with '_', so re-quoting such a name cannot change what DMS reads.
// Underscores elsewhere in an identifier (XDG_CURRENT_DESKTOP) are left
// untouched, and underscores inside strings or comments are skipped. Only a
// leading '_' is handled; other start characters kdl-go over-rejects (e.g. '.'
// or '?') do not occur in niri configs.
func quoteLeadingUnderscoreIdents(input string) string {
	var sb strings.Builder
	sb.Grow(len(input))

	var prev byte
	n := len(input)
	for i := 0; i < n; {
		c := input[i]

		switch {
		case c == '"':
			end := findStringEnd(input, i)
			sb.WriteString(input[i:end])
			prev = '"'
			i = end
		case c == '/' && i+1 < n && input[i+1] == '/':
			end := findLineCommentEnd(input, i)
			sb.WriteString(input[i:end])
			prev = '\n'
			i = end
		case c == '/' && i+1 < n && input[i+1] == '*':
			end := findBlockCommentEnd(input, i)
			sb.WriteString(input[i:end])
			prev = ' '
			i = end
		case c == '/' && i+1 < n && input[i+1] == '-':
			// KDL slashdash: /- comments out the next node/value. Keep the
			// marker but treat what follows as a fresh token start, so a
			// slashdashed leading-underscore node (e.g. `/-_FOO "1"`) still
			// gets quoted instead of crashing kdl-go.
			sb.WriteByte('/')
			sb.WriteByte('-')
			prev = ' '
			i += 2
		case c == '_' && isIdentBoundary(prev):
			end := scanBareIdent(input, i)
			sb.WriteByte('"')
			sb.WriteString(input[i:end])
			sb.WriteByte('"')
			prev = '"'
			i = end
		default:
			sb.WriteByte(c)
			prev = c
			i++
		}
	}

	return sb.String()
}

// isIdentBoundary reports whether the previously emitted byte ends a token, so
// that a following '_' starts a fresh bare identifier rather than sitting in
// the middle of one.
func isIdentBoundary(prev byte) bool {
	switch prev {
	case 0, ' ', '\t', '\n', '\r', '{', '}', ';', '=', '(', ')', ',':
		return true
	}
	return false
}

// scanBareIdent returns the index just past the bare identifier starting at
// start, stopping at whitespace or any KDL delimiter.
func scanBareIdent(s string, start int) int {
	n := len(s)
	for i := start; i < n; i++ {
		switch s[i] {
		case ' ', '\t', '\n', '\r', '"', '{', '}', '(', ')', ';', '=', ',', '/', '\\', '<', '>', '[', ']':
			return i
		}
	}
	return n
}

func findStringEnd(s string, start int) int {
	n := len(s)
	for i := start + 1; i < n; {
		switch s[i] {
		case '\\':
			i += 2
		case '"':
			return i + 1
		default:
			i++
		}
	}
	return n
}

func findLineCommentEnd(s string, start int) int {
	for i := start + 2; i < len(s); i++ {
		if s[i] == '\n' {
			return i
		}
	}
	return len(s)
}

func findBlockCommentEnd(s string, start int) int {
	n := len(s)
	depth := 1
	for i := start + 2; i < n && depth > 0; {
		switch {
		case i+1 < n && s[i] == '/' && s[i+1] == '*':
			depth++
			i += 2
		case i+1 < n && s[i] == '*' && s[i+1] == '/':
			depth--
			i += 2
			if depth == 0 {
				return i
			}
		default:
			i++
		}
	}
	return n
}

func isBraceAdjacentSpace(b byte) bool {
	switch b {
	case ' ', '\t', '\n', '\r', '{':
		return true
	}
	return false
}

func NewNiriParser(configDir string) *NiriParser {
	return &NiriParser{
		configDir:          configDir,
		processedFiles:     make(map[string]bool),
		bindMap:            make(map[string]*NiriKeyBinding),
		bindOrder:          []string{},
		currentSource:      "",
		dmsIncludePos:      -1,
		dmsBindKeys:        make(map[string]bool),
		configBindKeys:     make(map[string]bool),
		dmsBindMap:         make(map[string]*NiriKeyBinding),
		conflictingConfigs: make(map[string]*NiriKeyBinding),
	}
}

func normalizeNiriBindKey(key string) string {
	parts := strings.Split(key, "+")
	for i := range parts {
		parts[i] = strings.ToLower(strings.TrimSpace(parts[i]))
	}
	return strings.Join(parts, "+")
}

func (p *NiriParser) Parse() (*NiriSection, error) {
	dmsBindsPath := filepath.Join(p.configDir, "dms", "binds.kdl")
	if _, err := os.Stat(dmsBindsPath); err == nil {
		p.dmsBindsExists = true
	}

	configPath := filepath.Join(p.configDir, "config.kdl")
	section, err := p.parseFile(configPath, "")
	if err != nil {
		return nil, err
	}

	if p.dmsBindsExists && !p.dmsProcessed {
		p.parseDMSBindsDirectly(dmsBindsPath, section)
	}

	section.Keybinds = p.finalizeBinds()
	return section, nil
}

func (p *NiriParser) parseDMSBindsDirectly(dmsBindsPath string, section *NiriSection) {
	data, err := os.ReadFile(dmsBindsPath)
	if err != nil {
		return
	}

	doc, err := parseKDL(data)
	if err != nil {
		return
	}

	prevSource := p.currentSource
	p.currentSource = dmsBindsPath
	baseDir := filepath.Dir(dmsBindsPath)
	p.processNodes(doc.Nodes, section, baseDir)
	p.currentSource = prevSource
	p.dmsProcessed = true
}

func (p *NiriParser) finalizeBinds() []NiriKeyBinding {
	binds := make([]NiriKeyBinding, 0, len(p.bindOrder))
	for _, key := range p.bindOrder {
		if kb, ok := p.bindMap[key]; ok {
			binds = append(binds, *kb)
		}
	}
	return binds
}

func (p *NiriParser) addBind(kb *NiriKeyBinding) {
	key := p.formatBindKey(kb)
	normalizedKey := normalizeNiriBindKey(key)
	isDMSBind := strings.Contains(kb.Source, "dms/binds.kdl")

	if isDMSBind {
		p.dmsBindKeys[normalizedKey] = true
		p.dmsBindMap[normalizedKey] = kb
	} else if p.dmsBindKeys[normalizedKey] {
		p.bindsAfterDMS++
		p.conflictingConfigs[normalizedKey] = kb
		p.configBindKeys[normalizedKey] = true
		return
	} else {
		p.configBindKeys[normalizedKey] = true
	}

	if _, exists := p.bindMap[normalizedKey]; !exists {
		p.bindOrder = append(p.bindOrder, normalizedKey)
	}
	p.bindMap[normalizedKey] = kb
}

func (p *NiriParser) formatBindKey(kb *NiriKeyBinding) string {
	parts := make([]string, 0, len(kb.Mods)+1)
	parts = append(parts, kb.Mods...)
	parts = append(parts, kb.Key)
	return strings.Join(parts, "+")
}

func (p *NiriParser) parseFile(filePath, sectionName string) (*NiriSection, error) {
	absPath, err := filepath.Abs(filePath)
	if err != nil {
		return nil, fmt.Errorf("failed to resolve path %s: %w", filePath, err)
	}

	if p.processedFiles[absPath] {
		return &NiriSection{Name: sectionName}, nil
	}
	p.processedFiles[absPath] = true

	data, err := os.ReadFile(absPath)
	if err != nil {
		return nil, fmt.Errorf("failed to read %s: %w", absPath, err)
	}

	doc, err := parseKDL(data)
	if err != nil {
		return nil, fmt.Errorf("failed to parse KDL in %s: %w", absPath, err)
	}

	section := &NiriSection{
		Name: sectionName,
	}

	prevSource := p.currentSource
	p.currentSource = absPath
	baseDir := filepath.Dir(absPath)
	p.processNodes(doc.Nodes, section, baseDir)
	p.currentSource = prevSource

	return section, nil
}

func (p *NiriParser) processNodes(nodes []*document.Node, section *NiriSection, baseDir string) {
	for _, node := range nodes {
		name := node.Name.String()

		switch name {
		case "include":
			p.handleInclude(node, section, baseDir)
		case "input":
			p.handleInput(node)
		case "binds":
			p.extractBinds(node, "")
		case "recent-windows":
			p.handleRecentWindows(node)
		}
	}
}

func (p *NiriParser) handleInput(node *document.Node) {
	for _, child := range node.Children {
		if len(child.Arguments) == 0 {
			continue
		}
		value := strings.Trim(strings.TrimSpace(child.Arguments[0].String()), "\"")
		if value == "" {
			continue
		}
		switch child.Name.String() {
		case "mod-key":
			p.modKey = value
		case "mod-key-nested":
			p.modKeyNested = value
		}
	}
}

func (p *NiriParser) handleInclude(node *document.Node, section *NiriSection, baseDir string) {
	if len(node.Arguments) == 0 {
		return
	}

	includePath := strings.Trim(node.Arguments[0].String(), "\"")
	fullPath := filepath.Join(baseDir, includePath)
	if filepath.IsAbs(includePath) {
		fullPath = includePath
	}
	isDMSInclude := strings.HasSuffix(fullPath, "/dms/binds.kdl")

	p.includeCount++
	if isDMSInclude {
		p.dmsBindsIncluded = true
		p.dmsIncludePos = p.includeCount
		p.bindsBeforeDMS = len(p.bindMap)
		p.dmsProcessed = true
	}

	includedSection, err := p.parseFile(fullPath, "")
	if err != nil {
		return
	}

	section.Children = append(section.Children, includedSection.Children...)
}

func (p *NiriParser) HasDMSBindsIncluded() bool {
	return p.dmsBindsIncluded
}

func (p *NiriParser) handleRecentWindows(node *document.Node) {
	if node.Children == nil {
		return
	}

	for _, child := range node.Children {
		if child.Name.String() != "binds" {
			continue
		}
		p.extractBinds(child, "Alt-Tab")
	}
}

func (p *NiriParser) extractBinds(node *document.Node, subcategory string) {
	if node.Children == nil {
		return
	}

	for _, child := range node.Children {
		kb := p.parseKeybindNode(child, subcategory)
		if kb == nil {
			continue
		}
		p.addBind(kb)
	}
}

func (p *NiriParser) parseKeybindNode(node *document.Node, _ string) *NiriKeyBinding {
	keyCombo := node.Name.String()
	if keyCombo == "" {
		return nil
	}

	mods, key := p.parseKeyCombo(keyCombo)

	var action string
	var args []string
	if len(node.Children) > 0 {
		actionNode := node.Children[0]
		action = actionNode.Name.String()
		for _, arg := range actionNode.Arguments {
			args = append(args, arg.ValueString())
		}
		if actionNode.Properties != nil {
			for _, propName := range []string{"focus", "show-pointer", "write-to-disk", "skip-confirmation", "delay-ms", "filter", "scope"} {
				if val, ok := actionNode.Properties.Get(propName); ok {
					args = append(args, propName+"="+val.String())
				}
			}
		}
	}

	var description string
	var hideOnOverlay bool
	var cooldownMs int
	var allowWhenLocked bool
	var allowInhibiting *bool
	var repeat *bool
	if node.Properties != nil {
		if val, ok := node.Properties.Get("hotkey-overlay-title"); ok {
			switch val.ValueString() {
			case "null", "":
				hideOnOverlay = true
			default:
				description = val.ValueString()
			}
		}
		if val, ok := node.Properties.Get("cooldown-ms"); ok {
			cooldownMs, _ = strconv.Atoi(val.String())
		}
		if val, ok := node.Properties.Get("allow-when-locked"); ok {
			allowWhenLocked = val.String() == "true"
		}
		if val, ok := node.Properties.Get("allow-inhibiting"); ok {
			v := val.String() == "true"
			allowInhibiting = &v
		}
		if val, ok := node.Properties.Get("repeat"); ok {
			v := val.String() == "true"
			repeat = &v
		}
	}

	return &NiriKeyBinding{
		Mods:            mods,
		Key:             key,
		Action:          action,
		Args:            args,
		Description:     description,
		HideOnOverlay:   hideOnOverlay,
		CooldownMs:      cooldownMs,
		AllowWhenLocked: allowWhenLocked,
		AllowInhibiting: allowInhibiting,
		Repeat:          repeat,
		Source:          p.currentSource,
	}
}

func (p *NiriParser) parseKeyCombo(combo string) ([]string, string) {
	parts := strings.Split(combo, "+")

	switch len(parts) {
	case 0:
		return nil, combo
	case 1:
		return nil, parts[0]
	default:
		return parts[:len(parts)-1], parts[len(parts)-1]
	}
}

type NiriParseResult struct {
	Section            *NiriSection
	ModKey             string
	ModKeyNested       string
	DMSBindsIncluded   bool
	DMSStatus          *configfrag.Status
	ConflictingConfigs map[string]*NiriKeyBinding
}

var niriBindsMessages = configfrag.Messages{
	Missing:     "dms/binds.kdl does not exist",
	NotIncluded: "dms/binds.kdl is not included in config.kdl",
	Overridden:  "Some DMS binds may be overridden by config binds",
	Active:      "DMS binds are active",
}

func (p *NiriParser) buildDMSStatus() *configfrag.Status {
	scan := configfrag.IncludeScan{Count: p.includeCount, DMSPosition: p.dmsIncludePos, DMSSeen: p.dmsBindsIncluded}
	status := configfrag.BuildStatus(scan, p.dmsBindsExists, p.bindsAfterDMS, niriBindsMessages)
	return &status
}

func ParseNiriKeys(configDir string) (*NiriParseResult, error) {
	parser := NewNiriParser(configDir)
	section, err := parser.Parse()
	if err != nil {
		return nil, err
	}
	return &NiriParseResult{
		Section:            section,
		ModKey:             parser.modKey,
		ModKeyNested:       parser.modKeyNested,
		DMSBindsIncluded:   parser.HasDMSBindsIncluded(),
		DMSStatus:          parser.buildDMSStatus(),
		ConflictingConfigs: parser.conflictingConfigs,
	}, nil
}
