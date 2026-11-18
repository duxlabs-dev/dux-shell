package globalshortcuts

import "strings"

var gnomeModifierTokens = map[string]string{
	"ctrl":    "<Control>",
	"control": "<Control>",
	"shift":   "<Shift>",
	"alt":     "<Alt>",
	"super":   "<Super>",
	"win":     "<Super>",
	"meta":    "<Super>",
	"logo":    "<Super>",
}

var triggerModifiers = map[string]string{
	"control": "Ctrl",
	"ctrl":    "Ctrl",
	"ctl":     "Ctrl",
	"primary": "Ctrl",
	"shift":   "Shift",
	"shft":    "Shift",
	"alt":     "Alt",
	"mod1":    "Alt",
	"super":   "Super",
	"mod4":    "Super",
	"meta":    "Super",
}

func gnomeAccelerator(trigger string) (string, bool) {
	modifiers, key := splitTrigger(trigger)
	if key == "" {
		return "", false
	}

	var accelerator strings.Builder
	for _, modifier := range modifiers {
		token, known := gnomeModifierTokens[strings.ToLower(modifier)]
		if !known {
			return "", false
		}
		accelerator.WriteString(token)
	}
	accelerator.WriteString(key)
	return accelerator.String(), true
}

// xdp-gnome sends NUM as <mod2>, which no trigger can carry, so unknown modifiers are dropped.
func triggerFromGnomeAccelerator(accelerator string) string {
	var parts []string
	rest := strings.TrimSpace(accelerator)
	for strings.HasPrefix(rest, "<") {
		end := strings.IndexByte(rest, '>')
		if end < 0 {
			break
		}
		if modifier, known := triggerModifiers[strings.ToLower(rest[1:end])]; known {
			parts = append(parts, modifier)
		}
		rest = rest[end+1:]
	}
	if rest == "" {
		return ""
	}
	return strings.Join(append(parts, rest), "+")
}

func splitTrigger(trigger string) ([]string, string) {
	trigger = strings.TrimSpace(trigger)
	if modifiers, isPlusKey := strings.CutSuffix(trigger, "++"); isPlusKey {
		return strings.Split(modifiers, "+"), "plus"
	}
	if trigger == "+" {
		return nil, "plus"
	}
	parts := strings.Split(trigger, "+")
	return parts[:len(parts)-1], parts[len(parts)-1]
}
