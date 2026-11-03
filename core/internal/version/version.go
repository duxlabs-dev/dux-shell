package version

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/duxlabs-dev/dux-shell/core/internal/netfetch"
)

type VersionInfo struct {
	Current   string
	Latest    string
	IsGit     bool
	IsBranch  bool
	IsTag     bool
	HasUpdate bool
}

// VersionFetcher is an interface for fetching version information
type VersionFetcher interface {
	GetCurrentVersion(dmsPath string) (string, error)
	GetLatestVersion(dmsPath string) (string, error)
}

// DefaultVersionFetcher is the default implementation that uses git and the GitHub API
type DefaultVersionFetcher struct{}

func (d *DefaultVersionFetcher) GetCurrentVersion(dmsPath string) (string, error) {
	if _, err := os.Stat(filepath.Join(dmsPath, ".git")); err == nil {
		originalDir, err := os.Getwd()
		if err != nil {
			return "", err
		}
		defer func() {
			if err := os.Chdir(originalDir); err != nil {
				log.Warnf("failed to change back to original directory: %v", err)
			}
		}()

		if err := os.Chdir(dmsPath); err != nil {
			return "", fmt.Errorf("failed to change to DMS directory: %w", err)
		}

		tagCmd := exec.Command("git", "describe", "--exact-match", "--tags", "HEAD")
		if tagOutput, err := tagCmd.Output(); err == nil {
			return strings.TrimSpace(string(tagOutput)), nil
		}

		branchCmd := exec.Command("git", "rev-parse", "--abbrev-ref", "HEAD")
		if branchOutput, err := branchCmd.Output(); err == nil {
			branch := strings.TrimSpace(string(branchOutput))
			revCmd := exec.Command("git", "rev-parse", "--short", "HEAD")
			if revOutput, err := revCmd.Output(); err == nil {
				rev := strings.TrimSpace(string(revOutput))
				return fmt.Sprintf("%s@%s", branch, rev), nil
			}
			return branch, nil
		}
	}

	cmd := exec.Command("dms", "--version")
	if output, err := cmd.Output(); err == nil {
		return strings.TrimSpace(string(output)), nil
	}

	return "unknown", nil
}

func (d *DefaultVersionFetcher) GetLatestVersion(dmsPath string) (string, error) {
	if _, err := os.Stat(filepath.Join(dmsPath, ".git")); err == nil {
		originalDir, err := os.Getwd()
		if err != nil {
			return "", err
		}
		defer func() {
			if err := os.Chdir(originalDir); err != nil {
				log.Warnf("failed to change back to original directory: %v", err)
			}
		}()

		if err := os.Chdir(dmsPath); err != nil {
			return "", fmt.Errorf("failed to change to DMS directory: %w", err)
		}

		currentRefCmd := exec.Command("git", "symbolic-ref", "-q", "HEAD")
		currentRefOutput, _ := currentRefCmd.Output()
		onBranch := len(currentRefOutput) > 0

		if !onBranch {
			tagCmd := exec.Command("git", "describe", "--exact-match", "--tags", "HEAD")
			if _, err := tagCmd.Output(); err == nil {
				// Add timeout to git fetch to prevent hanging
				fetchCmd := exec.Command("timeout", "5s", "git", "fetch", "origin", "--tags", "--quiet")
				if err := fetchCmd.Run(); err != nil {
					log.Debugf("git fetch tags failed (continuing with local tags): %v", err)
				}

				latestTagCmd := exec.Command("git", "tag", "-l", "v*", "--sort=-version:refname")
				latestTagOutput, err := latestTagCmd.Output()
				if err != nil {
					return "", fmt.Errorf("failed to get latest tag: %w", err)
				}

				tags := strings.Split(strings.TrimSpace(string(latestTagOutput)), "\n")
				if len(tags) == 0 || tags[0] == "" {
					return "", fmt.Errorf("no version tags found")
				}
				return tags[0], nil
			}
		} else {
			branchCmd := exec.Command("git", "rev-parse", "--abbrev-ref", "HEAD")
			branchOutput, err := branchCmd.Output()
			if err != nil {
				return "", fmt.Errorf("failed to get current branch: %w", err)
			}
			currentBranch := strings.TrimSpace(string(branchOutput))

			// Add timeout to git fetch to prevent hanging
			fetchCmd := exec.Command("timeout", "5s", "git", "fetch", "origin", currentBranch, "--quiet")
			if err := fetchCmd.Run(); err != nil {
				log.Debugf("git fetch branch failed (continuing with local ref): %v", err)
			}

			remoteRevCmd := exec.Command("git", "rev-parse", "--short", fmt.Sprintf("origin/%s", currentBranch))
			remoteRevOutput, err := remoteRevCmd.Output()
			if err != nil {
				return "", fmt.Errorf("failed to get remote revision: %w", err)
			}
			remoteRev := strings.TrimSpace(string(remoteRevOutput))
			return fmt.Sprintf("%s@%s", currentBranch, remoteRev), nil
		}
	}

	return netfetch.LatestReleaseTag(context.Background())
}

// defaultFetcher is used by the public functions
var defaultFetcher VersionFetcher = &DefaultVersionFetcher{}

func GetCurrentDMSVersion() (string, error) {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("failed to get home directory: %w", err)
	}

	dmsPath := filepath.Join(homeDir, ".config", "quickshell", "dms")
	if _, err := os.Stat(dmsPath); os.IsNotExist(err) {
		return "", fmt.Errorf("DMS not installed")
	}

	return defaultFetcher.GetCurrentVersion(dmsPath)
}

func GetLatestDMSVersion() (string, error) {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("failed to get home directory: %w", err)
	}

	dmsPath := filepath.Join(homeDir, ".config", "quickshell", "dms")
	return defaultFetcher.GetLatestVersion(dmsPath)
}

func GetDMSVersionInfo() (*VersionInfo, error) {
	return GetDMSVersionInfoWithFetcher(defaultFetcher)
}

func GetDMSVersionInfoWithFetcher(fetcher VersionFetcher) (*VersionInfo, error) {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return nil, fmt.Errorf("failed to get home directory: %w", err)
	}

	dmsPath := filepath.Join(homeDir, ".config", "quickshell", "dms")
	if _, err := os.Stat(dmsPath); os.IsNotExist(err) {
		return nil, fmt.Errorf("DMS not installed")
	}

	current, err := fetcher.GetCurrentVersion(dmsPath)
	if err != nil {
		return nil, err
	}

	latest, err := fetcher.GetLatestVersion(dmsPath)
	if err != nil {
		return nil, fmt.Errorf("failed to get latest version: %w", err)
	}

	info := &VersionInfo{
		Current:  current,
		Latest:   latest,
		IsGit:    strings.Contains(current, "@"),
		IsBranch: strings.Contains(current, "@"),
		IsTag:    !strings.Contains(current, "@") && strings.HasPrefix(current, "v"),
	}

	if info.IsBranch {
		parts := strings.Split(current, "@")
		latestParts := strings.Split(latest, "@")
		if len(parts) == 2 && len(latestParts) == 2 {
			info.HasUpdate = parts[1] != latestParts[1]
		}
	} else if info.IsTag {
		info.HasUpdate = current != latest
	} else {
		info.HasUpdate = false
	}

	return info, nil
}

func CompareVersions(v1, v2 string) int {
	v1 = strings.TrimPrefix(v1, "v")
	v2 = strings.TrimPrefix(v2, "v")

	parts1 := strings.Split(v1, ".")
	parts2 := strings.Split(v2, ".")

	maxLen := max(len(parts2), len(parts1))

	for i := range maxLen {
		var p1, p2 int
		if i < len(parts1) {
			fmt.Sscanf(parts1[i], "%d", &p1) //nolint:errcheck
		}
		if i < len(parts2) {
			fmt.Sscanf(parts2[i], "%d", &p2) //nolint:errcheck
		}

		if p1 < p2 {
			return -1
		}
		if p1 > p2 {
			return 1
		}
	}

	return 0
}
