package mangoconf

import (
	"cmp"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"unicode"
)

// MainConfigs are the names Mango loads from its config dir, in lookup order.
func MainConfigs(dir string) []string {
	return []string{filepath.Join(dir, "config.conf"), filepath.Join(dir, "config.toml")}
}

// MainConfig is the file Mango loads from dir, or config.conf when neither exists.
func MainConfig(dir string) string {
	candidates := MainConfigs(dir)
	for _, path := range candidates {
		if _, err := os.Stat(path); err == nil {
			return path
		}
	}
	return candidates[0]
}

func IsTOML(path string) bool {
	return strings.EqualFold(filepath.Ext(path), ".toml")
}

// resolveSource resolves a source path as Mango does: ./ from the config dir, ~/ from $HOME, absolute as is.
// Mango opens any other path against its working directory, so DMS cannot resolve it.
func resolveSource(dir, source string) (string, bool) {
	switch {
	case strings.HasPrefix(source, "./"):
		return filepath.Join(dir, source[2:]), true
	case source == "~" || strings.HasPrefix(source, "~/"):
		return filepath.Join(os.Getenv("HOME"), source[1:]), true
	case filepath.IsAbs(source):
		return filepath.Clean(source), true
	}
	return "", false
}

// Vars is Mango's variable table. One table spans a config and every file it sources.
type Vars map[string]string

var (
	varRef  = regexp.MustCompile(`\$\{[^}]+\}|\$[A-Za-z_]\w*`)
	varName = regexp.MustCompile(`^[A-Za-z_]\w*$`)
)

// expand resolves $name and ${name}; unknown names stay as written, as in Mango.
func (v Vars) expand(value string) string {
	return varRef.ReplaceAllStringFunc(value, func(ref string) string {
		name := strings.TrimSuffix(strings.TrimPrefix(strings.TrimPrefix(ref, "$"), "{"), "}")
		if val, ok := v[name]; ok {
			return val
		}
		return ref
	})
}

func (v Vars) define(value string) {
	name, val, ok := strings.Cut(value, ",")
	if name = strings.TrimSpace(name); ok && varName.MatchString(name) {
		v[name] = strings.TrimSpace(val)
	}
}

// confLine splits a conf line as Mango's conf reader does: a # after whitespace starts a comment,
// and one pair of quotes around the value is dropped.
func confLine(line string) (key, value, comment string, ok bool) {
	line = strings.TrimSpace(line)
	if line == "" || line[0] == '#' {
		return "", "", "", false
	}
	var quote byte
scan:
	for i := 1; i < len(line); i++ {
		c := line[i]
		switch {
		case quote != 0:
			if c == quote {
				quote = 0
			}
		case c == '"' || c == '\'':
			quote = c
		case c == '#' && unicode.IsSpace(rune(line[i-1])):
			line, comment = line[:i], strings.TrimSpace(line[i+1:])
			break scan
		}
	}
	key, value, ok = strings.Cut(line, "=")
	key, value = strings.TrimSpace(key), strings.TrimSpace(value)
	if n := len(value); n >= 2 && (value[0] == '"' || value[0] == '\'') && value[n-1] == value[0] {
		value = strings.TrimSpace(value[1 : n-1])
	}
	return key, value, comment, ok && key != ""
}

func eachConf(content string, vars Vars, emit func(Entry)) {
	var above string
	for line := range strings.SplitSeq(content, "\n") {
		trimmed := strings.TrimSpace(line)
		if c, ok := strings.CutPrefix(trimmed, "#"); ok {
			above = strings.TrimSpace(c)
			continue
		}
		key, value, comment, ok := confLine(trimmed)
		if ok {
			value = vars.expand(value)
			if key == "var" {
				vars.define(value)
			}
			emit(Entry{Key: key, Value: value, Comment: cmp.Or(comment, above)})
		}
		above = ""
	}
}

// readsAsTOML picks the reader as Mango's detect_config_format does: by extension, else TOML
// when the first character outside comments and whitespace is [.
func readsAsTOML(path, content string) bool {
	switch strings.ToLower(filepath.Ext(path)) {
	case ".toml":
		return true
	case ".conf":
		return false
	}
	for line := range strings.SplitSeq(content, "\n") {
		if t := strings.TrimSpace(line); t != "" && t[0] != '#' {
			return t[0] == '['
		}
	}
	return false
}

// Walk visits each option Mango applies, reading a sourced file where it is sourced, as often as it is,
// with vars shared throughout. A source's value is its resolved path, "" when Mango cannot resolve it.
func Walk(dir, path string, vars Vars, visit func(file string, e Entry)) error {
	active := map[string]bool{}
	var walk func(file string) error
	walk = func(file string) error {
		if active[file] {
			return nil
		}
		active[file] = true
		defer delete(active, file)
		data, err := os.ReadFile(file)
		if err != nil {
			return err
		}
		each := eachConf
		if readsAsTOML(file, string(data)) {
			each = eachTOML
		}
		each(string(data), vars, func(e Entry) {
			if e.IsSource() {
				e.Value, _ = resolveSource(dir, e.Value)
			}
			visit(file, e)
			if e.IsSource() && e.Value != "" {
				_ = walk(e.Value)
			}
		})
		return nil
	}
	return walk(filepath.Clean(path))
}

// Entry is one option Mango's TOML reader applies, keyed and valued as its conf reader would take it.
type Entry struct {
	Key, Value string
	// Mode is the key mode of a bind table; other entries follow the running key_mode.
	Mode string
	// Comment is the comment on the statement's line, else on the line above it.
	Comment string
}

// IsSource mirrors Mango, which treats any key starting with source as one.
func (e Entry) IsSource() bool {
	return strings.HasPrefix(e.Key, "source")
}

type tomlKind int

const (
	tomlGlobal tomlKind = iota
	tomlEnv
	tomlVar
	tomlBind
	tomlRule
	tomlSkip
)

type tomlReader struct {
	emit                func(Entry)
	vars                Vars
	kind                tomlKind
	keyword, base, mode string
	pairs               []string
	// A rejected bind table still restores the key_mode it never saved, leaving it empty.
	clearMode bool
}

var tomlBindBases = []struct{ name, base string }{
	{"keybind", "bind"}, {"bind", "bind"}, {"mousebind", "mousebind"},
	{"axisbind", "axisbind"}, {"gesturebind", "gesturebind"}, {"switchbind", "switchbind"},
}

var tomlBindFlags = map[string]string{"sym": "s", "lock": "l", "release": "r", "pass": "p", "conflict": "c"}

var tomlRuleTypes = map[string]bool{
	"monitor_rule": true, "tag_rule": true, "layer_rule": true,
	"window_rule": true, "window_rule_once": true, "device_rule": true,
}

// TOMLEntries returns the options a TOML config applies on its own, in order.
func TOMLEntries(content string) []Entry {
	var out []Entry
	eachTOML(content, Vars{}, func(e Entry) { out = append(out, e) })
	return out
}

// eachTOML follows upstream src/config/toml_parse.c. Values expand when reached, so a var that
// emit defines, say by reading a sourced file, applies to the rest.
func eachTOML(content string, vars Vars, emit func(Entry)) {
	r := tomlReader{emit: emit, vars: vars}
	var stmt, comment string
	for line := range strings.SplitSeq(content, "\n") {
		code, note := tomlCutComment(line)
		code = strings.TrimSpace(code)
		switch {
		case code == "" && stmt == "":
			comment = note
			continue
		case code == "":
			continue
		case stmt == "":
			stmt = code
			if note != "" {
				comment = note
			}
		default:
			stmt += " " + code
		}
		if !tomlComplete(stmt) {
			continue
		}
		r.statement(stmt, comment)
		stmt, comment = "", ""
	}
	if stmt != "" {
		r.statement(stmt, comment)
	}
	r.flush()
}

func (r *tomlReader) apply(key, value, mode, comment string) {
	value = r.vars.expand(value)
	if key == "var" {
		r.vars.define(value)
	}
	r.emit(Entry{Key: key, Value: value, Mode: mode, Comment: comment})
}

func (r *tomlReader) statement(stmt, comment string) {
	if stmt[0] == '[' {
		r.flush()
		r.begin(strings.TrimSpace(strings.TrimRight(strings.TrimLeft(stmt, "["), "]")))
		return
	}
	if r.kind == tomlSkip {
		return
	}
	key, raw, ok := strings.Cut(stmt, "=")
	if !ok {
		return
	}
	key = tomlUnquoteKey(strings.TrimSpace(key))
	raw = strings.TrimSpace(raw)

	switch r.kind {
	case tomlEnv:
		if value := tomlScalar(raw, false); value != "" {
			r.apply("env", key+","+value, "", comment)
		}
	case tomlVar:
		r.apply("var", key+","+tomlScalar(raw, false), "", comment)
	case tomlRule:
		if value := tomlScalar(raw, true); value != "" {
			r.pairs = append(r.pairs, key+":"+r.vars.expand(value))
		}
	case tomlBind:
		prefix, ok := tomlBindPrefix(r.base, r.vars.expand(key))
		if !ok {
			return
		}
		for _, action := range tomlValues(raw) {
			r.apply(r.keyword, prefix+action, r.mode, comment)
		}
	default:
		values := tomlValues(raw)
		if strings.HasPrefix(raw, "[") && tomlJoinsArray(key) {
			values = []string{strings.Join(values, ",")}
		}
		for _, value := range values {
			r.apply(key, value, "", comment)
		}
	}
}

func (r *tomlReader) begin(name string) {
	r.kind, r.keyword, r.base, r.mode = tomlSkip, "", "", ""
	switch {
	case name == "global" || name == "rule":
		r.kind = tomlGlobal
		return
	case name == "env":
		r.kind = tomlEnv
		return
	case name == "var":
		r.kind = tomlVar
		return
	case tomlRuleTypes[strings.TrimPrefix(name, "rule.")]:
		r.kind, r.keyword = tomlRule, strings.TrimPrefix(name, "rule.")
		return
	}

	for _, b := range tomlBindBases {
		suffix, ok := strings.CutPrefix(name, b.name)
		if !ok || (suffix != "" && suffix[0] != '.') {
			continue
		}
		mode, flags := "", ""
		for part := range strings.SplitSeq(suffix, ".") {
			part = strings.TrimSpace(part)
			switch {
			case part == "":
			case mode == "":
				mode = part
			case tomlBindFlags[part] != "":
				flags += tomlBindFlags[part]
			default:
				r.clearMode = true
				return
			}
		}
		// Mango rejects a bind table without its key mode segment.
		if mode == "" {
			r.clearMode = true
			return
		}
		r.kind, r.keyword, r.base, r.mode = tomlBind, b.base+flags, b.base, mode
		return
	}
}

func (r *tomlReader) flush() {
	if r.kind == tomlRule && len(r.pairs) > 0 {
		r.emit(Entry{Key: r.keyword, Value: strings.Join(r.pairs, ",")})
	}
	if r.clearMode {
		r.emit(Entry{Key: "key_mode"})
	}
	r.kind, r.pairs, r.clearMode = tomlGlobal, nil, false
}

// tomlBindPrefix turns "mod+mod+key" into the conf "mod+mod,key," that precedes the action.
func tomlBindPrefix(base, combo string) (string, bool) {
	var segs []string
	for seg := range strings.SplitSeq(combo, "+") {
		if seg = strings.TrimSpace(seg); seg != "" {
			segs = append(segs, seg)
		}
	}
	n := len(segs)
	switch {
	case n == 0:
		return "", false
	case base == "switchbind":
		return segs[0] + ",", true
	case base == "gesturebind":
		if n < 3 {
			return "", false
		}
		return strings.Join(segs[:3], ",") + ",", true
	case n == 1:
		return "none," + segs[0] + ",", true
	}
	return strings.Join(segs[:n-1], "+") + "," + segs[n-1] + ",", true
}

func tomlJoinsArray(key string) bool {
	return strings.HasPrefix(key, "animation_curve_") || key == "scroller_proportion_preset" || key == "circle_layout"
}

func tomlUnquoteKey(key string) string {
	if len(key) >= 2 && (key[0] == '"' || key[0] == '\'') && key[len(key)-1] == key[0] {
		return key[1 : len(key)-1]
	}
	return key
}

// tomlValues returns the non-empty values of a scalar or an array, booleans as 1/0.
func tomlValues(raw string) []string {
	elems := []string{raw}
	if rest, ok := strings.CutPrefix(raw, "["); ok {
		elems = tomlArrayElements(rest)
	}
	var out []string
	for _, elem := range elems {
		if value := tomlScalar(elem, true); value != "" {
			out = append(out, value)
		}
	}
	return out
}

func tomlArrayElements(body string) []string {
	var out []string
	var quote byte
	depth, start := 0, 0
	for i := 0; i < len(body); i++ {
		c := body[i]
		switch {
		case quote != 0:
			// Upstream skips the escaped byte but still lets an escaped quote close the string.
			if c == '\\' && quote == '"' && i+1 < len(body) {
				i++
			}
			if body[i] == quote {
				quote = 0
			}
		case c == '"' || c == '\'':
			quote = c
		case c == '[':
			depth++
		case c == ']' && depth == 0:
			return append(out, body[start:i])
		case c == ']':
			depth--
		case c == ',' && depth == 0:
			out = append(out, body[start:i])
			start = i + 1
		}
	}
	return append(out, body[start:])
}

func tomlScalar(raw string, mapBool bool) string {
	raw = strings.TrimSpace(raw)
	n := len(raw)
	switch {
	case n >= 2 && raw[0] == '"' && raw[n-1] == '"':
		var b strings.Builder
		body := raw[1 : n-1]
		for i := 0; i < len(body); i++ {
			if body[i] != '\\' || i+1 >= len(body) {
				b.WriteByte(body[i])
				continue
			}
			i++
			switch body[i] {
			case 'n':
				b.WriteByte('\n')
			case 't':
				b.WriteByte('\t')
			case 'r':
				b.WriteByte('\r')
			case '"', '\\':
				b.WriteByte(body[i])
			default:
				b.WriteByte('\\')
				b.WriteByte(body[i])
			}
		}
		return b.String()
	case n >= 2 && raw[0] == '\'' && raw[n-1] == '\'':
		return raw[1 : n-1]
	case mapBool && raw == "true":
		return "1"
	case mapBool && raw == "false":
		return "0"
	}
	return raw
}

func tomlCutComment(line string) (code, comment string) {
	var quote byte
	for i := 0; i < len(line); i++ {
		c := line[i]
		switch {
		case quote != 0:
			if c == '\\' && quote == '"' {
				i++
			} else if c == quote {
				quote = 0
			}
		case c == '"' || c == '\'':
			quote = c
		case c == '#':
			return line[:i], strings.TrimSpace(line[i+1:])
		}
	}
	return line, ""
}

// tomlComplete reports whether stmt closes every bracket and string it opens, as Mango requires before applying it.
func tomlComplete(stmt string) bool {
	if stmt[0] == '[' {
		return strings.HasSuffix(stmt, "]")
	}
	_, value, ok := strings.Cut(stmt, "=")
	if !ok {
		return true
	}
	depth := 0
	var quote byte
	for i := 0; i < len(value); i++ {
		c := value[i]
		switch {
		case quote != 0:
			if c == '\\' && quote == '"' {
				i++
			} else if c == quote {
				quote = 0
			}
		case c == '"' || c == '\'':
			quote = c
		case c == '[':
			depth++
		case c == ']' && depth > 0:
			depth--
		}
	}
	return depth == 0 && quote == 0
}
