package providers

import (
	"fmt"
	"github.com/duxlabs-dev/dux-shell/core/internal/configfrag"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"

	"github.com/sblinch/kdl-go"
	"github.com/sblinch/kdl-go/document"

	"github.com/duxlabs-dev/dux-shell/core/internal/windowrules"
)

type NiriMatch struct {
	AppID              string
	Title              string
	IsFloating         *bool
	IsActive           *bool
	IsFocused          *bool
	IsActiveInColumn   *bool
	IsWindowCastTarget *bool
	IsUrgent           *bool
	AtStartup          *bool
}

type NiriWindowRule struct {
	MatchAppID              string
	MatchTitle              string
	MatchIsFloating         *bool
	MatchIsActive           *bool
	MatchIsFocused          *bool
	MatchIsActiveInColumn   *bool
	MatchIsWindowCastTarget *bool
	MatchIsUrgent           *bool
	MatchAtStartup          *bool
	Matches                 []NiriMatch
	Excludes                []NiriMatch
	Opacity                 *float64
	OpenFloating            *bool
	OpenMaximized           *bool
	OpenMaximizedToEdges    *bool
	OpenFullscreen          *bool
	OpenFocused             *bool
	OpenOnOutput            string
	OpenOnWorkspace         string
	DefaultColumnWidth      string
	DefaultWindowHeight     string
	VariableRefreshRate     *bool
	BlockOutFrom            string
	DefaultColumnDisplay    string
	ScrollFactor            *float64
	CornerRadius            *int
	ClipToGeometry          *bool
	TiledState              *bool
	MinWidth                *int
	MaxWidth                *int
	MinHeight               *int
	MaxHeight               *int
	BorderColor             string
	FocusRingColor          string
	FocusRingOff            *bool
	BorderOff               *bool
	DrawBorderWithBg        *bool
	BgBlur                  *bool
	BgXray                  *bool
	BgNoise                 *float64
	BgSaturation            *float64
	DefaultFloatingX        *int
	DefaultFloatingY        *int
	DefaultFloatingRelative string
	Source                  string
}

type NiriRulesParser struct {
	configDir        string
	processedFiles   map[string]bool
	rules            []NiriWindowRule
	currentSource    string
	dmsRulesIncluded bool
	dmsRulesExists   bool
	includeCount     int
	dmsIncludePos    int
	rulesAfterDMS    int
	dmsProcessed     bool
}

func NewNiriRulesParser(configDir string) *NiriRulesParser {
	return &NiriRulesParser{
		configDir:      configDir,
		processedFiles: make(map[string]bool),
		rules:          []NiriWindowRule{},
		dmsIncludePos:  -1,
	}
}

func (p *NiriRulesParser) Parse() ([]NiriWindowRule, error) {
	dmsRulesPath := filepath.Join(p.configDir, "dms", "windowrules.kdl")
	if _, err := os.Stat(dmsRulesPath); err == nil {
		p.dmsRulesExists = true
	}

	configPath := filepath.Join(p.configDir, "config.kdl")
	if err := p.parseFile(configPath); err != nil {
		return nil, err
	}

	if p.dmsRulesExists && !p.dmsProcessed {
		p.parseDMSRulesDirectly(dmsRulesPath)
	}

	return p.rules, nil
}

func (p *NiriRulesParser) parseDMSRulesDirectly(dmsRulesPath string) {
	data, err := os.ReadFile(dmsRulesPath)
	if err != nil {
		return
	}

	doc, err := kdl.Parse(strings.NewReader(string(data)))
	if err != nil {
		return
	}

	prevSource := p.currentSource
	p.currentSource = dmsRulesPath
	p.processNodes(doc.Nodes, filepath.Dir(dmsRulesPath))
	p.currentSource = prevSource
	p.dmsProcessed = true
}

func (p *NiriRulesParser) parseFile(filePath string) error {
	absPath, err := filepath.Abs(filePath)
	if err != nil {
		return err
	}

	if p.processedFiles[absPath] {
		return nil
	}
	p.processedFiles[absPath] = true

	data, err := os.ReadFile(absPath)
	if err != nil {
		return nil
	}

	doc, err := kdl.Parse(strings.NewReader(string(data)))
	if err != nil {
		return err
	}

	prevSource := p.currentSource
	p.currentSource = absPath
	baseDir := filepath.Dir(absPath)
	p.processNodes(doc.Nodes, baseDir)
	p.currentSource = prevSource

	return nil
}

func (p *NiriRulesParser) processNodes(nodes []*document.Node, baseDir string) {
	for _, node := range nodes {
		name := node.Name.String()

		switch name {
		case "include":
			p.handleInclude(node, baseDir)
		case "window-rule":
			p.parseWindowRuleNode(node)
		}
	}
}

func (p *NiriRulesParser) handleInclude(node *document.Node, baseDir string) {
	if len(node.Arguments) == 0 {
		return
	}

	includePath := strings.Trim(node.Arguments[0].String(), "\"")
	fullPath := filepath.Join(baseDir, includePath)
	if filepath.IsAbs(includePath) {
		fullPath = includePath
	}
	isDMSInclude := strings.HasSuffix(fullPath, "/dms/windowrules.kdl")

	p.includeCount++
	if isDMSInclude {
		p.dmsRulesIncluded = true
		p.dmsIncludePos = p.includeCount
		p.dmsProcessed = true
	}

	_ = p.parseFile(fullPath)
}

func (p *NiriRulesParser) parseWindowRuleNode(node *document.Node) {
	if node.Children == nil {
		return
	}

	rule := NiriWindowRule{
		Source: p.currentSource,
	}

	for _, child := range node.Children {
		childName := child.Name.String()

		switch childName {
		case "match":
			rule.Matches = append(rule.Matches, p.parseMatchNode(child))
		case "exclude":
			rule.Excludes = append(rule.Excludes, p.parseMatchNode(child))
		case "opacity":
			if len(child.Arguments) > 0 {
				val := child.Arguments[0].ResolvedValue()
				if f, ok := val.(float64); ok {
					rule.Opacity = &f
				}
			}
		case "open-floating":
			b := p.parseBoolArg(child)
			rule.OpenFloating = &b
		case "open-maximized":
			b := p.parseBoolArg(child)
			rule.OpenMaximized = &b
		case "open-maximized-to-edges":
			b := p.parseBoolArg(child)
			rule.OpenMaximizedToEdges = &b
		case "open-fullscreen":
			b := p.parseBoolArg(child)
			rule.OpenFullscreen = &b
		case "open-focused":
			b := p.parseBoolArg(child)
			rule.OpenFocused = &b
		case "open-on-output":
			if len(child.Arguments) > 0 {
				rule.OpenOnOutput = child.Arguments[0].ValueString()
			}
		case "open-on-workspace":
			if len(child.Arguments) > 0 {
				rule.OpenOnWorkspace = child.Arguments[0].ValueString()
			}
		case "default-column-width":
			rule.DefaultColumnWidth = p.parseSizeNode(child)
		case "default-window-height":
			rule.DefaultWindowHeight = p.parseSizeNode(child)
		case "variable-refresh-rate":
			b := p.parseBoolArg(child)
			rule.VariableRefreshRate = &b
		case "block-out-from":
			if len(child.Arguments) > 0 {
				rule.BlockOutFrom = child.Arguments[0].ValueString()
			}
		case "default-column-display":
			if len(child.Arguments) > 0 {
				rule.DefaultColumnDisplay = child.Arguments[0].ValueString()
			}
		case "scroll-factor":
			if len(child.Arguments) > 0 {
				val := child.Arguments[0].ResolvedValue()
				if f, ok := val.(float64); ok {
					rule.ScrollFactor = &f
				}
			}
		case "geometry-corner-radius":
			if len(child.Arguments) > 0 {
				val := child.Arguments[0].ResolvedValue()
				if i, ok := val.(int64); ok {
					intVal := int(i)
					rule.CornerRadius = &intVal
				}
			}
		case "clip-to-geometry":
			b := p.parseBoolArg(child)
			rule.ClipToGeometry = &b
		case "tiled-state":
			b := p.parseBoolArg(child)
			rule.TiledState = &b
		case "min-width":
			if len(child.Arguments) > 0 {
				val := child.Arguments[0].ResolvedValue()
				if i, ok := val.(int64); ok {
					intVal := int(i)
					rule.MinWidth = &intVal
				}
			}
		case "max-width":
			if len(child.Arguments) > 0 {
				val := child.Arguments[0].ResolvedValue()
				if i, ok := val.(int64); ok {
					intVal := int(i)
					rule.MaxWidth = &intVal
				}
			}
		case "min-height":
			if len(child.Arguments) > 0 {
				val := child.Arguments[0].ResolvedValue()
				if i, ok := val.(int64); ok {
					intVal := int(i)
					rule.MinHeight = &intVal
				}
			}
		case "max-height":
			if len(child.Arguments) > 0 {
				val := child.Arguments[0].ResolvedValue()
				if i, ok := val.(int64); ok {
					intVal := int(i)
					rule.MaxHeight = &intVal
				}
			}
		case "border":
			p.parseBorderNode(child, &rule)
		case "focus-ring":
			p.parseFocusRingNode(child, &rule)
		case "draw-border-with-background":
			b := p.parseBoolArg(child)
			rule.DrawBorderWithBg = &b
		case "background-effect":
			p.parseBackgroundEffectNode(child, &rule)
		case "default-floating-position":
			p.parseFloatingPositionNode(child, &rule)
		}
	}

	if len(rule.Matches) > 0 {
		first := rule.Matches[0]
		rule.MatchAppID = first.AppID
		rule.MatchTitle = first.Title
		rule.MatchIsFloating = first.IsFloating
		rule.MatchIsActive = first.IsActive
		rule.MatchIsFocused = first.IsFocused
		rule.MatchIsActiveInColumn = first.IsActiveInColumn
		rule.MatchIsWindowCastTarget = first.IsWindowCastTarget
		rule.MatchIsUrgent = first.IsUrgent
		rule.MatchAtStartup = first.AtStartup
	}

	p.rules = append(p.rules, rule)
}

func (p *NiriRulesParser) parseSizeNode(node *document.Node) string {
	if node.Children == nil {
		return ""
	}
	for _, child := range node.Children {
		name := child.Name.String()
		if len(child.Arguments) > 0 {
			val := child.Arguments[0].ResolvedValue()
			switch name {
			case "fixed":
				if i, ok := val.(int64); ok {
					return "fixed " + strconv.FormatInt(i, 10)
				}
			case "proportion":
				if f, ok := val.(float64); ok {
					return "proportion " + strconv.FormatFloat(f, 'f', -1, 64)
				}
			}
		}
	}
	return ""
}

func (p *NiriRulesParser) parseMatchNode(node *document.Node) NiriMatch {
	m := NiriMatch{}
	if node.Properties == nil {
		return m
	}

	if val, ok := node.Properties.Get("app-id"); ok {
		m.AppID = val.ValueString()
	}
	if val, ok := node.Properties.Get("title"); ok {
		m.Title = val.ValueString()
	}
	if val, ok := node.Properties.Get("is-floating"); ok {
		b := val.ValueString() == "true"
		m.IsFloating = &b
	}
	if val, ok := node.Properties.Get("is-active"); ok {
		b := val.ValueString() == "true"
		m.IsActive = &b
	}
	if val, ok := node.Properties.Get("is-focused"); ok {
		b := val.ValueString() == "true"
		m.IsFocused = &b
	}
	if val, ok := node.Properties.Get("is-active-in-column"); ok {
		b := val.ValueString() == "true"
		m.IsActiveInColumn = &b
	}
	if val, ok := node.Properties.Get("is-window-cast-target"); ok {
		b := val.ValueString() == "true"
		m.IsWindowCastTarget = &b
	}
	if val, ok := node.Properties.Get("is-urgent"); ok {
		b := val.ValueString() == "true"
		m.IsUrgent = &b
	}
	if val, ok := node.Properties.Get("at-startup"); ok {
		b := val.ValueString() == "true"
		m.AtStartup = &b
	}
	return m
}

func (p *NiriRulesParser) parseBorderNode(node *document.Node, rule *NiriWindowRule) {
	if node.Children == nil {
		return
	}

	for _, child := range node.Children {
		switch child.Name.String() {
		case "off":
			b := true
			rule.BorderOff = &b
		case "active-color":
			if len(child.Arguments) > 0 {
				rule.BorderColor = child.Arguments[0].ValueString()
			}
		}
	}
}

func (p *NiriRulesParser) parseBackgroundEffectNode(node *document.Node, rule *NiriWindowRule) {
	if node.Children == nil {
		return
	}

	for _, child := range node.Children {
		switch child.Name.String() {
		case "blur":
			b := p.parseBoolArg(child)
			rule.BgBlur = &b
		case "xray":
			b := p.parseBoolArg(child)
			rule.BgXray = &b
		case "noise":
			if f, ok := p.parseFloatArg(child); ok {
				rule.BgNoise = &f
			}
		case "saturation":
			if f, ok := p.parseFloatArg(child); ok {
				rule.BgSaturation = &f
			}
		}
	}
}

func (p *NiriRulesParser) parseFloatingPositionNode(node *document.Node, rule *NiriWindowRule) {
	if node.Properties == nil {
		return
	}
	if val, ok := node.Properties.Get("x"); ok {
		if n, err := strconv.Atoi(strings.TrimSpace(val.ValueString())); err == nil {
			rule.DefaultFloatingX = &n
		}
	}
	if val, ok := node.Properties.Get("y"); ok {
		if n, err := strconv.Atoi(strings.TrimSpace(val.ValueString())); err == nil {
			rule.DefaultFloatingY = &n
		}
	}
	if val, ok := node.Properties.Get("relative-to"); ok {
		rule.DefaultFloatingRelative = val.ValueString()
	}
}

func (p *NiriRulesParser) parseFloatArg(node *document.Node) (float64, bool) {
	if len(node.Arguments) == 0 {
		return 0, false
	}
	val := node.Arguments[0].ResolvedValue()
	switch v := val.(type) {
	case float64:
		return v, true
	case int64:
		return float64(v), true
	}
	return 0, false
}

func (p *NiriRulesParser) parseFocusRingNode(node *document.Node, rule *NiriWindowRule) {
	if node.Children == nil {
		return
	}

	for _, child := range node.Children {
		switch child.Name.String() {
		case "off":
			b := true
			rule.FocusRingOff = &b
		case "active-color":
			if len(child.Arguments) > 0 {
				rule.FocusRingColor = child.Arguments[0].ValueString()
			}
		}
	}
}

func (p *NiriRulesParser) parseBoolArg(node *document.Node) bool {
	if len(node.Arguments) == 0 {
		return true
	}
	return node.Arguments[0].ValueString() != "false"
}

func (p *NiriRulesParser) HasDMSRulesIncluded() bool {
	return p.dmsRulesIncluded
}

var niriRulesMessages = configfrag.Messages{
	Missing:     "dms/windowrules.kdl does not exist",
	NotIncluded: "dms/windowrules.kdl is not included in config.kdl",
	Overridden:  "Some DMS rules may be overridden by config rules",
	Active:      "DMS window rules are active",
}

func (p *NiriRulesParser) buildDMSStatus() *windowrules.DMSRulesStatus {
	scan := configfrag.IncludeScan{Count: p.includeCount, DMSPosition: p.dmsIncludePos, DMSSeen: p.dmsRulesIncluded}
	return windowrules.DMSRulesStatusFrom(configfrag.BuildStatus(scan, p.dmsRulesExists, p.rulesAfterDMS, niriRulesMessages))
}

type NiriRulesParseResult struct {
	Rules            []NiriWindowRule
	DMSRulesIncluded bool
	DMSStatus        *windowrules.DMSRulesStatus
}

func ParseNiriWindowRules(configDir string) (*NiriRulesParseResult, error) {
	parser := NewNiriRulesParser(configDir)
	rules, err := parser.Parse()
	if err != nil {
		return nil, err
	}
	return &NiriRulesParseResult{
		Rules:            rules,
		DMSRulesIncluded: parser.HasDMSRulesIncluded(),
		DMSStatus:        parser.buildDMSStatus(),
	}, nil
}

func convertNiriMatches(matches []NiriMatch) []windowrules.MatchCriteria {
	if len(matches) == 0 {
		return nil
	}
	result := make([]windowrules.MatchCriteria, 0, len(matches))
	for _, m := range matches {
		result = append(result, windowrules.MatchCriteria{
			AppID:              m.AppID,
			Title:              m.Title,
			IsFloating:         m.IsFloating,
			IsActive:           m.IsActive,
			IsFocused:          m.IsFocused,
			IsActiveInColumn:   m.IsActiveInColumn,
			IsWindowCastTarget: m.IsWindowCastTarget,
			IsUrgent:           m.IsUrgent,
			AtStartup:          m.AtStartup,
		})
	}
	return result
}

func ConvertNiriRulesToWindowRules(niriRules []NiriWindowRule) []windowrules.WindowRule {
	result := make([]windowrules.WindowRule, 0, len(niriRules))
	for i, nr := range niriRules {
		wr := windowrules.WindowRule{
			ID:      fmt.Sprintf("rule_%d", i),
			Enabled: true,
			Source:  nr.Source,
			MatchCriteria: windowrules.MatchCriteria{
				AppID:              nr.MatchAppID,
				Title:              nr.MatchTitle,
				IsFloating:         nr.MatchIsFloating,
				IsActive:           nr.MatchIsActive,
				IsFocused:          nr.MatchIsFocused,
				IsActiveInColumn:   nr.MatchIsActiveInColumn,
				IsWindowCastTarget: nr.MatchIsWindowCastTarget,
				IsUrgent:           nr.MatchIsUrgent,
				AtStartup:          nr.MatchAtStartup,
			},
			Matches:  convertNiriMatches(nr.Matches),
			Excludes: convertNiriMatches(nr.Excludes),
			Actions: windowrules.Actions{
				Opacity:                   nr.Opacity,
				OpenFloating:              nr.OpenFloating,
				OpenMaximized:             nr.OpenMaximized,
				OpenMaximizedToEdges:      nr.OpenMaximizedToEdges,
				OpenFullscreen:            nr.OpenFullscreen,
				OpenFocused:               nr.OpenFocused,
				OpenOnOutput:              nr.OpenOnOutput,
				OpenOnWorkspace:           nr.OpenOnWorkspace,
				DefaultColumnWidth:        nr.DefaultColumnWidth,
				DefaultWindowHeight:       nr.DefaultWindowHeight,
				VariableRefreshRate:       nr.VariableRefreshRate,
				BlockOutFrom:              nr.BlockOutFrom,
				DefaultColumnDisplay:      nr.DefaultColumnDisplay,
				ScrollFactor:              nr.ScrollFactor,
				CornerRadius:              nr.CornerRadius,
				ClipToGeometry:            nr.ClipToGeometry,
				TiledState:                nr.TiledState,
				MinWidth:                  nr.MinWidth,
				MaxWidth:                  nr.MaxWidth,
				MinHeight:                 nr.MinHeight,
				MaxHeight:                 nr.MaxHeight,
				BorderColor:               nr.BorderColor,
				FocusRingColor:            nr.FocusRingColor,
				FocusRingOff:              nr.FocusRingOff,
				BorderOff:                 nr.BorderOff,
				DrawBorderWithBg:          nr.DrawBorderWithBg,
				BackgroundBlur:            nr.BgBlur,
				BackgroundXray:            nr.BgXray,
				BackgroundNoise:           nr.BgNoise,
				BackgroundSaturation:      nr.BgSaturation,
				DefaultFloatingX:          nr.DefaultFloatingX,
				DefaultFloatingY:          nr.DefaultFloatingY,
				DefaultFloatingRelativeTo: nr.DefaultFloatingRelative,
			},
		}
		result = append(result, wr)
	}
	return result
}

type NiriWritableProvider struct {
	configDir string
}

func NewNiriWritableProvider(configDir string) *NiriWritableProvider {
	return &NiriWritableProvider{configDir: configDir}
}

func (p *NiriWritableProvider) Name() string {
	return "niri"
}

func (p *NiriWritableProvider) GetOverridePath() string {
	return filepath.Join(p.configDir, "dms", "windowrules.kdl")
}

func (p *NiriWritableProvider) GetRuleSet() (*windowrules.RuleSet, error) {
	result, err := ParseNiriWindowRules(p.configDir)
	if err != nil {
		return nil, err
	}
	return &windowrules.RuleSet{
		Title:            "Niri Window Rules",
		Provider:         "niri",
		Rules:            ConvertNiriRulesToWindowRules(result.Rules),
		DMSRulesIncluded: result.DMSRulesIncluded,
		DMSStatus:        result.DMSStatus,
	}, nil
}

func (p *NiriWritableProvider) EnsureWritable() error {
	return nil
}

func (p *NiriWritableProvider) SetRule(rule windowrules.WindowRule) error {
	return windowrules.Set(p, rule)
}

func (p *NiriWritableProvider) RemoveRule(id string) error {
	return windowrules.Remove(p, id)
}

func (p *NiriWritableProvider) ReorderRules(ids []string) error {
	return windowrules.Reorder(p, ids)
}

var niriMetaCommentRegex = regexp.MustCompile(`^//\s*@id=(\S*)\s*@name=(.*)$`)

func (p *NiriWritableProvider) LoadDMSRules() ([]windowrules.WindowRule, error) {
	rulesPath := p.GetOverridePath()
	data, err := os.ReadFile(rulesPath)
	if err != nil {
		if os.IsNotExist(err) {
			return []windowrules.WindowRule{}, nil
		}
		return nil, err
	}

	content := string(data)
	lines := strings.Split(content, "\n")

	type ruleMeta struct {
		id   string
		name string
	}
	var metas []ruleMeta
	var currentID, currentName string

	for _, line := range lines {
		trimmed := strings.TrimSpace(line)
		if matches := niriMetaCommentRegex.FindStringSubmatch(trimmed); matches != nil {
			currentID = matches[1]
			currentName = strings.TrimSpace(matches[2])
			continue
		}
		if strings.HasPrefix(trimmed, "window-rule") {
			metas = append(metas, ruleMeta{id: currentID, name: currentName})
			currentID = ""
			currentName = ""
		}
	}

	doc, err := kdl.Parse(strings.NewReader(content))
	if err != nil {
		return nil, err
	}

	parser := NewNiriRulesParser(p.configDir)
	parser.currentSource = rulesPath

	for _, node := range doc.Nodes {
		if node.Name.String() == "window-rule" {
			parser.parseWindowRuleNode(node)
		}
	}

	var rules []windowrules.WindowRule
	for i, nr := range parser.rules {
		id := ""
		name := ""
		if i < len(metas) {
			id = metas[i].id
			name = metas[i].name
		}
		if id == "" {
			id = fmt.Sprintf("dms_rule_%d", i)
		}

		wr := windowrules.WindowRule{
			ID:      id,
			Name:    name,
			Enabled: true,
			Source:  rulesPath,
			MatchCriteria: windowrules.MatchCriteria{
				AppID:              nr.MatchAppID,
				Title:              nr.MatchTitle,
				IsFloating:         nr.MatchIsFloating,
				IsActive:           nr.MatchIsActive,
				IsFocused:          nr.MatchIsFocused,
				IsActiveInColumn:   nr.MatchIsActiveInColumn,
				IsWindowCastTarget: nr.MatchIsWindowCastTarget,
				IsUrgent:           nr.MatchIsUrgent,
				AtStartup:          nr.MatchAtStartup,
			},
			Matches:  convertNiriMatches(nr.Matches),
			Excludes: convertNiriMatches(nr.Excludes),
			Actions: windowrules.Actions{
				Opacity:                   nr.Opacity,
				OpenFloating:              nr.OpenFloating,
				OpenMaximized:             nr.OpenMaximized,
				OpenMaximizedToEdges:      nr.OpenMaximizedToEdges,
				OpenFullscreen:            nr.OpenFullscreen,
				OpenFocused:               nr.OpenFocused,
				OpenOnOutput:              nr.OpenOnOutput,
				OpenOnWorkspace:           nr.OpenOnWorkspace,
				DefaultColumnWidth:        nr.DefaultColumnWidth,
				DefaultWindowHeight:       nr.DefaultWindowHeight,
				VariableRefreshRate:       nr.VariableRefreshRate,
				BlockOutFrom:              nr.BlockOutFrom,
				DefaultColumnDisplay:      nr.DefaultColumnDisplay,
				ScrollFactor:              nr.ScrollFactor,
				CornerRadius:              nr.CornerRadius,
				ClipToGeometry:            nr.ClipToGeometry,
				TiledState:                nr.TiledState,
				MinWidth:                  nr.MinWidth,
				MaxWidth:                  nr.MaxWidth,
				MinHeight:                 nr.MinHeight,
				MaxHeight:                 nr.MaxHeight,
				BorderColor:               nr.BorderColor,
				FocusRingColor:            nr.FocusRingColor,
				FocusRingOff:              nr.FocusRingOff,
				BorderOff:                 nr.BorderOff,
				DrawBorderWithBg:          nr.DrawBorderWithBg,
				BackgroundBlur:            nr.BgBlur,
				BackgroundXray:            nr.BgXray,
				BackgroundNoise:           nr.BgNoise,
				BackgroundSaturation:      nr.BgSaturation,
				DefaultFloatingX:          nr.DefaultFloatingX,
				DefaultFloatingY:          nr.DefaultFloatingY,
				DefaultFloatingRelativeTo: nr.DefaultFloatingRelative,
			},
		}

		rules = append(rules, wr)
	}

	return rules, nil
}

func (p *NiriWritableProvider) WriteDMSRules(rules []windowrules.WindowRule) error {
	rulesPath := p.GetOverridePath()

	if err := os.MkdirAll(filepath.Dir(rulesPath), 0755); err != nil {
		return err
	}

	var lines []string
	lines = append(lines, "// DMS Window Rules - Managed by Dux Shell")
	lines = append(lines, "// Do not edit manually - changes may be overwritten")
	lines = append(lines, "")

	for _, rule := range rules {
		lines = append(lines, p.formatRule(rule))
		lines = append(lines, "")
	}

	return os.WriteFile(rulesPath, []byte(strings.Join(lines, "\n")), 0644)
}

func formatNiriMatchLine(keyword string, m windowrules.MatchCriteria) (string, bool) {
	var matchProps []string
	if m.AppID != "" {
		matchProps = append(matchProps, fmt.Sprintf("app-id=%q", m.AppID))
	}
	if m.Title != "" {
		matchProps = append(matchProps, fmt.Sprintf("title=%q", m.Title))
	}
	if m.IsFloating != nil {
		matchProps = append(matchProps, fmt.Sprintf("is-floating=%t", *m.IsFloating))
	}
	if m.IsActive != nil {
		matchProps = append(matchProps, fmt.Sprintf("is-active=%t", *m.IsActive))
	}
	if m.IsFocused != nil {
		matchProps = append(matchProps, fmt.Sprintf("is-focused=%t", *m.IsFocused))
	}
	if m.IsActiveInColumn != nil {
		matchProps = append(matchProps, fmt.Sprintf("is-active-in-column=%t", *m.IsActiveInColumn))
	}
	if m.IsWindowCastTarget != nil {
		matchProps = append(matchProps, fmt.Sprintf("is-window-cast-target=%t", *m.IsWindowCastTarget))
	}
	if m.IsUrgent != nil {
		matchProps = append(matchProps, fmt.Sprintf("is-urgent=%t", *m.IsUrgent))
	}
	if m.AtStartup != nil {
		matchProps = append(matchProps, fmt.Sprintf("at-startup=%t", *m.AtStartup))
	}
	if len(matchProps) == 0 {
		return "", false
	}
	return "    " + keyword + " " + strings.Join(matchProps, " "), true
}

func (p *NiriWritableProvider) formatRule(rule windowrules.WindowRule) string {
	var lines []string
	lines = append(lines, fmt.Sprintf("// @id=%s @name=%s", rule.ID, rule.Name))
	lines = append(lines, "window-rule {")

	matches := rule.Matches
	if len(matches) == 0 {
		matches = []windowrules.MatchCriteria{rule.MatchCriteria}
	}
	for _, m := range matches {
		if line, ok := formatNiriMatchLine("match", m); ok {
			lines = append(lines, line)
		}
	}
	for _, m := range rule.Excludes {
		if line, ok := formatNiriMatchLine("exclude", m); ok {
			lines = append(lines, line)
		}
	}

	a := rule.Actions
	if a.Opacity != nil {
		lines = append(lines, fmt.Sprintf("    opacity %.2f", *a.Opacity))
	}
	if a.OpenFloating != nil {
		lines = append(lines, fmt.Sprintf("    open-floating %t", *a.OpenFloating))
	}
	if a.OpenMaximized != nil && *a.OpenMaximized {
		lines = append(lines, "    open-maximized true")
	}
	if a.OpenMaximizedToEdges != nil && *a.OpenMaximizedToEdges {
		lines = append(lines, "    open-maximized-to-edges true")
	}
	if a.OpenFullscreen != nil && *a.OpenFullscreen {
		lines = append(lines, "    open-fullscreen true")
	}
	if a.OpenFocused != nil {
		lines = append(lines, fmt.Sprintf("    open-focused %t", *a.OpenFocused))
	}
	if a.OpenOnOutput != "" {
		lines = append(lines, fmt.Sprintf("    open-on-output %q", a.OpenOnOutput))
	}
	if a.OpenOnWorkspace != "" {
		lines = append(lines, fmt.Sprintf("    open-on-workspace %q", a.OpenOnWorkspace))
	}
	if a.DefaultColumnWidth != "" {
		lines = append(lines, formatSizeProperty("default-column-width", a.DefaultColumnWidth))
	}
	if a.DefaultWindowHeight != "" {
		lines = append(lines, formatSizeProperty("default-window-height", a.DefaultWindowHeight))
	}
	if a.VariableRefreshRate != nil && *a.VariableRefreshRate {
		lines = append(lines, "    variable-refresh-rate true")
	}
	if a.BlockOutFrom != "" {
		lines = append(lines, fmt.Sprintf("    block-out-from %q", a.BlockOutFrom))
	}
	if a.DefaultColumnDisplay != "" {
		lines = append(lines, fmt.Sprintf("    default-column-display %q", a.DefaultColumnDisplay))
	}
	if a.ScrollFactor != nil {
		lines = append(lines, fmt.Sprintf("    scroll-factor %.2f", *a.ScrollFactor))
	}
	if a.CornerRadius != nil {
		lines = append(lines, fmt.Sprintf("    geometry-corner-radius %d", *a.CornerRadius))
	}
	if a.ClipToGeometry != nil && *a.ClipToGeometry {
		lines = append(lines, "    clip-to-geometry true")
	}
	if a.TiledState != nil && *a.TiledState {
		lines = append(lines, "    tiled-state true")
	}
	if a.MinWidth != nil {
		lines = append(lines, fmt.Sprintf("    min-width %d", *a.MinWidth))
	}
	if a.MaxWidth != nil {
		lines = append(lines, fmt.Sprintf("    max-width %d", *a.MaxWidth))
	}
	if a.MinHeight != nil {
		lines = append(lines, fmt.Sprintf("    min-height %d", *a.MinHeight))
	}
	if a.MaxHeight != nil {
		lines = append(lines, fmt.Sprintf("    max-height %d", *a.MaxHeight))
	}
	if a.BorderOff != nil && *a.BorderOff {
		lines = append(lines, "    border { off; }")
	} else if a.BorderColor != "" {
		lines = append(lines, fmt.Sprintf("    border { active-color %q; }", a.BorderColor))
	}
	if a.FocusRingOff != nil && *a.FocusRingOff {
		lines = append(lines, "    focus-ring { off; }")
	} else if a.FocusRingColor != "" {
		lines = append(lines, fmt.Sprintf("    focus-ring { active-color %q; }", a.FocusRingColor))
	}
	if a.DrawBorderWithBg != nil {
		lines = append(lines, fmt.Sprintf("    draw-border-with-background %t", *a.DrawBorderWithBg))
	}

	if a.BackgroundBlur != nil || a.BackgroundXray != nil || a.BackgroundNoise != nil || a.BackgroundSaturation != nil {
		lines = append(lines, "    background-effect {")
		if a.BackgroundBlur != nil {
			lines = append(lines, fmt.Sprintf("        blur %t", *a.BackgroundBlur))
		}
		if a.BackgroundXray != nil {
			lines = append(lines, fmt.Sprintf("        xray %t", *a.BackgroundXray))
		}
		if a.BackgroundNoise != nil {
			lines = append(lines, fmt.Sprintf("        noise %s", formatFloat(*a.BackgroundNoise)))
		}
		if a.BackgroundSaturation != nil {
			lines = append(lines, fmt.Sprintf("        saturation %s", formatFloat(*a.BackgroundSaturation)))
		}
		lines = append(lines, "    }")
	}

	if a.DefaultFloatingX != nil && a.DefaultFloatingY != nil {
		line := fmt.Sprintf("    default-floating-position x=%d y=%d", *a.DefaultFloatingX, *a.DefaultFloatingY)
		if a.DefaultFloatingRelativeTo != "" {
			line += fmt.Sprintf(" relative-to=%q", a.DefaultFloatingRelativeTo)
		}
		lines = append(lines, line)
	}

	lines = append(lines, "}")
	return strings.Join(lines, "\n")
}

func formatFloat(f float64) string {
	return strconv.FormatFloat(f, 'f', -1, 64)
}

func formatSizeProperty(name, value string) string {
	parts := strings.SplitN(value, " ", 2)
	if len(parts) == 2 {
		return fmt.Sprintf("    %s { %s %s; }", name, parts[0], parts[1])
	}
	// Bare number without type prefix — default to "fixed"
	if _, err := strconv.Atoi(value); err == nil {
		return fmt.Sprintf("    %s { fixed %s; }", name, value)
	}
	return fmt.Sprintf("    %s { }", name)
}
