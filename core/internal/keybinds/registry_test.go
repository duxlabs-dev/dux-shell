package keybinds

import (
	"testing"
)

type mockProvider struct {
	name string
	err  error
}

func (m *mockProvider) Name() string {
	return m.name
}

func (m *mockProvider) ModKey() ModKey {
	return DefaultModKey()
}

func (m *mockProvider) GetCheatSheet() (*CheatSheet, error) {
	if m.err != nil {
		return nil, m.err
	}
	return &CheatSheet{
		Title:    "Test",
		Provider: m.name,
		Binds:    make(map[string][]Keybind),
	}, nil
}

func TestRegisterProvider(t *testing.T) {
	tests := []struct {
		name        string
		provider    Provider
		expectError bool
		errorMsg    string
	}{
		{
			name:        "valid provider",
			provider:    &mockProvider{name: "test"},
			expectError: false,
		},
		{
			name:        "nil provider",
			provider:    nil,
			expectError: true,
			errorMsg:    "cannot register nil provider",
		},
		{
			name:        "empty name",
			provider:    &mockProvider{name: ""},
			expectError: true,
			errorMsg:    "provider name cannot be empty",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			r := NewRegistry()
			err := r.Register(tt.provider)

			if tt.expectError {
				if err == nil {
					t.Error("expected error, got nil")
				}
				return
			}

			if err != nil {
				t.Errorf("unexpected error: %v", err)
			}
		})
	}
}

func TestRegisterDuplicate(t *testing.T) {
	r := NewRegistry()
	p := &mockProvider{name: "test"}

	if err := r.Register(p); err != nil {
		t.Fatalf("first registration failed: %v", err)
	}

	err := r.Register(p)
	if err == nil {
		t.Error("expected error when registering duplicate, got nil")
	}
}

func TestGetProvider(t *testing.T) {
	r := NewRegistry()
	p := &mockProvider{name: "test"}

	if err := r.Register(p); err != nil {
		t.Fatalf("registration failed: %v", err)
	}

	retrieved, err := r.Get("test")
	if err != nil {
		t.Fatalf("Get failed: %v", err)
	}

	if retrieved.Name() != "test" {
		t.Errorf("Got provider name %q, want %q", retrieved.Name(), "test")
	}
}

func TestGetNonexistent(t *testing.T) {
	r := NewRegistry()

	_, err := r.Get("nonexistent")
	if err == nil {
		t.Error("expected error for nonexistent provider, got nil")
	}
}
