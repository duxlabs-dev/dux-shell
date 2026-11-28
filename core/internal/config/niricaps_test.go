package config

import (
	"slices"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestProbeNiriCapabilities(t *testing.T) {
	const overview, release = "focus-on-type-in-overview", "F1 { release"
	rejecting := func(syntax ...string) func(string) bool {
		return func(config string) bool {
			for _, s := range syntax {
				if strings.Contains(config, s) {
					return false
				}
			}
			return true
		}
	}
	var all []string
	for _, probe := range niriFeatureProbes {
		all = append(all, probe.capability)
	}
	without := func(caps ...string) []string {
		var kept []string
		for _, c := range all {
			if !slices.Contains(caps, c) {
				kept = append(kept, c)
			}
		}
		return kept
	}

	cases := []struct {
		name     string
		validate func(string) bool
		mismatch bool
		want     []string
	}{
		{"niri 26.04", func(string) bool { return false }, false, nil},
		{"niri main", rejecting(), false, all},
		{"git build between the two", rejecting(overview, release), false, without(NiriCapTypeInOverview, "niri.bind-release")},
		{"upgraded mid-session", rejecting(), true, nil},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := probeNiriCapabilities(tc.validate, func() bool { return tc.mismatch })
			assert.Equal(t, tc.want, got)
		})
	}
}
