package keybinds

import (
	"os"
	"path/filepath"
	"testing"
)

func TestDefaultDiscoveryConfig(t *testing.T) {
	oldConfigHome := os.Getenv("XDG_CONFIG_HOME")
	oldConfigDirs := os.Getenv("XDG_CONFIG_DIRS")
	defer func() {
		os.Setenv("XDG_CONFIG_HOME", oldConfigHome)
		os.Setenv("XDG_CONFIG_DIRS", oldConfigDirs)
	}()

	tests := []struct {
		name           string
		configHome     string
		configDirs     string
		expectedCount  int
		checkFirstPath bool
		firstPath      string
	}{
		{
			name:           "with XDG_CONFIG_HOME set",
			configHome:     "/custom/config",
			configDirs:     "",
			expectedCount:  1,
			checkFirstPath: true,
			firstPath:      "/custom/config/dms/cheatsheets",
		},
		{
			name:          "with XDG_CONFIG_DIRS set",
			configHome:    "/home/user/.config",
			configDirs:    "/etc/xdg:/opt/config",
			expectedCount: 3,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			os.Setenv("XDG_CONFIG_HOME", tt.configHome)
			os.Setenv("XDG_CONFIG_DIRS", tt.configDirs)

			config := DefaultDiscoveryConfig()

			if config == nil {
				t.Fatal("DefaultDiscoveryConfig returned nil")
			}

			if len(config.SearchPaths) != tt.expectedCount {
				t.Errorf("SearchPaths count = %d, want %d", len(config.SearchPaths), tt.expectedCount)
			}

			if tt.checkFirstPath && len(config.SearchPaths) > 0 {
				if tt.firstPath != "" && config.SearchPaths[0] != tt.firstPath {
					t.Errorf("SearchPaths[0] = %q, want %q", config.SearchPaths[0], tt.firstPath)
				}
			}
		})
	}
}

func TestFindJSONFiles(t *testing.T) {
	tmpDir := t.TempDir()

	file1 := filepath.Join(tmpDir, "tmux.json")
	file2 := filepath.Join(tmpDir, "vim.json")
	txtFile := filepath.Join(tmpDir, "readme.txt")
	subdir := filepath.Join(tmpDir, "subdir")

	if err := os.WriteFile(file1, []byte("{}"), 0o644); err != nil {
		t.Fatalf("Failed to create file1: %v", err)
	}
	if err := os.WriteFile(file2, []byte("{}"), 0o644); err != nil {
		t.Fatalf("Failed to create file2: %v", err)
	}
	if err := os.WriteFile(txtFile, []byte("text"), 0o644); err != nil {
		t.Fatalf("Failed to create txt file: %v", err)
	}
	if err := os.MkdirAll(subdir, 0o755); err != nil {
		t.Fatalf("Failed to create subdir: %v", err)
	}

	config := &DiscoveryConfig{
		SearchPaths: []string{tmpDir},
	}

	files, err := config.FindJSONFiles()
	if err != nil {
		t.Fatalf("FindJSONFiles failed: %v", err)
	}

	if len(files) != 2 {
		t.Errorf("expected 2 JSON files, got %d", len(files))
	}

	found := make(map[string]bool)
	for _, f := range files {
		found[filepath.Base(f)] = true
	}

	if !found["tmux.json"] {
		t.Error("tmux.json not found")
	}
	if !found["vim.json"] {
		t.Error("vim.json not found")
	}
	if found["readme.txt"] {
		t.Error("readme.txt should not be included")
	}
}

func TestFindJSONFilesNonexistentPath(t *testing.T) {
	config := &DiscoveryConfig{
		SearchPaths: []string{"/nonexistent/path"},
	}

	files, err := config.FindJSONFiles()
	if err != nil {
		t.Fatalf("FindJSONFiles failed: %v", err)
	}

	if len(files) != 0 {
		t.Errorf("expected 0 files for nonexistent path, got %d", len(files))
	}
}

func TestAutoDiscoverProviders(t *testing.T) {
	tmpDir := t.TempDir()

	jsonContent := `{
  "title": "Test App",
  "provider": "testapp",
  "binds": {}
}`

	file := filepath.Join(tmpDir, "testapp.json")
	if err := os.WriteFile(file, []byte(jsonContent), 0o644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}

	config := &DiscoveryConfig{
		SearchPaths: []string{tmpDir},
	}

	registry := NewRegistry()

	factoryCalled := false
	SetJSONProviderFactory(func(filePath string) (Provider, error) {
		factoryCalled = true
		return &mockProvider{name: "testapp"}, nil
	})

	err := AutoDiscoverProviders(registry, config)
	if err != nil {
		t.Fatalf("AutoDiscoverProviders failed: %v", err)
	}

	if !factoryCalled {
		t.Error("factory was not called")
	}

	provider, err := registry.Get("testapp")
	if err != nil {
		t.Fatalf("provider not registered: %v", err)
	}

	if provider.Name() != "testapp" {
		t.Errorf("provider name = %q, want %q", provider.Name(), "testapp")
	}
}

func TestAutoDiscoverProvidersNoFactory(t *testing.T) {
	tmpDir := t.TempDir()

	file := filepath.Join(tmpDir, "test.json")
	if err := os.WriteFile(file, []byte("{}"), 0o644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}

	config := &DiscoveryConfig{
		SearchPaths: []string{tmpDir},
	}

	registry := NewRegistry()

	SetJSONProviderFactory(nil)

	err := AutoDiscoverProviders(registry, config)
	if err != nil {
		t.Fatalf("AutoDiscoverProviders should not fail without factory: %v", err)
	}

	providers := registry.List()
	if len(providers) != 0 {
		t.Errorf("expected 0 providers without factory, got %d", len(providers))
	}
}
