package niriconf

import (
	"os"
	"testing"
)

func historyContent(t *testing.T, s *Store, n int) string {
	t.Helper()
	got, err := s.versionContent("niri.kdl", n)
	if err != nil {
		t.Fatal(err)
	}
	return got
}

func TestApplyKeepsHandEditInHistory(t *testing.T) {
	// The rolled back file holds the last loaded version, not a hand edit.
	cases := map[string]struct {
		failed bool
		before string
	}{
		"hand edit":           {false, "hand\n"},
		"after a rolled back": {true, "broken\n"},
	}
	for name, c := range cases {
		t.Run(name, func(t *testing.T) {
			s := newStore(t)
			mustApply(t, s, "old\n")
			if c.failed {
				s.Events = &fakeEvents{t: t, path: s.path("niri.kdl"), failed: true}
				_, hash, _ := s.Read("niri.kdl")
				s.Apply("niri.kdl", "broken\n", hash)
				s.Events = nil
			} else if err := os.WriteFile(s.path("niri.kdl"), []byte("hand\n"), 0o644); err != nil {
				t.Fatal(err)
			}
			mustApply(t, s, "b\n")

			h, _ := s.History("niri.kdl")
			if got := historyContent(t, s, h[1].N); got != c.before {
				t.Fatalf("version before the apply %q, history %v", got, h)
			}
		})
	}
}

func TestHistoryKeepsLast(t *testing.T) {
	s := newStore(t)
	s.Keep = 3
	for _, c := range []string{"1\n", "2\n", "3\n", "4\n", "5\n"} {
		mustApply(t, s, c)
	}
	h, err := s.History("niri.kdl")
	if err != nil {
		t.Fatal(err)
	}
	if len(h) != 3 || h[0].N != 5 || h[1].N != 4 || h[2].N != 3 {
		t.Fatalf("history %v", h)
	}
}

func TestRestoreBringsBackOldContent(t *testing.T) {
	s := newStore(t)
	a := mustApply(t, s, "a\n")
	mustApply(t, s, "b\n")

	if _, _, err := s.Restore("niri.kdl", a.N); err != nil {
		t.Fatal(err)
	}
	if got := readFragment(t, s); got != "a\n" {
		t.Fatalf("file %q", got)
	}
	if h, _ := s.History("niri.kdl"); len(h) != 3 {
		t.Fatalf("history %v", h)
	}
}
