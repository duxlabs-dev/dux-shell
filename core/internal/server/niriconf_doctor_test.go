package server

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/duxlabs-dev/dux-shell/core/internal/niriconf"
	"github.com/stretchr/testify/require"
)

func TestNiriConfigDoctorFixesInclude(t *testing.T) {
	setupNiriConfig(t)
	dms := filepath.Join(os.Getenv("XDG_CONFIG_HOME"), "niri", "dms")
	require.NoError(t, os.MkdirAll(dms, 0o755))
	require.NoError(t, os.WriteFile(filepath.Join(dms, "alttab.kdl"), []byte("recent-windows { off; }\n"), 0o644))

	raw, errText := callNiriConfig(t, "niri.config.doctor", map[string]any{"appIds": []any{"foot"}})
	require.Empty(t, errText)
	var report niriconf.Report
	require.NoError(t, json.Unmarshal(raw, &report))
	require.Len(t, report.Findings, 1)
	require.Equal(t, niriconf.FixAddInclude, report.Findings[0].Fix)

	raw, errText = callNiriConfig(t, "niri.config.doctor", map[string]any{"fix": niriconf.FixAddInclude, "fragment": "alttab.kdl"})
	require.Empty(t, errText)
	require.NoError(t, json.Unmarshal(raw, &report))
	require.Empty(t, report.Findings)
	require.True(t, report.Undo)

	raw, errText = callNiriConfig(t, "niri.config.doctor", map[string]any{"fix": niriconf.FixUndoInclude})
	require.Empty(t, errText)
	report = niriconf.Report{}
	require.NoError(t, json.Unmarshal(raw, &report))
	require.Len(t, report.Findings, 1)
	require.False(t, report.Undo)

	_, errText = callNiriConfig(t, "niri.config.doctor", map[string]any{"fix": niriconf.FixUndoInclude})
	require.Equal(t, "nothing to undo", errText)
}

func TestNiriConfigDoctorErrors(t *testing.T) {
	setupNiriConfig(t)
	for want, p := range map[string]map[string]any{
		"bad fix": {"fix": "remove-rule"},
		"missing or invalid 'fragment' parameter": {"fix": niriconf.FixAddInclude},
		"bad name":                        {"fix": niriconf.FixAddInclude, "fragment": "../x.kdl"},
		"stat: no such file or directory": {"fix": niriconf.FixAddInclude, "fragment": "gone.kdl"},
	} {
		_, errText := callNiriConfig(t, "niri.config.doctor", p)
		require.Equal(t, want, errText)
	}
}
