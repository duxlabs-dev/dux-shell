package providers

import (
	"maps"
	"regexp"
	"strconv"
	"strings"
)

// Lua configs can express binds dynamically: variables (mainMod .. " + C"),
// tostring() calls, and numeric for loops (workspace binds). This resolves such
// expressions to literal key combos so the static bind parser can read them.

const luaMaxLoopIterations = 1000

var (
	luaAssignRE     = regexp.MustCompile(`^(?:local\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+)$`)
	luaForRE        = regexp.MustCompile(`^for\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(-?\d+)\s*,\s*(-?\d+)\s*(?:,\s*(-?\d+)\s*)?do\b(.*)$`)
	luaTostringRE   = regexp.MustCompile(`to(?:string|number)\s*\(\s*("(?:\\.|[^"])*"|'(?:\\.|[^'])*'|-?\d+(?:\.\d+)?)\s*\)`)
	luaBlockOpenRE  = regexp.MustCompile(`\b(?:function|for|while|if)\b`)
	luaBlockCloseRE = regexp.MustCompile(`\bend\b`)
	luaNumberRE     = regexp.MustCompile(`^-?\d+(?:\.\d+)?$`)
)

type luaVarEnv map[string]string

type luaForHeader struct {
	varName string
	start   int
	stop    int
	step    int
	inline  string
}

func expandLuaConfigLines(lines []string) []string {
	lines, _ = expandLuaConfigLinesEnv(lines)
	return lines
}

func expandLuaConfigLinesEnv(lines []string) ([]string, luaVarEnv) {
	env := luaVarEnv{}
	return expandLuaBlock(joinLuaBindSpans(lines), env), env
}

// The bind parser is line based; fold wrapped hl.bind( calls, keeping only the closing line's comment.
func joinLuaBindSpans(lines []string) []string {
	out := make([]string, 0, len(lines))
	for i := 0; i < len(lines); i++ {
		masked := luaMaskStrings(lines[i])
		depth := luaParenDelta(masked)
		if depth <= 0 || !strings.Contains(masked, "hl.bind") {
			out = append(out, lines[i])
			continue
		}
		parts := []string{strings.TrimSpace(luaStripLineComment(lines[i]))}
		j := i + 1
		for ; j < len(lines) && depth > 0; j++ {
			depth += luaParenDelta(luaMaskStrings(lines[j]))
			part := lines[j]
			if depth > 0 {
				part = luaStripLineComment(part)
			}
			if part = strings.TrimSpace(part); part != "" {
				parts = append(parts, part)
			}
		}
		if depth > 0 {
			out = append(out, lines[i])
			continue
		}
		out = append(out, strings.Join(parts, " "))
		i = j - 1
	}
	return out
}

func luaParenDelta(masked string) int {
	return strings.Count(masked, "(") - strings.Count(masked, ")")
}

func expandLuaBlock(lines []string, env luaVarEnv) []string {
	out := make([]string, 0, len(lines))
	for i := 0; i < len(lines); i++ {
		code := strings.TrimSpace(luaStripLineComment(lines[i]))

		if name, value, ok := parseLuaStringAssignment(code, env); ok {
			env[name] = value
			out = append(out, lines[i])
			continue
		}

		header, ok := parseLuaForHeader(code)
		if !ok {
			out = append(out, resolveLuaDynamicLine(lines[i], env))
			continue
		}

		body, consumed, complete := collectLuaForBody(header, lines, i)
		if !complete {
			out = append(out, resolveLuaDynamicLine(lines[i], env))
			continue
		}
		out = append(out, expandLuaForLoop(header, body, env)...)
		i = consumed
	}
	return out
}

func parseLuaStringAssignment(code string, env luaVarEnv) (name, value string, ok bool) {
	m := luaAssignRE.FindStringSubmatch(code)
	if m == nil {
		return "", "", false
	}
	value, ok = evalLuaConcat(m[2], env)
	if !ok {
		return "", "", false
	}
	return m[1], value, true
}

func parseLuaForHeader(code string) (luaForHeader, bool) {
	m := luaForRE.FindStringSubmatch(code)
	if m == nil {
		return luaForHeader{}, false
	}
	start, _ := strconv.Atoi(m[2])
	stop, _ := strconv.Atoi(m[3])
	step := 1
	if m[4] != "" {
		step, _ = strconv.Atoi(m[4])
	}
	if step == 0 {
		return luaForHeader{}, false
	}
	return luaForHeader{varName: m[1], start: start, stop: stop, step: step, inline: strings.TrimSpace(m[5])}, true
}

func collectLuaForBody(header luaForHeader, lines []string, headerIdx int) (body []string, consumed int, complete bool) {
	depth := 1
	if header.inline != "" {
		delta := luaBlockDelta(header.inline)
		if depth+delta <= 0 {
			if stmt := strings.TrimSpace(strings.TrimSuffix(strings.TrimSpace(header.inline), "end")); stmt != "" {
				body = append(body, stmt)
			}
			return body, headerIdx, true
		}
		depth += delta
		body = append(body, header.inline)
	}
	for j := headerIdx + 1; j < len(lines); j++ {
		delta := luaBlockDelta(lines[j])
		if depth+delta <= 0 {
			return body, j, true
		}
		depth += delta
		body = append(body, lines[j])
	}
	return nil, headerIdx, false
}

func expandLuaForLoop(header luaForHeader, body []string, env luaVarEnv) []string {
	var out []string
	inRange := func(v int) bool {
		if header.step > 0 {
			return v <= header.stop
		}
		return v >= header.stop
	}
	count := 0
	for v := header.start; inRange(v); v += header.step {
		if count++; count > luaMaxLoopIterations {
			break
		}
		value := strconv.Itoa(v)
		iterLines := make([]string, len(body))
		for k, bl := range body {
			iterLines[k] = substituteLuaIdent(bl, header.varName, value)
		}
		out = append(out, expandLuaBlock(iterLines, cloneLuaEnv(env))...)
	}
	return out
}

func luaBlockDelta(line string) int {
	masked := luaMaskStrings(line)
	return len(luaBlockOpenRE.FindAllString(masked, -1)) - len(luaBlockCloseRE.FindAllString(masked, -1))
}

func resolveLuaDynamicLine(line string, env luaVarEnv) string {
	if !strings.Contains(line, "hl.bind") && !strings.Contains(line, "hl.unbind") {
		return line
	}
	line = normalizeLuaToString(line)
	return rewriteLuaBindKeyArg(line, env)
}

func normalizeLuaToString(line string) string {
	return luaTostringRE.ReplaceAllStringFunc(line, func(m string) string {
		inner := luaTostringRE.FindStringSubmatch(m)[1]
		if inner[0] == '"' || inner[0] == '\'' {
			return inner
		}
		return strconv.Quote(inner)
	})
}

func rewriteLuaBindKeyArg(line string, env luaVarEnv) string {
	for _, fn := range []string{"hl.bind", "hl.unbind"} {
		idx := strings.Index(line, fn)
		if idx < 0 {
			continue
		}
		open := skipLuaWS(line, idx+len(fn))
		if open >= len(line) || line[open] != '(' {
			continue
		}
		argStart := skipLuaWS(line, open+1)
		expr, end, ok := parseLuaFirstArgExpr(line, argStart)
		if !ok || isLuaPlainStringArg(expr) {
			continue
		}
		value, ok := evalLuaConcat(expr, env)
		if !ok {
			continue
		}
		return line[:argStart] + strconv.Quote(value) + line[end:]
	}
	return line
}

func evalLuaConcat(expr string, env luaVarEnv) (string, bool) {
	parts := splitLuaConcat(expr)
	var sb strings.Builder
	for _, part := range parts {
		value, ok := evalLuaOperand(part, env)
		if !ok {
			return "", false
		}
		sb.WriteString(value)
	}
	return sb.String(), true
}

func evalLuaOperand(op string, env luaVarEnv) (string, bool) {
	op = strings.TrimSpace(op)
	if op == "" {
		return "", false
	}
	switch op[0] {
	case '"', '\'':
		s, next, ok := parseLuaStringLiteral(op, 0)
		return s, next == len(op) && ok
	}
	if luaNumberRE.MatchString(op) {
		return op, true
	}
	if inner, ok := luaUnwrapCall(op, "tostring"); ok {
		return evalLuaConcat(inner, env)
	}
	if inner, ok := luaUnwrapCall(op, "tonumber"); ok {
		return evalLuaConcat(inner, env)
	}
	if value, ok := env[op]; ok {
		return value, true
	}
	return "", false
}

func splitLuaConcat(expr string) []string {
	var parts []string
	parenDepth, braceDepth, bracketDepth := 0, 0, 0
	inStr := byte(0)
	esc := false
	start := 0
	for i := 0; i < len(expr); i++ {
		c := expr[i]
		if inStr != 0 {
			switch {
			case esc:
				esc = false
			case c == '\\' && inStr == '"':
				esc = true
			case c == inStr:
				inStr = 0
			}
			continue
		}
		switch c {
		case '"', '\'':
			inStr = c
		case '(':
			parenDepth++
		case ')':
			if parenDepth > 0 {
				parenDepth--
			}
		case '{':
			braceDepth++
		case '}':
			if braceDepth > 0 {
				braceDepth--
			}
		case '[':
			bracketDepth++
		case ']':
			if bracketDepth > 0 {
				bracketDepth--
			}
		case '.':
			if parenDepth == 0 && braceDepth == 0 && bracketDepth == 0 && i+1 < len(expr) && expr[i+1] == '.' {
				parts = append(parts, expr[start:i])
				i++
				start = i + 1
			}
		}
	}
	return append(parts, expr[start:])
}

func substituteLuaIdent(line, name, value string) string {
	if !strings.Contains(line, name) {
		return line
	}
	var sb strings.Builder
	inStr := byte(0)
	esc := false
	for i := 0; i < len(line); {
		c := line[i]
		if inStr != 0 {
			sb.WriteByte(c)
			switch {
			case esc:
				esc = false
			case c == '\\' && inStr == '"':
				esc = true
			case c == inStr:
				inStr = 0
			}
			i++
			continue
		}
		if c == '"' || c == '\'' {
			inStr = c
			sb.WriteByte(c)
			i++
			continue
		}
		if isLuaIdentStart(c) {
			j := i + 1
			for j < len(line) && isLuaIdentByte(line[j]) {
				j++
			}
			word := line[i:j]
			if word == name && (i == 0 || line[i-1] != '.') {
				sb.WriteString(value)
			} else {
				sb.WriteString(word)
			}
			i = j
			continue
		}
		sb.WriteByte(c)
		i++
	}
	return sb.String()
}

func luaMaskStrings(line string) string {
	b := []byte(line)
	inStr := byte(0)
	esc := false
	for i := 0; i < len(b); i++ {
		c := b[i]
		if inStr != 0 {
			wasEnd := !esc && c == inStr
			esc = !esc && c == '\\' && inStr == '"'
			b[i] = ' '
			if wasEnd {
				inStr = 0
			}
			continue
		}
		switch c {
		case '"', '\'':
			inStr = c
			b[i] = ' '
		case '-':
			if i+1 < len(b) && b[i+1] == '-' {
				for ; i < len(b); i++ {
					b[i] = ' '
				}
			}
		}
	}
	return string(b)
}

func luaStripLineComment(line string) string {
	inStr := byte(0)
	esc := false
	for i := 0; i+1 < len(line); i++ {
		c := line[i]
		if inStr != 0 {
			switch {
			case esc:
				esc = false
			case c == '\\' && inStr == '"':
				esc = true
			case c == inStr:
				inStr = 0
			}
			continue
		}
		switch c {
		case '"', '\'':
			inStr = c
		case '-':
			if line[i+1] == '-' {
				return line[:i]
			}
		}
	}
	return line
}

func luaUnwrapCall(op, fn string) (string, bool) {
	op = strings.TrimSpace(op)
	if !strings.HasPrefix(op, fn) {
		return "", false
	}
	rest := strings.TrimSpace(op[len(fn):])
	if !strings.HasPrefix(rest, "(") || !strings.HasSuffix(rest, ")") {
		return "", false
	}
	return rest[1 : len(rest)-1], true
}

func isLuaPlainStringArg(expr string) bool {
	expr = strings.TrimSpace(expr)
	if expr == "" || (expr[0] != '"' && expr[0] != '\'') {
		return false
	}
	_, next, ok := parseLuaStringLiteral(expr, 0)
	return ok && next == len(expr)
}

func isLuaIdentStart(c byte) bool {
	return c == '_' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

func cloneLuaEnv(env luaVarEnv) luaVarEnv {
	clone := make(luaVarEnv, len(env))
	maps.Copy(clone, env)
	return clone
}
