package providers

import (
	"os"
	"path/filepath"
	"testing"
)

func TestNewJSONFileProvider(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.json")

	if err := os.WriteFile(testFile, []byte("{}"), 0o644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}

	tests := []struct {
		name        string
		filePath    string
		expectError bool
		wantName    string
	}{
		{
			name:        "valid file",
			filePath:    testFile,
			expectError: false,
			wantName:    "test",
		},
		{
			name:        "empty path",
			filePath:    "",
			expectError: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			p, err := NewJSONFileProvider(tt.filePath)

			if tt.expectError {
				if err == nil {
					t.Error("expected error, got nil")
				}
				return
			}

			if err != nil {
				t.Errorf("unexpected error: %v", err)
				return
			}

			if p.Name() != tt.wantName {
				t.Errorf("Name() = %q, want %q", p.Name(), tt.wantName)
			}
		})
	}
}

func TestJSONFileProviderGetCheatSheet(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "tmux.json")

	content := `{
  "title": "Tmux Binds",
  "provider": "tmux",
  "binds": {
    "Pane": [
      {
        "key": "Ctrl+Alt+J",
        "desc": "Resize split downward",
        "subcat": "Sizing"
      },
      {
        "key": "Ctrl+K",
        "desc": "Move Focus Up",
        "subcat": "Navigation"
      }
    ]
  }
}`

	if err := os.WriteFile(testFile, []byte(content), 0o644); err != nil {
		t.Fatalf("Failed to write test file: %v", err)
	}

	p, err := NewJSONFileProvider(testFile)
	if err != nil {
		t.Fatalf("NewJSONFileProvider failed: %v", err)
	}

	sheet, err := p.GetCheatSheet()
	if err != nil {
		t.Fatalf("GetCheatSheet failed: %v", err)
	}

	if sheet.Title != "Tmux Binds" {
		t.Errorf("Title = %q, want %q", sheet.Title, "Tmux Binds")
	}

	if sheet.Provider != "tmux" {
		t.Errorf("Provider = %q, want %q", sheet.Provider, "tmux")
	}

	paneBinds, ok := sheet.Binds["Pane"]
	if !ok {
		t.Fatal("expected Pane category")
	}

	if len(paneBinds) != 2 {
		t.Errorf("len(Pane binds) = %d, want 2", len(paneBinds))
	}

	if len(paneBinds) > 0 {
		bind := paneBinds[0]
		if bind.Key != "Ctrl+Alt+J" {
			t.Errorf("Pane[0].Key = %q, want %q", bind.Key, "Ctrl+Alt+J")
		}
		if bind.Description != "Resize split downward" {
			t.Errorf("Pane[0].Description = %q, want %q", bind.Description, "Resize split downward")
		}
		if bind.Subcategory != "Sizing" {
			t.Errorf("Pane[0].Subcategory = %q, want %q", bind.Subcategory, "Sizing")
		}
	}
}

func TestJSONFileProviderGetCheatSheetNoProvider(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "custom.json")

	content := `{
  "title": "Custom Binds",
  "binds": {}
}`

	if err := os.WriteFile(testFile, []byte(content), 0o644); err != nil {
		t.Fatalf("Failed to write test file: %v", err)
	}

	p, err := NewJSONFileProvider(testFile)
	if err != nil {
		t.Fatalf("NewJSONFileProvider failed: %v", err)
	}

	sheet, err := p.GetCheatSheet()
	if err != nil {
		t.Fatalf("GetCheatSheet failed: %v", err)
	}

	if sheet.Provider != "custom" {
		t.Errorf("Provider = %q, want %q (should default to filename)", sheet.Provider, "custom")
	}
}

func TestJSONFileProviderFlatArrayBackwardsCompat(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "legacy.json")

	content := `{
  "title": "Legacy Format",
  "provider": "legacy",
  "binds": [
    {
      "key": "Ctrl+S",
      "desc": "Save file",
      "cat": "File",
      "subcat": "Operations"
    },
    {
      "key": "Ctrl+O",
      "desc": "Open file",
      "cat": "File"
    },
    {
      "key": "Ctrl+Q",
      "desc": "Quit",
      "subcat": "Exit"
    }
  ]
}`

	if err := os.WriteFile(testFile, []byte(content), 0o644); err != nil {
		t.Fatalf("Failed to write test file: %v", err)
	}

	p, err := NewJSONFileProvider(testFile)
	if err != nil {
		t.Fatalf("NewJSONFileProvider failed: %v", err)
	}

	sheet, err := p.GetCheatSheet()
	if err != nil {
		t.Fatalf("GetCheatSheet failed: %v", err)
	}

	fileBinds, ok := sheet.Binds["File"]
	if !ok || len(fileBinds) != 2 {
		t.Errorf("expected 2 binds in File category, got %d", len(fileBinds))
	}

	otherBinds, ok := sheet.Binds["Other"]
	if !ok || len(otherBinds) != 1 {
		t.Errorf("expected 1 bind in Other category (no cat specified), got %d", len(otherBinds))
	}

	if len(fileBinds) > 0 {
		if fileBinds[0].Subcategory != "Operations" {
			t.Errorf("expected subcategory %q, got %q", "Operations", fileBinds[0].Subcategory)
		}
	}
}

func TestJSONFileProviderInvalidJSON(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "invalid.json")

	if err := os.WriteFile(testFile, []byte("not valid json"), 0o644); err != nil {
		t.Fatalf("Failed to write test file: %v", err)
	}

	p, err := NewJSONFileProvider(testFile)
	if err != nil {
		t.Fatalf("NewJSONFileProvider failed: %v", err)
	}

	_, err = p.GetCheatSheet()
	if err == nil {
		t.Error("expected error for invalid JSON, got nil")
	}
}
