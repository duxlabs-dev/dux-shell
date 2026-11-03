package windowrules

import (
	"errors"
	"testing"
)

type fakeStore struct {
	rules      []WindowRule
	written    []WindowRule
	wrote      bool
	loadErr    error
	writableEr error
	loads      int
}

func (f *fakeStore) EnsureWritable() error { return f.writableEr }

func (f *fakeStore) LoadDMSRules() ([]WindowRule, error) {
	f.loads++
	if f.loadErr != nil {
		return nil, f.loadErr
	}
	return append([]WindowRule(nil), f.rules...), nil
}

func (f *fakeStore) WriteDMSRules(rules []WindowRule) error {
	f.written = rules
	f.wrote = true
	return nil
}

func storeWith(ids ...string) *fakeStore {
	rules := make([]WindowRule, 0, len(ids))
	for _, id := range ids {
		rules = append(rules, WindowRule{ID: id})
	}
	return &fakeStore{rules: rules}
}

func writtenIDs(store *fakeStore) []string {
	out := make([]string, 0, len(store.written))
	for _, rule := range store.written {
		out = append(out, rule.ID)
	}
	return out
}

func assertIDs(t *testing.T, store *fakeStore, want ...string) {
	t.Helper()
	got := writtenIDs(store)
	if len(got) != len(want) {
		t.Fatalf("wrote %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("wrote %v, want %v", got, want)
		}
	}
}

func TestSetAppendsARuleWithANewID(t *testing.T) {
	store := storeWith("a", "b")
	if err := Set(store, WindowRule{ID: "c"}); err != nil {
		t.Fatalf("Set: %v", err)
	}
	assertIDs(t, store, "a", "b", "c")
}

func TestSetReplacesAnExistingRuleInPlace(t *testing.T) {
	store := storeWith("a", "b", "c")
	if err := Set(store, WindowRule{ID: "b", Name: "renamed"}); err != nil {
		t.Fatalf("Set: %v", err)
	}
	assertIDs(t, store, "a", "b", "c")
	if store.written[1].Name != "renamed" {
		t.Errorf("rule b name = %q, want renamed", store.written[1].Name)
	}
}

func TestSetStartsFromEmptyWhenTheFragmentCannotBeRead(t *testing.T) {
	store := &fakeStore{loadErr: errors.New("unreadable")}
	if err := Set(store, WindowRule{ID: "a"}); err != nil {
		t.Fatalf("Set: %v", err)
	}
	assertIDs(t, store, "a")
}

func TestRemoveDropsOnlyTheNamedRule(t *testing.T) {
	store := storeWith("a", "b", "c")
	if err := Remove(store, "b"); err != nil {
		t.Fatalf("Remove: %v", err)
	}
	assertIDs(t, store, "a", "c")
}

func TestRemovePropagatesALoadFailure(t *testing.T) {
	store := &fakeStore{loadErr: errors.New("unreadable")}
	if err := Remove(store, "a"); err == nil {
		t.Fatal("Remove must fail when the fragment cannot be read")
	}
	if store.wrote {
		t.Error("Remove must not write after a failed load")
	}
}

func TestReorderWithAFullListProducesExactlyThatOrder(t *testing.T) {
	store := storeWith("a", "b", "c")
	if err := Reorder(store, []string{"c", "a", "b"}); err != nil {
		t.Fatalf("Reorder: %v", err)
	}
	assertIDs(t, store, "c", "a", "b")
}

func TestReorderIgnoresAnUnknownID(t *testing.T) {
	store := storeWith("a", "b")
	if err := Reorder(store, []string{"b", "ghost", "a"}); err != nil {
		t.Fatalf("Reorder: %v", err)
	}
	assertIDs(t, store, "b", "a")
}

func TestReorderWithASubsetKeepsLeftoversInTheirOriginalOrder(t *testing.T) {
	store := storeWith("a", "b", "c", "d", "e")
	if err := Reorder(store, []string{"e", "c"}); err != nil {
		t.Fatalf("Reorder: %v", err)
	}
	assertIDs(t, store, "e", "c", "a", "b", "d")
}

func TestReorderWithAnEmptyListKeepsTheOriginalOrder(t *testing.T) {
	store := storeWith("a", "b", "c")
	if err := Reorder(store, nil); err != nil {
		t.Fatalf("Reorder: %v", err)
	}
	assertIDs(t, store, "a", "b", "c")
}

func TestReorderIgnoresADuplicateID(t *testing.T) {
	store := storeWith("a", "b")
	if err := Reorder(store, []string{"b", "b", "a"}); err != nil {
		t.Fatalf("Reorder: %v", err)
	}
	assertIDs(t, store, "b", "a")
}

func TestAReadOnlyConfigIsRefusedBeforeTheFragmentIsRead(t *testing.T) {
	refusal := errors.New("read-only")
	for name, call := range map[string]func(*fakeStore) error{
		"Set":     func(s *fakeStore) error { return Set(s, WindowRule{ID: "a"}) },
		"Remove":  func(s *fakeStore) error { return Remove(s, "a") },
		"Reorder": func(s *fakeStore) error { return Reorder(s, []string{"a"}) },
	} {
		store := storeWith("a")
		store.writableEr = refusal
		if err := call(store); !errors.Is(err, refusal) {
			t.Errorf("%s: err = %v, want the read-only refusal", name, err)
		}
		if store.loads != 0 {
			t.Errorf("%s: loaded the fragment %d times, want 0", name, store.loads)
		}
		if store.wrote {
			t.Errorf("%s: wrote despite a read-only config", name)
		}
	}
}

func TestDMSOpaqueRuleIsPinnedLast(t *testing.T) {
	tests := []struct {
		name string
		run  func(*fakeStore) error
		have []string
		want []string
	}{
		{
			name: "Set keeps opaque last",
			run:  func(s *fakeStore) error { return Set(s, WindowRule{ID: "new"}) },
			have: []string{"a", OpaqueRuleID},
			want: []string{"a", "new", OpaqueRuleID},
		},
		{
			name: "Remove keeps opaque last",
			run:  func(s *fakeStore) error { return Remove(s, "b") },
			have: []string{"a", "b", OpaqueRuleID, "c"},
			want: []string{"a", "c", OpaqueRuleID},
		},
		{
			name: "Reorder with only user IDs",
			run:  func(s *fakeStore) error { return Reorder(s, []string{"b", "a"}) },
			have: []string{"a", OpaqueRuleID, "b"},
			want: []string{"b", "a", OpaqueRuleID},
		},
		{
			name: "Set replacing mid-list opaque moves it last",
			run:  func(s *fakeStore) error { return Set(s, WindowRule{ID: OpaqueRuleID}) },
			have: []string{"a", OpaqueRuleID, "b"},
			want: []string{"a", "b", OpaqueRuleID},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			store := storeWith(tt.have...)
			if err := tt.run(store); err != nil {
				t.Fatal(err)
			}
			assertIDs(t, store, tt.want...)
		})
	}
}
