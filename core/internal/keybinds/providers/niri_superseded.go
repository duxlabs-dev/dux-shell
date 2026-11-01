package providers

import (
	"regexp"
	"strings"
)

// supersededDefaults: the native action a stock key used to carry. A user line exactly
// equal to that old stock line was never touched, so it follows the new stock.
var supersededDefaults = map[string]string{
	"Mod+R":       "switch-preset-column-width",
	"Mod+Shift+R": "switch-preset-window-height",
}

type supersededLine struct {
	action string
	line   *regexp.Regexp // the old stock line, no option, alone on its line
}

// supersededByKey is supersededDefaults keyed by normalized key, each old line's
// regexp compiled once at load.
var supersededByKey = func() map[string]supersededLine {
	m := make(map[string]supersededLine, len(supersededDefaults))
	for key, action := range supersededDefaults {
		m[normalizeNiriBindKey(key)] = supersededLine{
			action: action,
			line:   regexp.MustCompile(`(?m)^([ \t]*)` + regexp.QuoteMeta(key) + `[ \t]*\{[ \t]*` + regexp.QuoteMeta(action) + `[ \t]*;[ \t]*\}[ \t]*$`),
		}
	}
	return m
}()

// upgradedBind reports whether old is the superseded stock line of key and cur the
// stock line that replaced it: the one rewrite a merge makes to an existing line.
func upgradedBind(key string, old, cur *overrideBind, stockSet map[string]*overrideBind) bool {
	w := stockSet[key]
	return w != nil && old.Action == supersededByKey[key].action && bindEqual(w, cur)
}

// upgradeSuperseded rewrites, in place, the stock lines of data whose action the stock
// replaced; it returns the keys it rewrote.
func (n *NiriProvider) upgradeSuperseded(data string, stock []*overrideBind) (string, []string) {
	var upgraded []string
	for _, bind := range stock {
		old, ok := supersededByKey[normalizeNiriBindKey(bind.Key)]
		if !ok || !old.line.MatchString(data) {
			continue
		}
		var sb strings.Builder
		n.writeBindNode(&sb, bind, "")
		data = old.line.ReplaceAllString(data, "${1}"+strings.TrimRight(sb.String(), "\n"))
		upgraded = append(upgraded, bind.Key)
	}
	return data, upgraded
}
