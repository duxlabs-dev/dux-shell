package sysupdate

import (
	"slices"
	"testing"
)

func TestTerminalWrapperWezterm(t *testing.T) {
	for _, tt := range []struct {
		name      string
		extraArgs []string
		want      []string
	}{
		{
			name: "update",
			want: []string{"wezterm", "start", "--always-new-process", "--class", "dev.duxlabs.shell", "--", "sh", "-c"},
		},
		{
			name:      "extra arguments",
			extraArgs: []string{"--cwd", "/tmp/system update"},
			want:      []string{"wezterm", "start", "--always-new-process", "--class", "dev.duxlabs.shell", "--cwd", "/tmp/system update", "--", "sh", "-c"},
		},
	} {
		t.Run(tt.name, func(t *testing.T) {
			argv := wrapInTerminal("wezterm", "Test", "true", tt.extraArgs)
			if len(argv) != len(tt.want)+1 || !slices.Equal(argv[:len(argv)-1], tt.want) {
				t.Fatalf("argv = %q, want %q followed by the update script", argv, tt.want)
			}
		})
	}
}
