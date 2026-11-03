package sysupdate

import "testing"

func TestParsePkgUpgradeDryRun(t *testing.T) {
	input := `Installed packages to be UPGRADED:
        nano: 8.6 -> 8.7 [FreeBSD]
        wine-devel: 10.19,1 -> 10.20,1 [FreeBSD-ports]

Installed packages to be REINSTALLED:
        foo-1.0 [FreeBSD]
`
	got := parsePkgUpgradeDryRun(input)
	if len(got) != 2 {
		t.Fatalf("got %d packages, want 2: %#v", len(got), got)
	}
	if got[0].Name != "nano" || got[0].FromVersion != "8.6" || got[0].ToVersion != "8.7" {
		t.Fatalf("unexpected first package: %#v", got[0])
	}
	if got[1].Name != "wine-devel" || got[1].ToVersion != "10.20,1" {
		t.Fatalf("unexpected second package: %#v", got[1])
	}
}
