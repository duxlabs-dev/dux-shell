package keybinds

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

func TestDMSBindsStatusKeySpellings(t *testing.T) {
	keys := marshalKeys(t, DMSBindsStatus{
		Exists:          true,
		Included:        true,
		IncludePosition: 2,
		TotalIncludes:   3,
		BindsAfterDMS:   4,
		Effective:       true,
		OverriddenBy:    4,
		StatusMessage:   "DMS binds are active",
	})

	want := []string{"exists", "included", "includePosition", "totalIncludes", "bindsAfterDms", "effective", "overriddenBy", "statusMessage"}
	if len(keys) != len(want) {
		t.Fatalf("key count = %d, want %d: %v", len(keys), len(want), keys)
	}
	for _, key := range want {
		if _, ok := keys[key]; !ok {
			t.Errorf("missing key %q", key)
		}
	}
}

func TestDMSBindsStatusFromCarriesEveryField(t *testing.T) {
	got := DMSBindsStatusFrom(configfrag.Status{
		Exists:          true,
		Included:        true,
		IncludePosition: 2,
		TotalIncludes:   3,
		EntriesAfterDMS: 7,
		Effective:       true,
		OverriddenBy:    7,
		StatusMessage:   "DMS binds are active",
	})

	want := DMSBindsStatus{
		Exists:          true,
		Included:        true,
		IncludePosition: 2,
		TotalIncludes:   3,
		BindsAfterDMS:   7,
		Effective:       true,
		OverriddenBy:    7,
		StatusMessage:   "DMS binds are active",
	}
	if *got != want {
		t.Errorf("DMSBindsStatusFrom = %+v, want %+v", *got, want)
	}
}
