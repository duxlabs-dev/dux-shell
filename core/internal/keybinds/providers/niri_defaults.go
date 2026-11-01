package providers

import (
	"os"
	"strings"

	"github.com/duxlabs-dev/dux-shell/core/internal/config"
	"github.com/duxlabs-dev/dux-shell/core/internal/niriconf"
)

// bindsBackup is the one copy of dms/binds.kdl kept before missing defaults land in it.
func (n *NiriProvider) bindsBackup() string {
	return n.GetOverridePath() + ".dms-bak"
}

// MergeMissingDefaults adds every embedded default bind whose key is bound nowhere (not in
// dms/binds.kdl, config.kdl or its includes); every existing line is kept. The merged file is
// validated first, the old one kept beside it for UndoMergeDefaults. Returns the keys added,
// nil when nothing was missing.
func (n *NiriProvider) MergeMissingDefaults(terminalCommand string) ([]string, error) {
	stock, err := n.stockDefaults(terminalCommand)
	if err != nil {
		return nil, err
	}

	data, err := os.ReadFile(n.GetOverridePath())
	if err != nil && !os.IsNotExist(err) {
		return nil, err
	}

	merged, added, err := n.mergeBinds(data, stock)
	if err != nil {
		return nil, err
	}
	if len(added) == 0 {
		return nil, nil
	}
	if err := n.validateBindsContent(merged); err != nil {
		return nil, err
	}
	if len(data) > 0 {
		if err := os.WriteFile(n.bindsBackup(), data, 0o600); err != nil {
			return nil, err
		}
		if err := os.Chmod(n.bindsBackup(), 0o600); err != nil { // WriteFile keeps an existing file's mode
			return nil, err
		}
	}
	if err := niriconf.WriteAtomic(n.GetOverridePath(), []byte(merged)); err != nil {
		return nil, err
	}
	return added, nil
}

// UndoMergeDefaults puts dms/binds.kdl back as it was before the last
// MergeMissingDefaults, unless the file changed since.
func (n *NiriProvider) UndoMergeDefaults(terminalCommand string) error {
	old, err := os.ReadFile(n.bindsBackup())
	if os.IsNotExist(err) {
		return niriconf.ErrNoUndo
	}
	if err != nil {
		return err
	}

	current, err := os.ReadFile(n.GetOverridePath())
	if err != nil {
		return err
	}

	if !n.undoSafe(old, current, terminalCommand) {
		return niriconf.ErrChanged
	}

	if err := niriconf.WriteAtomic(n.GetOverridePath(), old); err != nil {
		return err
	}
	os.Remove(n.bindsBackup())
	return nil
}

// undoSafe reports whether current is exactly old plus the stock defaults a
// merge would add to old. kdl-go renders properties in map order, so two
// renders of the same binds differ half the time: the check compares binds,
// never rendered bytes.
func (n *NiriProvider) undoSafe(old, current []byte, terminalCommand string) bool {
	oldBinds, err := n.bindsFromData(old)
	if err != nil {
		return false
	}
	curBinds, err := n.bindsFromData(current)
	if err != nil {
		return false
	}
	stock, err := n.stockDefaults(terminalCommand)
	if err != nil {
		return false
	}

	oldSet := bindSet(oldBinds)
	curSet := bindSet(curBinds)
	want, err := n.missingDefaults(old, stock)
	if err != nil {
		return false
	}

	for key, b := range oldSet {
		c, ok := curSet[key]
		if !ok || !bindEqual(b, c) {
			return false
		}
	}
	for key, b := range curSet {
		if _, kept := oldSet[key]; kept {
			continue
		}
		w, ok := want[key]
		if !ok || !bindEqual(w, b) {
			return false
		}
	}
	for key, w := range want {
		c, ok := curSet[key]
		if !ok || !bindEqual(w, c) {
			return false
		}
	}
	return true
}

// missingDefaults: the defaults a merge would add to data, stock keys bound nowhere yet.
func (n *NiriProvider) missingDefaults(data []byte, stock []*overrideBind) (map[string]*overrideBind, error) {
	bound, err := n.boundKeys(data)
	if err != nil {
		return nil, err
	}
	want := map[string]*overrideBind{}
	for _, b := range stock {
		key := normalizeNiriBindKey(b.Key)
		if !bound[key] {
			want[key] = b
		}
	}
	return want, nil
}

func bindSet(binds []*overrideBind) map[string]*overrideBind {
	set := make(map[string]*overrideBind, len(binds))
	for _, b := range binds {
		set[normalizeNiriBindKey(b.Key)] = b
	}
	return set
}

func bindEqual(a, b *overrideBind) bool {
	if a.Action != b.Action || a.Description != b.Description {
		return false
	}
	for _, k := range []string{"repeat", "allow-when-locked", "allow-inhibiting"} {
		if optionBool(a.Options, k) != optionBool(b.Options, k) {
			return false
		}
	}
	return optionInt(a.Options, "cooldown-ms") == optionInt(b.Options, "cooldown-ms")
}

// optionBool reads the options a bind can render (buildBindNode): absent and
// false mean the same thing, so no "was set" distinction exists.
func optionBool(m map[string]any, key string) bool {
	v, ok := m[key].(bool)
	return ok && v
}

func optionInt(m map[string]any, key string) int {
	v, _ := m[key].(int)
	return v
}

func (n *NiriProvider) stockDefaults(terminalCommand string) ([]*overrideBind, error) {
	stock := strings.ReplaceAll(config.NiriBindsConfig, "{{TERMINAL_COMMAND}}", terminalCommand)
	return n.bindsFromData([]byte(stock))
}

// mergeBinds renders the stock binds missing from data into data's first top-level
// binds node. Empty data yields the whole stock file; every existing line is kept.
// It returns the keys it added.
func (n *NiriProvider) mergeBinds(data []byte, stock []*overrideBind) (string, []string, error) {
	skip, err := n.boundKeys(data)
	if err != nil {
		return "", nil, err
	}

	content := string(data)
	var lines, added []string
	for _, bind := range stock {
		if skip[normalizeNiriBindKey(bind.Key)] {
			continue
		}
		added = append(added, bind.Key)
		var sb strings.Builder
		n.writeBindNode(&sb, bind, "    ")
		lines = append(lines, strings.TrimRight(sb.String(), "\n"))
	}
	if len(added) == 0 {
		return content, added, nil
	}
	body := strings.Join(lines, "\n") + "\n"

	if len(content) == 0 {
		return "binds {\n" + body + "}\n", added, nil
	}
	if merged, ok := insertBindsLines(content, body); ok {
		return merged, added, nil
	}
	// No binds node to extend: a fresh one carries the missing defaults.
	return strings.TrimRight(content, "\n") + "\n\nbinds {\n" + body + "}\n", added, nil
}

// boundKeys collects the keys already bound in data and in the config.kdl include
// chain, so a default lands nowhere a bind of the user's already lives.
func (n *NiriProvider) boundKeys(data []byte) (map[string]bool, error) {
	binds, err := n.bindsFromData(data)
	if err != nil {
		return nil, err
	}
	skip := map[string]bool{}
	for _, bind := range binds {
		skip[normalizeNiriBindKey(bind.Key)] = true
	}
	parser := NewNiriParser(n.configDir)
	if _, err := parser.Parse(); err != nil {
		return nil, err
	}
	for key := range parser.configBindKeys {
		skip[key] = true
	}
	return skip, nil
}

// insertBindsLines returns content with body added just before the brace that
// closes its first top-level binds node, false when the file has none.
func insertBindsLines(content, body string) (string, bool) {
	end := bindsBlockEnd(content)
	if end < 0 {
		return content, false
	}
	var b strings.Builder
	b.WriteString(content[:end])
	if end == 0 || content[end-1] != '\n' {
		b.WriteString("\n")
	}
	b.WriteString(body)
	b.WriteString(content[end:])
	return b.String(), true
}

// bindsBlockEnd scans KDL text, strings and comments skipped, for the index of
// the brace closing the first node named binds at the top level, -1 when absent.
func bindsBlockEnd(s string) int {
	depth := 0
	inBinds := false
	last := ""
	for i := 0; i < len(s); i++ {
		c := s[i]
		switch {
		case c == '"':
			for i++; i < len(s); i++ {
				if s[i] == '\\' {
					i++
				} else if s[i] == '"' {
					break
				}
			}
		case c == '/' && i+1 < len(s) && s[i+1] == '/':
			for i < len(s) && s[i] != '\n' {
				i++
			}
		case c == '/' && i+1 < len(s) && s[i+1] == '*':
			i += 2
			for i+1 < len(s) && !(s[i] == '*' && s[i+1] == '/') {
				i++
			}
			i++
		case c == '{':
			if depth == 0 {
				inBinds = last == "binds"
				last = ""
			}
			depth++
		case c == '}':
			depth--
			if depth == 0 && inBinds {
				return i
			}
		case isBindsIdentByte(c):
			j := i
			for j < len(s) && isBindsIdentByte(s[j]) {
				j++
			}
			if depth == 0 {
				last = s[i:j]
			}
			i = j - 1
		}
	}
	return -1
}

func isBindsIdentByte(c byte) bool {
	return c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' || c == '_' || c == '-'
}
