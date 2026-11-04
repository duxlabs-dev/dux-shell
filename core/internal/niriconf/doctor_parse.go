package niriconf

import (
	"regexp"
	"strings"

	"github.com/sblinch/kdl-go"
	"github.com/sblinch/kdl-go/document"
)

// shortcut: kdl-go rejects a bare name starting with '_' (niri accepts `_JAVA_AWT_WM_NONREPARENTING "1"`); only a name at line start is quoted, enough for environment entries.
var leadingUnderscore = regexp.MustCompile(`(?m)^(\s*)(_[A-Za-z0-9_]*)`)

func parseNiriKDL(data []byte) (*document.Document, error) {
	text := terminateBeforeBrace(leadingUnderscore.ReplaceAllString(string(data), `$1"$2"`))
	return kdl.Parse(strings.NewReader(text))
}

// terminateBeforeBrace adds the `;` kdl-go wants before a `}` that closes a block on the same
// line (`layout { gaps 8 }`, `binds { A { b; } }`), skipping strings and comments. shortcut: raw strings r"…" are not skipped.
func terminateBeforeBrace(text string) string {
	var b strings.Builder
	last := byte(0)
	for i := 0; i < len(text); i++ {
		c := text[i]
		switch {
		case c == '"':
			end := i + 1
			for end < len(text) && text[end] != '"' {
				if text[end] == '\\' {
					end++
				}
				end++
			}
			end = min(end+1, len(text))
			b.WriteString(text[i:end])
			i, last = end-1, '"'
			continue
		case strings.HasPrefix(text[i:], "//"):
			end := strings.IndexByte(text[i:], '\n')
			if end < 0 {
				end = len(text) - i
			}
			b.WriteString(text[i : i+end])
			i += end - 1
			continue
		case strings.HasPrefix(text[i:], "/*"):
			end := len(text)
			if n := strings.Index(text[i+2:], "*/"); n >= 0 {
				end = i + 2 + n + 2
			}
			b.WriteString(text[i:end])
			i = end - 1
			continue
		case c == '}' && last != 0 && !strings.ContainsRune("{;\n", rune(last)):
			b.WriteByte(';')
		}
		b.WriteByte(c)
		if c != ' ' && c != '\t' {
			last = c
		}
	}
	return b.String()
}
