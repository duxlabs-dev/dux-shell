package providers

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/duxlabs-dev/dux-shell/core/internal/mangoconf"
	"github.com/duxlabs-dev/dux-shell/core/internal/windowrules"
)

// DMS-managed rules live in dms/windowrules.conf (sourced from config.conf),
// each preceded by an `# @id=<id> @name=<name>` comment so they round-trip.

type MangoWindowRule struct {
	Source string
	Fields map[string]string
}

var mangoWindowRuleRegex = regexp.MustCompile(`^window_rule\s*=\s*(.+)$`)
var mangoMetaCommentRegex = regexp.MustCompile(`^#\s*@id=(\S*)\s*@name=(.*)$`)
var mangoOnceRuleRegex = regexp.MustCompile(`^window_rule_once\s*=`)

// Fields the editor models; anything else on a DMS rule line is carried through saves.
var mangoModeledFields = map[string]bool{
	"app_id": true, "title": true, "tags": true, "monitor": true, "width": true, "height": true,
	"is_floating": true, "is_fullscreen": true, "no_blur": true, "no_border": true,
	"no_shadow": true, "no_radius": true, "no_animation": true,
}

func mangoUnmodeledFields(value string) [][2]string {
	var extra [][2]string
	fields := parseMangoWindowRuleLine(value)
	_, hasWidth := fields["width"]
	_, hasHeight := fields["height"]
	for pair := range strings.SplitSeq(value, ",") {
		k, v, ok := strings.Cut(strings.TrimSpace(pair), ":")
		if !ok {
			continue
		}
		key := strings.TrimSpace(k)
		sized := (key == "width" || key == "height") && (!hasWidth || !hasHeight)
		if key != "" && (!mangoModeledFields[key] || sized) {
			extra = append(extra, [2]string{key, strings.TrimSpace(v)})
		}
	}
	return extra
}

func parseMangoWindowRuleLine(value string) map[string]string {
	fields := map[string]string{}
	for pair := range strings.SplitSeq(value, ",") {
		pair = strings.TrimSpace(pair)
		if pair == "" {
			continue
		}
		before, after, ok := strings.Cut(pair, ":")
		if !ok {
			continue
		}
		key := strings.TrimSpace(before)
		val := strings.TrimSpace(after)
		if key != "" {
			fields[key] = val
		}
	}
	return fields
}

// mangoConfigPath returns the main mango config (config.conf or mango.conf).
func mangoConfigPath(configDir string) string {
	candidates := []string{
		filepath.Join(configDir, "config.conf"),
		filepath.Join(configDir, "mango.conf"),
	}
	for _, c := range candidates {
		if _, err := os.Stat(c); err == nil {
			return c
		}
	}
	return candidates[0]
}

func mangoOverridePath(configDir string) string {
	return filepath.Join(configDir, "dms", "windowrules.conf")
}

// parseMangoRulesFile reads a config file and returns its window_rule= lines.
func parseMangoRulesFile(path, source string) []MangoWindowRule {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil
	}
	var rules []MangoWindowRule
	for line := range strings.SplitSeq(string(data), "\n") {
		trimmed := strings.TrimSpace(line)
		if m := mangoWindowRuleRegex.FindStringSubmatch(trimmed); m != nil {
			rules = append(rules, MangoWindowRule{Source: source, Fields: parseMangoWindowRuleLine(m[1])})
		}
	}
	return rules
}

type MangoRulesParseResult struct {
	Rules            []MangoWindowRule
	DMSRulesIncluded bool
	DMSStatus        *windowrules.DMSRulesStatus
}

func ParseMangoWindowRules(configDir string) (*MangoRulesParseResult, error) {
	mainPath := mangoConfigPath(configDir)
	overridePath := mangoOverridePath(configDir)

	var rules []MangoWindowRule
	rules = append(rules, parseMangoRulesFile(mainPath, "config.conf")...)
	rules = append(rules, parseMangoRulesFile(overridePath, "dms/windowrules.conf")...)

	included := mangoDMSRulesIncluded(mainPath)
	return &MangoRulesParseResult{
		Rules:            rules,
		DMSRulesIncluded: included,
		DMSStatus: &windowrules.DMSRulesStatus{
			Exists:        fileExists(overridePath),
			Included:      included,
			Effective:     included,
			StatusMessage: mangoIncludeMessage(included),
		},
	}, nil
}

func fileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

func mangoDMSRulesIncluded(mainPath string) bool {
	data, err := os.ReadFile(mainPath)
	if err != nil {
		return false
	}
	for line := range strings.SplitSeq(string(data), "\n") {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "source") && strings.Contains(trimmed, "dms/windowrules.conf") {
			return true
		}
	}
	return false
}

func mangoIncludeMessage(included bool) string {
	if included {
		return "DMS window rules are sourced from config.conf"
	}
	return "Add `source=./dms/windowrules.conf` to config.conf to apply DMS window rules"
}

func mangoBoolField(fields map[string]string, key string) *bool {
	v, ok := fields[key]
	if !ok {
		return nil
	}
	b := v == "1" || strings.EqualFold(v, "true")
	return &b
}

func mangoBoolStr(b *bool) string {
	if b != nil && *b {
		return "1"
	}
	return "0"
}

func ConvertMangoRulesToWindowRules(mangoRules []MangoWindowRule) []windowrules.WindowRule {
	result := make([]windowrules.WindowRule, 0, len(mangoRules))
	for i, mr := range mangoRules {
		f := mr.Fields
		actions := windowrules.Actions{
			OpenFloating:   mangoBoolField(f, "is_floating"),
			OpenFullscreen: mangoBoolField(f, "is_fullscreen"),
			NoBlur:         mangoBoolField(f, "no_blur"),
			NoBorder:       mangoBoolField(f, "no_border"),
			NoShadow:       mangoBoolField(f, "no_shadow"),
			NoRounding:     mangoBoolField(f, "no_radius"),
			NoAnim:         mangoBoolField(f, "no_animation"),
		}
		if tags, ok := f["tags"]; ok {
			actions.Workspace = tags
		}
		if mon, ok := f["monitor"]; ok {
			actions.Monitor = mon
		}
		if w, ok := f["width"]; ok {
			if h, ok2 := f["height"]; ok2 {
				actions.SizeWidth = w
				actions.SizeHeight = h
			}
		}

		result = append(result, windowrules.WindowRule{
			ID:      fmt.Sprintf("rule_%d", i),
			Enabled: true,
			Source:  mr.Source,
			MatchCriteria: windowrules.MatchCriteria{
				AppID: f["app_id"],
				Title: f["title"],
			},
			Actions: actions,
		})
	}
	return result
}

func formatMangoRule(rule windowrules.WindowRule, extra ...[2]string) string {
	var parts []string
	add := func(k, v string) {
		if v != "" {
			parts = append(parts, k+":"+v)
		}
	}

	add("app_id", rule.MatchCriteria.AppID)
	add("title", rule.MatchCriteria.Title)
	add("tags", rule.Actions.Workspace)
	add("monitor", rule.Actions.Monitor)

	if rule.Actions.SizeWidth != "" && rule.Actions.SizeHeight != "" {
		add("width", rule.Actions.SizeWidth)
		add("height", rule.Actions.SizeHeight)
	}

	addBool := func(k string, b *bool) {
		if b != nil {
			parts = append(parts, k+":"+mangoBoolStr(b))
		}
	}
	addBool("is_floating", rule.Actions.OpenFloating)
	addBool("is_fullscreen", rule.Actions.OpenFullscreen)
	addBool("no_blur", rule.Actions.NoBlur)
	addBool("no_border", rule.Actions.NoBorder)
	addBool("no_shadow", rule.Actions.NoShadow)
	addBool("no_radius", rule.Actions.NoRounding)
	addBool("no_animation", rule.Actions.NoAnim)
	for _, kv := range extra {
		add(kv[0], kv[1])
	}

	return "window_rule=" + strings.Join(parts, ",")
}

type MangoWritableProvider struct {
	configDir string
	// Filled by LoadDMSRules so the following write keeps what the editor cannot show.
	extraFields map[string][][2]string
	onceLines   []string
}

func NewMangoWritableProvider(configDir string) *MangoWritableProvider {
	return &MangoWritableProvider{configDir: configDir}
}

func (p *MangoWritableProvider) Name() string { return "mango" }

func (p *MangoWritableProvider) GetOverridePath() string {
	return mangoOverridePath(p.configDir)
}

func (p *MangoWritableProvider) GetRuleSet() (*windowrules.RuleSet, error) {
	result, err := ParseMangoWindowRules(p.configDir)
	if err != nil {
		return nil, err
	}
	return &windowrules.RuleSet{
		Title:            "Mango Window Rules",
		Provider:         "mango",
		Rules:            ConvertMangoRulesToWindowRules(result.Rules),
		DMSRulesIncluded: result.DMSRulesIncluded,
		DMSStatus:        result.DMSStatus,
	}, nil
}

func (p *MangoWritableProvider) EnsureWritable() error {
	return nil
}

func (p *MangoWritableProvider) SetRule(rule windowrules.WindowRule) error {
	return windowrules.Set(p, rule)
}

func (p *MangoWritableProvider) RemoveRule(id string) error {
	return windowrules.Remove(p, id)
}

func (p *MangoWritableProvider) ReorderRules(ids []string) error {
	return windowrules.Reorder(p, ids)
}

// LoadDMSRules parses only the DMS override file, preserving @id/@name metadata.
func (p *MangoWritableProvider) LoadDMSRules() ([]windowrules.WindowRule, error) {
	data, err := os.ReadFile(p.GetOverridePath())
	if err != nil {
		if os.IsNotExist(err) {
			return []windowrules.WindowRule{}, nil
		}
		return nil, err
	}

	var rules []windowrules.WindowRule
	var curID, curName string
	idx := 0
	p.extraFields = map[string][][2]string{}
	p.onceLines = nil
	for line := range strings.SplitSeq(string(data), "\n") {
		trimmed := strings.TrimSpace(line)
		if m := mangoMetaCommentRegex.FindStringSubmatch(trimmed); m != nil {
			curID = m[1]
			curName = strings.TrimSpace(m[2])
			continue
		}
		if mangoOnceRuleRegex.MatchString(trimmed) {
			p.onceLines = append(p.onceLines, trimmed)
			curID, curName = "", ""
			continue
		}
		if m := mangoWindowRuleRegex.FindStringSubmatch(trimmed); m != nil {
			converted := ConvertMangoRulesToWindowRules([]MangoWindowRule{{Source: "dms/windowrules.conf", Fields: parseMangoWindowRuleLine(m[1])}})
			wr := converted[0]
			if curID != "" {
				wr.ID = curID
			} else {
				wr.ID = fmt.Sprintf("rule_%d", idx)
			}
			wr.Name = curName
			if extra := mangoUnmodeledFields(m[1]); len(extra) > 0 {
				p.extraFields[wr.ID] = extra
			}
			rules = append(rules, wr)
			curID, curName = "", ""
			idx++
		}
	}
	return rules, nil
}

func (p *MangoWritableProvider) WriteDMSRules(rules []windowrules.WindowRule) error {
	overridePath := p.GetOverridePath()
	if err := os.MkdirAll(filepath.Dir(overridePath), 0o755); err != nil {
		return err
	}

	var sb strings.Builder
	sb.WriteString("# Auto-generated by DMS - DMS-managed mango window rules\n\n")
	for i, r := range rules {
		id := r.ID
		if id == "" {
			id = fmt.Sprintf("rule_%d", i)
		}
		line := formatMangoRule(r, p.extraFields[r.ID]...)
		if err := mangoconf.CheckLine(line); err != nil {
			return fmt.Errorf("rule %q: %w", r.Name, err)
		}
		fmt.Fprintf(&sb, "# @id=%s @name=%s\n", id, r.Name)
		sb.WriteString(line)
		sb.WriteString("\n\n")
	}
	for _, line := range p.onceLines {
		sb.WriteString(line)
		sb.WriteString("\n")
	}

	return os.WriteFile(overridePath, []byte(sb.String()), 0o644)
}
