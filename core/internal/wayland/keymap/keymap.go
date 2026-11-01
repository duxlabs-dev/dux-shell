package keymap

import (
	"regexp"
	"strconv"
	"strings"

	"github.com/duxlabs-dev/dux-go/wayland/client"
	"golang.org/x/sys/unix"
)

const FormatXkbV1 = 1

// wl_keyboard.key carries evdev scancodes; xkb keycodes sit 8 above them.
const evdevOffset = 8

var pc105Codes = map[string]uint32{
	"Escape":    1,
	"p":         25,
	"Return":    28,
	"Control_L": 29,
	"Shift_L":   42,
	"v":         47,
	"Alt_L":     56,
	"space":     57,
	"KP_Enter":  96,
	"Control_R": 97,
	"Alt_R":     100,
}

var pc105Syms = invert(pc105Codes)

// KeysymNames maps each keysym this package can name to that name. xkbcommon
// may serialize keysyms as hex instead of names, and the keymap a compositor
// hands out on wl_keyboard does exactly that. A keysym absent here is one we
// could not name.
var KeysymNames = buildKeysymNames()

// The ASCII range covers every key a bind is normally written against. Letters
// and digits are named after themselves, the punctuation is not, so it needs
// the table. Anything outside stays hex and callers treat it as unknown.
var asciiPunctuationNames = map[uint32]string{
	0x20: "space",
	0x21: "exclam",
	0x22: "quotedbl",
	0x23: "numbersign",
	0x24: "dollar",
	0x25: "percent",
	0x26: "ampersand",
	0x27: "apostrophe",
	0x28: "parenleft",
	0x29: "parenright",
	0x2a: "asterisk",
	0x2b: "plus",
	0x2c: "comma",
	0x2d: "minus",
	0x2e: "period",
	0x2f: "slash",
	0x3a: "colon",
	0x3b: "semicolon",
	0x3c: "less",
	0x3d: "equal",
	0x3e: "greater",
	0x3f: "question",
	0x40: "at",
	0x5b: "bracketleft",
	0x5c: "backslash",
	0x5d: "bracketright",
	0x5e: "asciicircum",
	0x5f: "underscore",
	0x60: "grave",
	0x7b: "braceleft",
	0x7c: "bar",
	0x7d: "braceright",
	0x7e: "asciitilde",
}

func buildKeysymNames() map[uint32]string {
	names := map[uint32]string{
		0xff0d: "Return",
		0xff1b: "Escape",
		0xff8d: "KP_Enter",
		0xffe1: "Shift_L",
		0xffe3: "Control_L",
		0xffe4: "Control_R",
		0xffe9: "Alt_L",
		0xffea: "Alt_R",
	}
	for value, name := range asciiPunctuationNames {
		names[value] = name
	}
	for _, span := range []struct{ from, to uint32 }{{'0', '9'}, {'A', 'Z'}, {'a', 'z'}} {
		for value := span.from; value <= span.to; value++ {
			names[value] = string(rune(value))
		}
	}
	return names
}

var (
	keycodeDefRe = regexp.MustCompile(`<([A-Za-z0-9+_-]+)>\s*=\s*(\d+)`)
	keySymbolsRe = regexp.MustCompile(`key\s*<([A-Za-z0-9+_-]+)>\s*\{([^}]*)\}`)
	groupIndexRe = regexp.MustCompile(`\w+\[\d+\]\s*=`)
	symbolListRe = regexp.MustCompile(`\[([^\]]*)\]`)
)

// Keymap maps evdev scancodes to their first-group, first-level keysym names.
// A nil Keymap answers with pc105 positions.
type Keymap struct {
	symByCode map[uint32]string
	codeBySym map[string]uint32
	// Every group's first-level keysym, not just the first group's, so a key
	// stays recognisable for people who switch between two layouts.
	groupSyms map[uint32][]string
}

// FromEvent owns and closes the keymap fd; nil means no usable xkb keymap.
func FromEvent(e client.KeyboardKeymapEvent) *Keymap {
	defer unix.Close(e.Fd)
	if e.Format != FormatXkbV1 {
		return nil
	}
	text, err := Read(e.Fd, e.Size)
	if err != nil {
		return nil
	}
	return Parse(text)
}

func Read(fd int, size uint32) (string, error) {
	data, err := unix.Mmap(fd, 0, int(size), unix.PROT_READ, unix.MAP_PRIVATE)
	if err != nil {
		return "", err
	}
	text := strings.TrimRight(string(data), "\x00")
	return text, unix.Munmap(data)
}

func Parse(text string) *Keymap {
	xkbCodes := map[string]uint32{}
	for _, m := range keycodeDefRe.FindAllStringSubmatch(text, -1) {
		if code, err := strconv.Atoi(m[2]); err == nil {
			xkbCodes[m[1]] = uint32(code)
		}
	}

	k := &Keymap{symByCode: map[uint32]string{}, codeBySym: map[string]uint32{}, groupSyms: map[uint32][]string{}}
	for _, m := range keySymbolsRe.FindAllStringSubmatch(text, -1) {
		groups := symbolListRe.FindAllStringSubmatch(groupIndexRe.ReplaceAllString(m[2], ""), -1)
		if len(groups) == 0 {
			continue
		}
		xkbCode, ok := xkbCodes[m[1]]
		if !ok || xkbCode < evdevOffset {
			continue
		}
		sym := canonicalKeysym(strings.TrimSpace(strings.Split(groups[0][1], ",")[0]))
		if sym == "" {
			continue
		}
		code := xkbCode - evdevOffset
		k.symByCode[code] = sym
		if _, seen := k.codeBySym[sym]; !seen {
			k.codeBySym[sym] = code
		}
		k.groupSyms[code] = firstLevelPerGroup(groups)
	}
	return k
}

func (k *Keymap) Keysym(code uint32) string {
	if k == nil {
		return pc105Syms[code]
	}
	if sym, ok := k.symByCode[code]; ok {
		return sym
	}
	return pc105Syms[code]
}

func (k *Keymap) Keycode(sym string) uint32 {
	if k == nil {
		return pc105Codes[sym]
	}
	if code, ok := k.codeBySym[sym]; ok {
		return code
	}
	return pc105Codes[sym]
}

// Level1ByXkbKeycode reports, for every physical key, the keysyms it produces on
// the first level of each layout group, keyed by xkb keycode because that is
// what Qt reports as nativeScanCode. Compositors resolve bind keysyms at the
// first level, so a keysym absent here cannot be reached by any bind.
func (k *Keymap) Level1ByXkbKeycode() map[uint32][]string {
	out := map[uint32][]string{}
	if k == nil {
		for code, sym := range pc105Syms {
			out[code+evdevOffset] = []string{sym}
		}
		return out
	}
	for code, syms := range k.groupSyms {
		out[code+evdevOffset] = syms
	}
	return out
}

func firstLevelPerGroup(groups [][]string) []string {
	syms := make([]string, 0, len(groups))
	for _, group := range groups {
		sym := canonicalKeysym(strings.TrimSpace(strings.Split(group[1], ",")[0]))
		if sym == "" {
			continue
		}
		syms = append(syms, sym)
	}
	return syms
}

func canonicalKeysym(sym string) string {
	if !strings.HasPrefix(sym, "0x") && !strings.HasPrefix(sym, "0X") {
		return sym
	}
	value, err := strconv.ParseUint(sym[2:], 16, 32)
	if err != nil {
		return sym
	}
	if name, ok := KeysymNames[uint32(value)]; ok {
		return name
	}
	return sym
}

func invert(m map[string]uint32) map[uint32]string {
	out := make(map[uint32]string, len(m))
	for sym, code := range m {
		out[code] = sym
	}
	return out
}
