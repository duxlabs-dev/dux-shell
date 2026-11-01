package niriconf

import (
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"slices"
	"strings"

	"github.com/sblinch/kdl-go/document"
)

const (
	SeverityError   = "error"
	SeverityWarning = "warning"
)

const (
	KindDuplicateBind    = "duplicate-bind"
	KindDuplicateStartup = "duplicate-startup"
	KindMissingInclude   = "missing-include"
	KindNotIncluded      = "not-included"
	KindOverride         = "override"
	KindReplaced         = "replaced"
	KindUnusedRule       = "unused-rule"
	KindObsolete         = "obsolete"
	KindUnreadable       = "unreadable"
)

// FixAddInclude is the only fix the doctor applies, FixUndoInclude takes it back: the other findings sit in files DMS or the user owns.
const (
	FixAddInclude  = "add-include"
	FixUndoInclude = "undo-include"
)

const (
	FileBase        = "base"
	FileActive      = "active"
	FileMissing     = "missing"
	FileNotIncluded = "not-included"
	FileUnreadable  = "unreadable"
)

// Finding.Files are relative to the config dir, in config order: the last one wins.
type Finding struct {
	Kind     string   `json:"kind"`
	Severity string   `json:"severity"`
	Subject  string   `json:"subject"`
	Files    []string `json:"files"`
	Fix      string   `json:"fix,omitempty"`
}

// FileState.Overrides counts the settings of earlier files this one replaces.
type FileState struct {
	Path      string `json:"path"`
	State     string `json:"state"`
	Overrides int    `json:"overrides"`
}

type Report struct {
	Files    []FileState `json:"files"`
	Findings []Finding   `json:"findings"`
	// Undo is true while the last added include can be taken back.
	Undo bool `json:"undo"`
}

// Sections inserted as is, never merged (see the niri wiki, Configuration: Include).
var multipart = map[string]bool{
	"window-rule": true, "layer-rule": true, "output": true, "workspace": true,
	"spawn-at-startup": true, "spawn-sh-at-startup": true,
}

// Blocks a later file replaces whole instead of merging their properties.
var wholeBlocks = map[string]bool{
	"layout struts":                true,
	"layout preset-column-widths":  true,
	"layout preset-window-heights": true,
	"layout default-column-width":  true,
	"input touchpad":               true,
	"input mouse":                  true,
	"input trackpoint":             true,
	"input trackball":              true,
	"input tablet":                 true,
	"input touch":                  true,
}

var modAliases = map[string]string{"control": "ctrl", "win": "super", "mod5": "iso_level3_shift", "mod3": "iso_level5_shift"}

type setting struct{ file, label string }

type rule struct {
	file   string
	appIDs []string
}

type doctor struct {
	dir     string
	report  Report
	seen    map[string]bool
	byFile  map[string]int
	values  map[string][]setting
	order   []string
	whole   map[string]bool
	rules   []rule
	spawns  []spawnLine
	subject map[string]string
}

// Doctor reads configDir/config.kdl and every file it includes, without running niri.
// appIDs are the apps known on this machine; rules are only judged against a non-empty list.
func Doctor(configDir string, appIDs []string) Report {
	d := &doctor{
		dir: configDir, seen: map[string]bool{}, byFile: map[string]int{},
		values: map[string][]setting{}, whole: map[string]bool{}, subject: map[string]string{},
	}
	d.report.Findings = []Finding{}
	d.walk(filepath.Join(configDir, "config.kdl"), true)
	d.overrides()
	d.unusedRules(appIDs)
	d.notIncluded()
	d.duplicateStartup(autostartEntries(autostartDir()))
	d.report.Undo = undoable(configDir)
	return d.report
}

func (d *doctor) rel(abs string) string {
	rel, err := filepath.Rel(d.dir, abs)
	if err != nil || !filepath.IsLocal(rel) {
		return filepath.Base(abs)
	}
	return rel
}

func (d *doctor) add(f Finding) {
	d.report.Findings = append(d.report.Findings, f)
}

func (d *doctor) file(path, state string) {
	d.byFile[path] = len(d.report.Files)
	d.report.Files = append(d.report.Files, FileState{Path: path, State: state})
}

func (d *doctor) walk(abs string, base bool) {
	if d.seen[abs] {
		return
	}
	d.seen[abs] = true
	path := d.rel(abs)
	data, err := os.ReadFile(abs)
	if errors.Is(err, fs.ErrNotExist) {
		d.file(path, FileMissing)
		return
	}
	var doc *document.Document
	if err == nil {
		doc, err = parseNiriKDL(data)
	}
	if err != nil {
		d.file(path, FileUnreadable)
		d.add(Finding{Kind: KindUnreadable, Severity: SeverityWarning, Subject: path, Files: []string{path}})
		return
	}
	state := FileActive
	if base {
		state = FileBase
	}
	d.file(path, state)

	for _, n := range doc.Nodes {
		d.obsolete(n, nil, path)
		name := n.Name.NodeNameString()
		switch {
		case name == "include":
			d.include(n, abs, path)
		case name == "window-rule":
			d.rule(n, path)
		case name == "spawn-at-startup":
			d.spawn(n, path)
		case multipart[name]:
		case name == "binds":
			d.binds(n, []string{name}, path)
		default:
			d.collect(n, []string{name}, path)
		}
	}
}

func (d *doctor) include(n *document.Node, abs, from string) {
	if len(n.Arguments) == 0 {
		return
	}
	target, err := resolveInclude(filepath.Dir(abs), n.Arguments[0].ValueString())
	if err != nil {
		return
	}
	if _, err := os.Stat(target); errors.Is(err, fs.ErrNotExist) {
		optional, _ := n.Properties.Get("optional")
		if optional == nil || optional.ResolvedValue() != true {
			d.add(Finding{Kind: KindMissingInclude, Severity: SeverityError, Subject: d.rel(target), Files: []string{from, d.rel(target)}})
		}
	}
	d.walk(target, false)
}

func (d *doctor) set(key, label, file string, whole bool) {
	if _, ok := d.values[key]; !ok {
		d.order = append(d.order, key)
	}
	d.values[key] = append(d.values[key], setting{file: file, label: label})
	d.whole[key] = whole
	d.subject[key] = label
}

func (d *doctor) collect(n *document.Node, path []string, file string) {
	key := strings.Join(path, " ")
	whole := wholeBlocks[key] || (len(path) == 2 && path[0] == "animations")
	if len(n.Children) == 0 || whole {
		d.set(key, key, file, whole)
		return
	}
	for _, c := range n.Children {
		name := c.Name.NodeNameString()
		if name == "binds" {
			d.binds(c, append(slices.Clone(path), name), file)
			continue
		}
		d.collect(c, append(slices.Clone(path), name), file)
	}
}
