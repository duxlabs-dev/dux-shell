package providers

import (
	"os"
	"testing"

	"github.com/duxlabs-dev/dux-shell/core/internal/windowrules"
)

// Writes must not depend on whichever niri happens to be installed.
func TestMain(m *testing.M) {
	niriValidateRules = func(string) error { return nil }
	os.Exit(m.Run())
}

func newTestWindowRule(id, name, appID string) windowrules.WindowRule {
	return windowrules.WindowRule{
		ID:      id,
		Name:    name,
		Enabled: true,
		MatchCriteria: windowrules.MatchCriteria{
			AppID: appID,
		},
	}
}
