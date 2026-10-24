package matugen

import (
	"cmp"
	"encoding/json"
	"fmt"
	"os"
	"strings"
)

type AuditReport struct {
	Variant     string        `json:"variant"`
	Results     []AuditResult `json:"results"`
	Adjustments []Adjustment  `json:"adjustments"`
}

func (r AuditReport) Failures() int {
	n := 0
	for _, res := range r.Results {
		if !res.Pass {
			n++
		}
	}
	return n
}

type colorsFile struct {
	Mode        string                       `json:"mode"`
	Dank16      map[string]map[string]string `json:"dank16"`
	Dank16Term  map[string]map[string]string `json:"dank16term"`
	Colors      map[string]map[string]string `json:"colors"`
	Adjustments map[string][]Adjustment      `json:"adjustments"`
	Contrast    map[string][]AuditResult     `json:"contrast"`
}

// AuditColorsFile reports the palette DMS last wrote; variant "" means what the shell shows now.
// With terminalsDark the terminal rows come from the dark variant, as forced-dark terminals render it.
func AuditColorsFile(path, variant string, terminalsDark bool) (AuditReport, error) {
	switch variant {
	case "", "default", "dark", "light":
	default:
		return AuditReport{}, fmt.Errorf("unknown variant %q (want dark, light or default)", variant)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return AuditReport{}, err
	}
	var f colorsFile
	if err := json.Unmarshal(data, &f); err != nil {
		return AuditReport{}, fmt.Errorf("%s: %w", path, err)
	}
	if variant == "" || variant == "default" {
		variant = f.shownVariant()
	}

	results := f.results(variant)
	if terminalsDark && variant != "dark" {
		results = withTerminalRows(results, f.results("dark"))
	}

	adjustments := f.Adjustments[variant]
	if adjustments == nil {
		adjustments = []Adjustment{}
	}
	return AuditReport{Variant: variant, Results: results, Adjustments: adjustments}, nil
}

// shownVariant is "default" only when generation recorded it apart from the mode's own variant.
func (f colorsFile) shownVariant() string {
	if _, ok := f.Contrast["default"]; ok {
		return "default"
	}
	return cmp.Or(f.Mode, "dark")
}

func (f colorsFile) results(variant string) []AuditResult {
	if stored, ok := f.Contrast[variant]; ok {
		return stored
	}
	// Written before generation recorded the audit: measure the file itself.
	view := f.view(variant)
	return auditPalette(view, view, nil)
}

func withTerminalRows(results, dark []AuditResult) []AuditResult {
	terminal := map[string]AuditResult{}
	for _, r := range dark {
		if strings.HasPrefix(r.Key, "dank16term.") {
			terminal[r.Key] = r
		}
	}
	out := make([]AuditResult, len(results))
	for i, r := range results {
		if d, ok := terminal[r.Key]; ok {
			r = d
		}
		out[i] = r
	}
	return out
}

func (f colorsFile) view(variant string) map[string]string {
	view := map[string]string{}
	for role, hex := range f.Colors[variant] {
		view["colors."+role] = hex
	}
	for ns, slots := range map[string]map[string]map[string]string{"dank16": f.Dank16, "dank16term": f.Dank16Term} {
		for slot, variants := range slots {
			view[ns+"."+slot] = variants[variant]
		}
	}
	return view
}
