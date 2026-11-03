package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestCheckBundledFonts(t *testing.T) {
	for family, relPaths := range bundledFontRelPaths {
		t.Run(family, func(t *testing.T) {
			shellPath := t.TempDir()
			if missing := checkConfiguredFont("Font", family, shellPath, nil, false, ""); missing.status != statusWarn {
				t.Fatalf("missing bundled font status = %v, want %v", missing.status, statusWarn)
			}
			fontPath := filepath.Join(shellPath, relPaths[0])
			if err := os.MkdirAll(filepath.Dir(fontPath), 0o755); err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(fontPath, []byte("font"), 0o644); err != nil {
				t.Fatal(err)
			}
			for _, name := range []string{family, " " + strings.ToUpper(family) + " "} {
				if result := checkConfiguredFont("Font", name, shellPath, nil, false, ""); result.status != statusOK {
					t.Fatalf("bundled font %q status = %v, want %v", name, result.status, statusOK)
				}
			}
		})
	}
}

func TestQtFontFamilies(t *testing.T) {
	fcOutput := "RobotoMono Nerd Font\tBold\tGOOG\n" +
		"RobotoMono Nerd Font\tBold Italic\tpyrs\n" +
		"Nimbus Sans\tRegular\tURW \n" +
		"Nimbus Sans\tBold\tUKWN\n" +
		"Plex,Plex Lt\tLight,Regular\tIBM\n" +
		"Mono,Mono NF,Mono NF Light\tLight,Regular\tNONE\n"
	families := parseQtFontFamilies(fcOutput)

	cases := map[string]bool{
		"RobotoMono Nerd Font [GOOG]": true,
		"robotomono nerd font [pyrs]": true,
		"RobotoMono Nerd Font":        true,
		"Nimbus Sans [URW ]":          true,
		"Plex Lt":                     true,
		"Plex [IBM]":                  true,
		"Mono NF":                     true,
		"Mono NF Light":               false,
		"Monospace":                   true,
		"Missing Font [GOOG]":         false,
	}
	for name, want := range cases {
		if got := fontInFcList(name, families); got != want {
			t.Errorf("fontInFcList(%q) = %v, want %v", name, got, want)
		}
	}
}
