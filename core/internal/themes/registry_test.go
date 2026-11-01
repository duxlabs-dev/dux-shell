package themes

import (
	"os"
	"testing"

	"github.com/duxlabs-dev/dux-shell/core/internal/clipolicy"
	"github.com/duxlabs-dev/dux-shell/core/internal/registries"
	"github.com/spf13/afero"
)

func TestLoadThemeWCAGInvalidJSON(t *testing.T) {
	fs := afero.NewMemMapFs()
	if err := afero.WriteFile(fs, "/themes/bad/wcag.json", []byte("{"), 0o644); err != nil {
		t.Fatal(err)
	}

	if wcag := loadThemeWCAG(fs, "/themes/bad"); wcag != nil {
		t.Fatalf("expected nil for invalid wcag.json, got %+v", wcag)
	}
}

type stubGitClient struct {
	cloneFunc func(path string, url string) error
}

func (s *stubGitClient) PlainClone(path string, url string) error {
	if s.cloneFunc != nil {
		return s.cloneFunc(path, url)
	}
	return nil
}
func (s *stubGitClient) Pull(path string) error                { return nil }
func (s *stubGitClient) OriginURL(path string) (string, error) { return "", os.ErrNotExist }

func writeTestTheme(t *testing.T, fs afero.Fs, registryDir, themeID, name string) {
	dir := registryDir + "/themes/" + themeID
	if err := fs.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	themeJSON := `{"id":"` + themeID + `","name":"` + name + `","version":"1.0","author":"a","description":"d"}`
	if err := afero.WriteFile(fs, dir+"/theme.json", []byte(themeJSON), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestUpdateMultiRegistry(t *testing.T) {
	fs := afero.NewMemMapFs()
	base := "/test-cache"
	r := &Registry{
		fs:       fs,
		cacheDir: base,
		registries: []registries.Source{
			{Name: "official", URL: "https://example.com/official.git"},
			{Name: "extra", URL: "https://example.com/extra.git"},
		},
		themes: []Theme{},
	}
	r.git = &stubGitClient{
		cloneFunc: func(path string, url string) error {
			switch path {
			case base + "/official":
				writeTestTheme(t, fs, path, "shared", "OfficialShared")
				writeTestTheme(t, fs, path, "one", "One")
			case base + "/extra":
				writeTestTheme(t, fs, path, "shared", "ExtraShared")
				writeTestTheme(t, fs, path, "two", "Two")
			}
			return nil
		},
	}

	if err := r.Update(); err != nil {
		t.Fatalf("Update: %v", err)
	}
	if len(r.themes) != 3 {
		t.Fatalf("expected 3 themes after dedupe, got %d", len(r.themes))
	}
	for _, theme := range r.themes {
		if theme.ID == "shared" && theme.Name != "OfficialShared" {
			t.Fatalf("first registry should win for duplicate ID, got %q", theme.Name)
		}
	}

	if dir := r.GetThemeDir("two"); dir != base+"/extra/themes/two" {
		t.Fatalf("expected theme dir under extra registry, got %q", dir)
	}
	if path := r.GetThemeSourcePath("one"); path != base+"/official/themes/one/theme.json" {
		t.Fatalf("expected theme source under official registry, got %q", path)
	}
}

func TestRegistriesDisabledByPolicy(t *testing.T) {
	t.Setenv("XDG_CONFIG_HOME", "/xdg")
	fs := afero.NewMemMapFs()
	if err := registries.Add(fs, "extra", "https://example.com/extra.git"); err != nil {
		t.Fatal(err)
	}
	if err := afero.WriteFile(fs, clipolicy.AdminPath, []byte(`{"disable_registries": true}`), 0o644); err != nil {
		t.Fatal(err)
	}

	r, err := NewRegistryWithFs(fs)
	if err != nil {
		t.Fatalf("NewRegistryWithFs: %v", err)
	}
	var cloned []string
	r.git = &stubGitClient{
		cloneFunc: func(path string, url string) error {
			cloned = append(cloned, url)
			return nil
		},
	}

	list, err := r.List()
	if err != nil {
		t.Fatalf("List: %v", err)
	}
	if len(list) != 0 {
		t.Fatalf("expected no themes, got %d", len(list))
	}
	if len(cloned) != 0 {
		t.Fatalf("expected no registry clone, got %v", cloned)
	}
}

func TestNewRegistryWithFsMalformedPolicy(t *testing.T) {
	fs := afero.NewMemMapFs()
	if err := afero.WriteFile(fs, clipolicy.AdminPath, []byte("{not json"), 0o644); err != nil {
		t.Fatal(err)
	}

	if _, err := NewRegistryWithFs(fs); err == nil {
		t.Fatal("expected an error for a malformed policy file")
	}
}
