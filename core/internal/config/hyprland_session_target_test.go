package config

import (
	"os"
	"path/filepath"
	"testing"
)

func writeUnit(t *testing.T, path, content string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestEnsureHyprlandSessionTarget(t *testing.T) {
	const custom = "[Unit]\nDescription=mine\n"
	ours := append([]string{hyprlandSessionTargetUnit}, staleHyprlandSessionTargetUnits...)

	type tc struct {
		name     string
		user     string
		packaged bool
		wantUser string // "" means the user unit must not exist
		wantPkg  bool
	}
	cases := []tc{
		{name: "missing, no packaged unit", wantUser: hyprlandSessionTargetUnit},
		{name: "missing, packaged unit", packaged: true, wantPkg: true},
		{name: "custom, no packaged unit", user: custom, wantUser: custom},
		{name: "custom, packaged unit", user: custom, packaged: true, wantUser: custom},
	}
	for i, unit := range ours {
		cases = append(cases,
			tc{name: "ours " + string(rune('a'+i)) + ", no packaged unit", user: unit, wantUser: hyprlandSessionTargetUnit},
			tc{name: "ours " + string(rune('a'+i)) + ", packaged unit", user: unit, packaged: true, wantPkg: true},
		)
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			root := t.TempDir()
			userPath := filepath.Join(root, "home", "hyprland-session.target")
			pkgDirs := []string{filepath.Join(root, "usr-lib"), filepath.Join(root, "usr-local-lib")}
			pkgPath := filepath.Join(pkgDirs[1], "hyprland-session.target")
			if c.user != "" {
				writeUnit(t, userPath, c.user)
			}
			if c.packaged {
				writeUnit(t, pkgPath, "[Unit]\nDescription=Hyprland session\n")
			}

			got, err := ensureHyprlandSessionTarget(userPath, pkgDirs)
			if err != nil {
				t.Fatal(err)
			}

			data, readErr := os.ReadFile(userPath)
			switch {
			case c.wantUser == "" && readErr == nil:
				t.Fatalf("user unit should be gone, has:\n%s", data)
			case c.wantUser != "" && string(data) != c.wantUser:
				t.Fatalf("user unit = %q, want %q", data, c.wantUser)
			}
			wantPath := userPath
			if c.wantPkg {
				wantPath = pkgPath
			}
			if got != wantPath {
				t.Fatalf("path = %s, want %s", got, wantPath)
			}
		})
	}
}
