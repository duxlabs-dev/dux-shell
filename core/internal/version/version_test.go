package version

import (
	"os"
	"path/filepath"
	"testing"

	mocks_version "github.com/duxlabs-dev/dux-shell/core/internal/mocks/version"
)

func TestCompareVersions(t *testing.T) {
	tests := []struct {
		v1       string
		v2       string
		expected int
	}{
		{"v0.1.0", "v0.1.0", 0},
		{"v0.1.0", "v0.1.1", -1},
		{"v0.1.1", "v0.1.0", 1},
		{"v0.1.10", "v0.1.2", 1},
		{"1.0.0", "v1.0.0", 0},
		{"", "", 0},
		{"v1.0", "v1", 0},
		{"v1.0.1", "v1.0", 1},
	}

	for _, tt := range tests {
		result := CompareVersions(tt.v1, tt.v2)
		if result != tt.expected {
			t.Errorf("CompareVersions(%q, %q) = %d; want %d", tt.v1, tt.v2, result, tt.expected)
		}
	}
}

func TestGetDMSVersionInfo_Structure(t *testing.T) {
	// Create a temp directory with a fake DMS installation
	tempDir := t.TempDir()
	dmsPath := filepath.Join(tempDir, ".config", "quickshell", "dms")
	os.MkdirAll(dmsPath, 0o755)

	// Create a .git directory to simulate git installation
	os.MkdirAll(filepath.Join(dmsPath, ".git"), 0o755)

	originalHome := os.Getenv("HOME")
	defer os.Setenv("HOME", originalHome)
	os.Setenv("HOME", tempDir)

	// Create mock fetcher
	mockFetcher := mocks_version.NewMockVersionFetcher(t)
	mockFetcher.EXPECT().GetCurrentVersion(dmsPath).Return("v0.1.0", nil)
	mockFetcher.EXPECT().GetLatestVersion(dmsPath).Return("v0.1.1", nil)

	info, err := GetDMSVersionInfoWithFetcher(mockFetcher)
	if err != nil {
		t.Fatalf("GetDMSVersionInfoWithFetcher() failed: %v", err)
	}

	if !info.HasUpdate {
		t.Error("HasUpdate should be true when current != latest")
	}

	if !info.IsTag {
		t.Error("IsTag should be true for v0.1.0")
	}
}

func TestGetDMSVersionInfo_BranchVersion(t *testing.T) {
	tempDir := t.TempDir()
	dmsPath := filepath.Join(tempDir, ".config", "quickshell", "dms")
	os.MkdirAll(dmsPath, 0o755)
	os.MkdirAll(filepath.Join(dmsPath, ".git"), 0o755)

	originalHome := os.Getenv("HOME")
	defer os.Setenv("HOME", originalHome)
	os.Setenv("HOME", tempDir)

	mockFetcher := mocks_version.NewMockVersionFetcher(t)
	mockFetcher.EXPECT().GetCurrentVersion(dmsPath).Return("master@abc1234", nil)
	mockFetcher.EXPECT().GetLatestVersion(dmsPath).Return("master@def5678", nil)

	info, err := GetDMSVersionInfoWithFetcher(mockFetcher)
	if err != nil {
		t.Fatalf("GetDMSVersionInfoWithFetcher() failed: %v", err)
	}

	if !info.IsBranch {
		t.Error("IsBranch should be true for branch@commit format")
	}

	if !info.IsGit {
		t.Error("IsGit should be true for branch@commit format")
	}

	if !info.HasUpdate {
		t.Error("HasUpdate should be true when commits differ")
	}
}

func TestGetDMSVersionInfo_NoUpdate(t *testing.T) {
	tempDir := t.TempDir()
	dmsPath := filepath.Join(tempDir, ".config", "quickshell", "dms")
	os.MkdirAll(dmsPath, 0o755)
	os.MkdirAll(filepath.Join(dmsPath, ".git"), 0o755)

	originalHome := os.Getenv("HOME")
	defer os.Setenv("HOME", originalHome)
	os.Setenv("HOME", tempDir)

	mockFetcher := mocks_version.NewMockVersionFetcher(t)
	mockFetcher.EXPECT().GetCurrentVersion(dmsPath).Return("v0.1.0", nil)
	mockFetcher.EXPECT().GetLatestVersion(dmsPath).Return("v0.1.0", nil)

	info, err := GetDMSVersionInfoWithFetcher(mockFetcher)
	if err != nil {
		t.Fatalf("GetDMSVersionInfoWithFetcher() failed: %v", err)
	}

	if info.HasUpdate {
		t.Error("HasUpdate should be false when current == latest")
	}
}

func TestGetCurrentDMSVersion_NotInstalled(t *testing.T) {
	originalHome := os.Getenv("HOME")
	defer os.Setenv("HOME", originalHome)

	tempDir := t.TempDir()
	os.Setenv("HOME", tempDir)

	_, err := GetCurrentDMSVersion()
	if err == nil {
		t.Error("Expected error when DMS not installed, got nil")
	}
}
