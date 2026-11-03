package keymap

import (
	"maps"
	"slices"
	"testing"
)

const qwertyKeymap = `xkb_keymap {
xkb_keycodes "(unnamed)" {
	minimum = 8;
	maximum = 708;
	<ESC>  = 9;
	<AB04> = 55;
	<LCTL> = 37;
	<LFSH> = 50;
	alias <AL01> = <AC01>;
	indicator 1 = "Caps Lock";
};
xkb_types "(unnamed)" {
	type "ALPHABETIC" {
		modifiers = Shift+Lock;
		map[Shift] = Level2;
		level_name[Level1] = "Base";
	};
};
xkb_symbols "(unnamed)" {
	key <ESC>  { [ Escape ] };
	key <AB04> { type= "ALPHABETIC", [ v, V ] };
	key <LCTL> { [ Control_L ] };
	key <LFSH> { [ Shift_L ] };
};
};`

const hexKeymap = `xkb_keymap {
xkb_keycodes "(unnamed)" {
	<AB04> = 56;
	<LCTL> = 38;
	<LFSH> = 51;
};
xkb_symbols "(unnamed)" {
	key <LCTL> {	[ 0xffe3 ] };
	key <LFSH> {
		type= "PC_ALT_LEVEL2",
		symbols[1]= [ 0xffe1, 0xfe08 ]
	};
	key <AB04> {	[ 0x76, 0x56 ] };
};
};`

const dvorakKeymap = `xkb_keymap {
xkb_keycodes "(unnamed)" {
	<AB09> = 60;
	<LCTL> = 37;
	<LFSH> = 50;
};
xkb_symbols "(unnamed)" {
	key <AB09> { [ v, V ] };
	key <LCTL> { [ Control_L ] };
	key <LFSH> { [ Shift_L ] };
};
};`

const swapEscapeKeymap = `xkb_keymap {
xkb_keycodes "(unnamed)" {
	<ESC>  = 9;
	<RTRN> = 36;
	<CAPS> = 66;
	<KPEN> = 104;
};
xkb_symbols "(unnamed)" {
	key <ESC>  {	[       Caps_Lock ] };
	key <RTRN> {	[          Return ] };
	key <CAPS> {
		type= "ONE_LEVEL",
		symbols[1]= [          Escape ]
	};
	key <KPEN> {	[        KP_Enter ] };
};
};`

func TestKeycode(t *testing.T) {
	tests := []struct {
		name   string
		keymap string
		sym    string
		want   uint32
	}{
		{"qwerty v", qwertyKeymap, "v", 47},
		{"dvorak v", dvorakKeymap, "v", 52},
		{"hex v", hexKeymap, "v", 48},
		{"hex ctrl", hexKeymap, "Control_L", 30},
		{"hex shift", hexKeymap, "Shift_L", 43},
		{"swapescape escape", swapEscapeKeymap, "Escape", 58},
		{"missing falls back to pc105", dvorakKeymap, "Escape", 1},
		{"empty falls back to pc105", "", "v", 47},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := Parse(tt.keymap).Keycode(tt.sym); got != tt.want {
				t.Errorf("Keycode(%q) = %d, want %d", tt.sym, got, tt.want)
			}
		})
	}
}

func TestKeysym(t *testing.T) {
	tests := []struct {
		name   string
		keymap string
		code   uint32
		want   string
	}{
		{"swapescape caps yields Escape", swapEscapeKeymap, 58, "Escape"},
		{"swapescape esc yields Caps_Lock", swapEscapeKeymap, 1, "Caps_Lock"},
		{"swapescape keypad enter", swapEscapeKeymap, 96, "KP_Enter"},
		{"hex ctrl", hexKeymap, 30, "Control_L"},
		{"unmapped code falls back to pc105", qwertyKeymap, 28, "Return"},
		{"unknown code is empty", qwertyKeymap, 200, ""},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := Parse(tt.keymap).Keysym(tt.code); got != tt.want {
				t.Errorf("Keysym(%d) = %q, want %q", tt.code, got, tt.want)
			}
		})
	}
}

func TestNilKeymapUsesPc105(t *testing.T) {
	var k *Keymap
	if got := k.Keysym(1); got != "Escape" {
		t.Errorf("Keysym(1) = %q, want Escape", got)
	}
	if got := k.Keycode("Control_L"); got != 29 {
		t.Errorf("Keycode(Control_L) = %d, want 29", got)
	}
}

// de:neo reaches bracketleft only on layer 4, which is the shape behind #3585:
// a bind written against it can never match. The compositor hands the keymap
// over with the keysyms as hex, so the ASCII range has to be named back first.
const neoKeymap = `xkb_keymap {
xkb_keycodes "(unnamed)" {
	<AD03> = 26;
	<AD04> = 27;
	<AE01> = 10;
};
xkb_symbols "(unnamed)" {
	key <AD03> { type= "EIGHT_LEVEL", [ 0x6c, 0x4c, 0x5b, Greek_lamda ] };
	key <AD04> { type= "EIGHT_LEVEL", [ c, C, bracketright, Greek_chi ] };
	key <AE01> { [ 0x31, degree ] };
};
};`

// Two layouts in one keymap. The first level of the second group has to count
// as reachable too, otherwise anyone running de,us gets warned about keys that
// work perfectly well.
const twoGroupKeymap = `xkb_keymap {
xkb_keycodes "(unnamed)" {
	<AD03> = 26;
	<AD11> = 34;
};
xkb_symbols "(unnamed)" {
	key <AD03> {
		symbols[1]= [ e, E, EuroSign ],
		symbols[2]= [ e, E ]
	};
	key <AD11> {
		symbols[1]= [ 0xfc, 0xdc ],
		symbols[2]= [ bracketleft, braceleft ]
	};
};
};`

func TestLevel1ByXkbKeycodeKeysTheMapByXkbKeycode(t *testing.T) {
	level1 := Parse(neoKeymap).Level1ByXkbKeycode()

	if got := level1[26]; len(got) != 1 || got[0] != "l" {
		t.Fatalf("xkb keycode 26: got %v, want [l]", got)
	}
	if _, ok := level1[18]; ok {
		t.Fatal("xkb keycode 26 must not also show up under its evdev scancode 18")
	}
}

func TestLevel1ByXkbKeycodeLeavesHigherLevelsOut(t *testing.T) {
	level1 := Parse(neoKeymap).Level1ByXkbKeycode()

	for code, syms := range level1 {
		for _, sym := range syms {
			if sym == "bracketleft" || sym == "bracketright" {
				t.Fatalf("keycode %d reports %q, but neo only has it on layer 4", code, sym)
			}
		}
	}
}

func TestLevel1ByXkbKeycodeKeepsEveryGroup(t *testing.T) {
	level1 := Parse(twoGroupKeymap).Level1ByXkbKeycode()

	if got := level1[26]; len(got) != 2 || got[0] != "e" || got[1] != "e" {
		t.Fatalf("xkb keycode 26: got %v, want [e e]", got)
	}
	got := level1[34]
	if len(got) != 2 || got[1] != "bracketleft" {
		t.Fatalf("xkb keycode 34: got %v, want the second group's bracketleft", got)
	}
}

func TestParseNamesTheAsciiRange(t *testing.T) {
	level1 := Parse(neoKeymap).Level1ByXkbKeycode()

	if got := level1[10]; len(got) != 1 || got[0] != "1" {
		t.Fatalf("0x31 should come back as \"1\", got %v", got)
	}
	if got := Parse(twoGroupKeymap).Level1ByXkbKeycode()[34]; got[0] != "0xfc" {
		t.Fatalf("udiaeresis is outside the named range and must stay hex, got %q", got[0])
	}
}

func TestKeysymNamesCoversWhatParseCanProduce(t *testing.T) {
	names := slices.Collect(maps.Values(KeysymNames))

	for _, want := range []string{"bracketleft", "braceright", "a", "Z", "7", "Escape"} {
		if !slices.Contains(names, want) {
			t.Fatalf("%q missing from the vocabulary", want)
		}
	}
	// udiaeresis has no name here, so a caller must not read its absence from
	// a keymap as "the layout cannot reach it".
	if slices.Contains(names, "udiaeresis") {
		t.Fatal("udiaeresis is not a name this package can produce")
	}
}
