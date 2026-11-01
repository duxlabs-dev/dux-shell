package niriconf

import (
	"errors"
	"os"
	"path/filepath"
	"sync"
	"testing"
)

func newStore(t *testing.T) *Store {
	t.Helper()
	return &Store{ConfigDir: setupValidate(t, `include "dms/niri.kdl"`+"\n", "")}
}

func mustApply(t *testing.T, s *Store, content string) Version {
	t.Helper()
	_, hash, err := s.Read("niri.kdl")
	if err != nil {
		t.Fatal(err)
	}
	v, err := s.Apply("niri.kdl", content, hash)
	if err != nil {
		t.Fatalf("apply %q: %v", content, err)
	}
	return v
}

func readFragment(t *testing.T, s *Store) string {
	t.Helper()
	got, err := os.ReadFile(filepath.Join(s.ConfigDir, "dms", "niri.kdl"))
	if err != nil {
		t.Fatal(err)
	}
	return string(got)
}

func TestApplyWritesAndRecordsHistory(t *testing.T) {
	s := newStore(t)
	mustApply(t, s, "a\n")
	mustApply(t, s, "b\n")

	if got := readFragment(t, s); got != "b\n" {
		t.Fatalf("file %q", got)
	}
	h, err := s.History("niri.kdl")
	if err != nil {
		t.Fatal(err)
	}
	if len(h) != 2 {
		t.Fatalf("history %v", h)
	}
	if got := historyContent(t, s, h[0].N); got != "b\n" {
		t.Fatalf("newest history %q", got)
	}
}

func TestApplyRefusesStaleBase(t *testing.T) {
	s := newStore(t)
	_, hash, err := s.Read("niri.kdl")
	if err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(s.ConfigDir, "dms", "niri.kdl")
	if err := os.WriteFile(path, []byte("outside\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	if _, err := s.Apply("niri.kdl", "mine\n", hash); !errors.Is(err, ErrChanged) {
		t.Fatalf("want ErrChanged, got %v", err)
	}
	if got := readFragment(t, s); got != "outside\n" {
		t.Fatalf("file %q", got)
	}
}

func TestApplyInvalidWritesNothing(t *testing.T) {
	cases := map[string]struct {
		content string
		setup   func(t *testing.T)
	}{
		"invalid":      {"BAD\n", func(t *testing.T) {}},
		"niri missing": {"ok\n", func(t *testing.T) { NiriBin = filepath.Join(t.TempDir(), "no-niri") }},
	}
	for name, c := range cases {
		t.Run(name, func(t *testing.T) {
			s := newStore(t)
			mustApply(t, s, "good\n")
			c.setup(t)
			_, hash, _ := s.Read("niri.kdl")

			_, err := s.Apply("niri.kdl", c.content, hash)
			var inv *InvalidError
			if err == nil || (name == "invalid") != errors.As(err, &inv) {
				t.Fatalf("got %v", err)
			}
			if got := readFragment(t, s); got != "good\n" {
				t.Fatalf("file %q", got)
			}
			if h, _ := s.History("niri.kdl"); len(h) != 1 {
				t.Fatalf("history %v", h)
			}
		})
	}
}

func TestApplyExtraFragment(t *testing.T) {
	cases := map[string]struct {
		extra      string
		reloadFail bool
		wantMain   string
		wantExtra  string
	}{
		"written":       {"custom\n", false, "new\n", "custom\n"},
		"invalid":       {"BAD\n", false, "old\n", "kept\n"},
		"reload failed": {"custom\n", true, "old\n", "kept\n"},
	}
	for name, c := range cases {
		t.Run(name, func(t *testing.T) {
			ev := &fakeEvents{failed: c.reloadFail}
			s := storeWithEvents(t, ev)
			if err := os.WriteFile(s.path("niri-custom.kdl"), []byte("kept\n"), 0o644); err != nil {
				t.Fatal(err)
			}
			_, hash, _ := s.Read("niri.kdl", "niri-custom.kdl")

			_, err := s.Apply("niri.kdl", "new\n", hash, Fragment{Name: "niri-custom.kdl", Content: c.extra})
			if (err == nil) != (c.wantMain == "new\n") {
				t.Fatalf("got %v", err)
			}
			if got := readFragment(t, s); got != c.wantMain {
				t.Fatalf("main %q", got)
			}
			if got, _, _ := s.Read("niri-custom.kdl"); got != c.wantExtra {
				t.Fatalf("extra %q", got)
			}
		})
	}
}

func TestApplyRefusesHandEditOfExtra(t *testing.T) {
	s := newStore(t)
	_, hash, _ := s.Read("niri.kdl", "niri-custom.kdl")
	if err := os.WriteFile(s.path("niri-custom.kdl"), []byte("by hand\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	_, err := s.Apply("niri.kdl", "new\n", hash, Fragment{Name: "niri-custom.kdl", Content: "page\n"})
	if !errors.Is(err, ErrChanged) {
		t.Fatalf("want ErrChanged, got %v", err)
	}
	if got, _, _ := s.Read("niri-custom.kdl"); got != "by hand\n" {
		t.Fatalf("extra %q", got)
	}
}

func TestApplyAddsIncludeOnlyWhenAccepted(t *testing.T) {
	s := newStore(t)
	configPath := filepath.Join(s.ConfigDir, "config.kdl")
	if err := os.WriteFile(configPath, []byte("layout {}\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	_, hash, _ := s.Read("niri.kdl")

	for _, c := range []struct{ content, base, want string }{
		{"BAD\n", hash, "layout {}\n"},
		{"new\n", "stale", "layout {}\n"},
		{"new\n", hash, "layout {}\n" + dmsInclude},
	} {
		s.Apply("niri.kdl", c.content, c.base)
		if got := readFile(t, configPath); got != c.want {
			t.Fatalf("%q on %q: config %q", c.content, c.base, got)
		}
	}
}

func TestBadNameRefused(t *testing.T) {
	s := newStore(t)
	for _, name := range []string{"../x.kdl", "x.txt", "X.kdl", "a/b.kdl"} {
		if _, _, err := s.Read(name); !errors.Is(err, ErrBadName) {
			t.Errorf("read %q: %v", name, err)
		}
		if _, err := s.Apply(name, "a\n", ""); !errors.Is(err, ErrBadName) {
			t.Errorf("apply %q: %v", name, err)
		}
		if _, err := s.History(name); !errors.Is(err, ErrBadName) {
			t.Errorf("history %q: %v", name, err)
		}
		if _, _, err := s.Restore(name, 1); !errors.Is(err, ErrBadName) {
			t.Errorf("restore %q: %v", name, err)
		}
	}
}

func TestConcurrentApplySerialised(t *testing.T) {
	s := newStore(t)
	_, hash, err := s.Read("niri.kdl")
	if err != nil {
		t.Fatal(err)
	}

	errs := make([]error, 10)
	var wg sync.WaitGroup
	for i := range errs {
		wg.Go(func() {
			_, errs[i] = s.Apply("niri.kdl", "a\n", hash)
		})
	}
	wg.Wait()

	ok := 0
	for _, err := range errs {
		switch {
		case err == nil:
			ok++
		case !errors.Is(err, ErrChanged):
			t.Fatalf("unexpected %v", err)
		}
	}
	if ok != 1 {
		t.Fatalf("%d applies succeeded", ok)
	}
}
