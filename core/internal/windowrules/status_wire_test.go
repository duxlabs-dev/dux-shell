package windowrules

import (
	"encoding/json"
	"testing"

	"github.com/duxlabs-dev/dux-shell/core/internal/configfrag"
)

func marshalKeys(t *testing.T, v any) map[string]json.RawMessage {
	t.Helper()
	data, err := json.Marshal(v)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	var out map[string]json.RawMessage
	if err := json.Unmarshal(data, &out); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	return out
}

func TestDMSRulesStatusKeySpellings(t *testing.T) {
	keys := marshalKeys(t, DMSRulesStatus{
		Exists:          true,
		Included:        true,
		IncludePosition: 2,
		TotalIncludes:   3,
		RulesAfterDMS:   4,
		Effective:       true,
		OverriddenBy:    4,
		StatusMessage:   "DMS window rules are active",
	})

	want := []string{"exists", "included", "includePosition", "totalIncludes", "rulesAfterDms", "effective", "overriddenBy", "statusMessage"}
	if len(keys) != len(want) {
		t.Fatalf("key count = %d, want %d: %v", len(keys), len(want), keys)
	}
	for _, key := range want {
		if _, ok := keys[key]; !ok {
			t.Errorf("missing key %q", key)
		}
	}
}

func TestDMSRulesStatusFromCarriesEveryField(t *testing.T) {
	got := DMSRulesStatusFrom(configfrag.Status{
		Exists:          true,
		Included:        true,
		IncludePosition: 2,
		TotalIncludes:   3,
		EntriesAfterDMS: 7,
		Effective:       true,
		OverriddenBy:    7,
		StatusMessage:   "DMS window rules are active",
	})

	want := DMSRulesStatus{
		Exists:          true,
		Included:        true,
		IncludePosition: 2,
		TotalIncludes:   3,
		RulesAfterDMS:   7,
		Effective:       true,
		OverriddenBy:    7,
		StatusMessage:   "DMS window rules are active",
	}
	if *got != want {
		t.Errorf("DMSRulesStatusFrom = %+v, want %+v", *got, want)
	}
}
