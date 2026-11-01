package niriconf

import (
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strings"

	"github.com/sblinch/kdl-go/document"
)

// binds reports a key bound twice in one block: niri refuses that config.
func (d *doctor) binds(n *document.Node, path []string, file string) {
	block := map[string]bool{}
	prefix := strings.Join(path, " ")
	for _, c := range n.Children {
		label := c.Name.NodeNameString()
		key := normalizeKey(label)
		if block[key] {
			d.add(Finding{Kind: KindDuplicateBind, Severity: SeverityError, Subject: label, Files: []string{file}})
			continue
		}
		block[key] = true
		d.set(prefix+" "+key, label, file, false)
	}
}

func normalizeKey(name string) string {
	parts := strings.Split(strings.ToLower(name), "+")
	mods := parts[:len(parts)-1]
	for i, m := range mods {
		m = strings.TrimSpace(m)
		if alias, ok := modAliases[m]; ok {
			m = alias
		}
		mods[i] = m
	}
	slices.Sort(mods)
	return strings.Join(append(mods, parts[len(parts)-1]), "+")
}

// overrides reports what the mockup shows: binds hidden by a later file, options set twice
// in one file, and blocks replaced whole. A plain option overridden by a later file is how
// DMS works, so it only counts in FileState.Overrides.
func (d *doctor) overrides() {
	for _, key := range d.order {
		values := d.values[key]
		if len(values) < 2 {
			continue
		}
		last := values[len(values)-1]
		files := make([]string, len(values))
		otherFile := false
		for i, v := range values {
			files[i] = v.file
			otherFile = otherFile || v.file != last.file
		}
		if otherFile {
			d.report.Files[d.byFile[last.file]].Overrides++
		}
		bind := strings.HasPrefix(key, "binds ")
		switch {
		case d.whole[key] && otherFile:
			d.add(Finding{Kind: KindReplaced, Severity: SeverityError, Subject: d.subject[key], Files: files})
		case bind && otherFile, !otherFile:
			d.add(Finding{Kind: KindOverride, Severity: SeverityWarning, Subject: d.subject[key], Files: files})
		}
	}
}

// rule keeps the app-id patterns of a rule only when every match has one: a title-only
// or state-only match may hit any app.
func (d *doctor) rule(n *document.Node, file string) {
	var ids []string
	for _, c := range n.Children {
		if c.Name.NodeNameString() != "match" {
			continue
		}
		id, ok := c.Properties.Get("app-id")
		if !ok {
			return
		}
		ids = append(ids, id.ValueString())
	}
	if len(ids) > 0 {
		d.rules = append(d.rules, rule{file: file, appIDs: ids})
	}
}

// unusedRules skips a pattern Go cannot compile: niri's regex dialect differs a little.
func (d *doctor) unusedRules(appIDs []string) {
	if len(appIDs) == 0 {
		return
	}
	for _, r := range d.rules {
		if !matchesNone(r.appIDs, appIDs) {
			continue
		}
		d.add(Finding{Kind: KindUnusedRule, Severity: SeverityWarning, Subject: strings.Join(r.appIDs, " | "), Files: []string{r.file}})
	}
}

func matchesNone(patterns, appIDs []string) bool {
	for _, p := range patterns {
		re, err := regexp.Compile(p)
		if err != nil {
			return false
		}
		if slices.ContainsFunc(appIDs, re.MatchString) {
			return false
		}
	}
	return true
}

// obsolete follows the niri wiki: output background-color (deprecated in 25.11) and colors
// written as four numbers (Configuration: Layout).
func (d *doctor) obsolete(n *document.Node, parent []string, file string) {
	name := n.Name.NodeNameString()
	path := append(slices.Clone(parent), name)
	subject := strings.Join(path, " ")
	switch {
	case len(parent) == 1 && parent[0] == "output" && name == "background-color":
		d.add(Finding{Kind: KindObsolete, Severity: SeverityWarning, Subject: subject, Files: []string{file}})
	case strings.HasSuffix(name, "-color") && len(n.Arguments) == 4:
		d.add(Finding{Kind: KindObsolete, Severity: SeverityWarning, Subject: subject, Files: []string{file}})
	}
	for _, c := range n.Children {
		d.obsolete(c, path, file)
	}
}

// notIncluded skips niri-custom.kdl: the page's niri.kdl includes it.
// An empty fragment carries no setting: nothing to include, no dormant warning.
func (d *doctor) notIncluded() {
	frags, _ := filepath.Glob(filepath.Join(d.dir, "dms", "*.kdl"))
	for _, abs := range frags {
		if d.seen[abs] || filepath.Base(abs) == "niri-custom.kdl" || !validName(filepath.Base(abs)) {
			continue
		}
		if info, err := os.Stat(abs); err != nil || info.Size() == 0 {
			continue
		}
		path := d.rel(abs)
		d.file(path, FileNotIncluded)
		d.add(Finding{Kind: KindNotIncluded, Severity: SeverityWarning, Subject: path, Files: []string{path}, Fix: FixAddInclude})
	}
}
