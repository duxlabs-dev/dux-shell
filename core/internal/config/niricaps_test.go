package config

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestProbeNiriCapabilities(t *testing.T) {
	cases := []struct {
		name     string
		accepts  bool
		mismatch bool
		want     []string
	}{
		{"niri 26.04", false, false, nil},
		{"niri main", true, false, []string{NiriCapConfigNext}},
		{"upgraded mid-session", true, true, nil},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := probeNiriCapabilities(func(string) bool { return tc.accepts }, func() bool { return tc.mismatch })
			assert.Equal(t, tc.want, got)
		})
	}
}
