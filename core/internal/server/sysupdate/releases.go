package sysupdate

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/duxlabs-dev/dux-shell/core/internal/netfetch"
	"github.com/duxlabs-dev/dux-shell/core/internal/site"
	"github.com/duxlabs-dev/dux-shell/core/internal/utils"
)

const (
	releasesURL      = site.API + "/dms/releases"
	releasesTimeout  = 10 * time.Second
	releasesMinAge   = time.Hour
	releasesMaxBytes = 1 << 20
)

var releasesFetch = func(ctx context.Context, etag string) (netfetch.Conditional, error) {
	return netfetch.BytesConditional(ctx, releasesURL, etag, netfetch.Options{Timeout: releasesTimeout, MaxBytes: releasesMaxBytes})
}

func cacheDir() string {
	return filepath.Join(utils.XDGCacheHome(), "dms")
}

func releasesCachePath() string {
	return filepath.Join(cacheDir(), "releases.json")
}

// The feed never lives in Manager memory; every reader goes through the cache file.
func LoadReleases() (ReleasesFeed, bool) {
	data, err := os.ReadFile(releasesCachePath())
	if err != nil {
		return ReleasesFeed{}, false
	}
	var feed ReleasesFeed
	if err := json.Unmarshal(data, &feed); err != nil {
		return ReleasesFeed{}, false
	}
	if feed.Releases == nil {
		feed.Releases = []Release{}
	}
	return feed, true
}

func saveReleases(feed ReleasesFeed) error {
	data, err := json.Marshal(feed)
	if err != nil {
		return err
	}
	return writeFileAtomic(releasesCachePath(), data)
}

func writeFileAtomic(path string, data []byte) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, data, 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

// Serialized so overlapping requests don't fetch twice.
func (m *Manager) refreshReleases(ctx context.Context, force bool) (ReleasesFeed, error) {
	m.releasesMu.Lock()
	defer m.releasesMu.Unlock()
	cached, ok := LoadReleases()
	if ok && !force && time.Since(time.Unix(cached.FetchedAt, 0)) < releasesMinAge {
		return cached, nil
	}

	res, err := releasesFetch(ctx, cached.ETag)
	if err != nil {
		if ok {
			return cached, err
		}
		return ReleasesFeed{Releases: []Release{}}, err
	}

	now := time.Now().Unix()
	feed := cached
	if !res.NotModified {
		feed = ReleasesFeed{}
		if err := json.Unmarshal(res.Body, &feed); err != nil {
			if ok {
				return cached, err
			}
			return ReleasesFeed{Releases: []Release{}}, err
		}
		if feed.Releases == nil {
			feed.Releases = []Release{}
		}
	}
	feed.FetchedAt = now
	feed.ETag = res.ETag
	if err := saveReleases(feed); err != nil {
		log.Warnf("[sysupdate] save releases cache: %v", err)
	}
	m.applyReleases(feed)
	return feed, nil
}

func (m *Manager) applyReleases(feed ReleasesFeed) {
	m.mu.Lock()
	m.state.Shell.CommitsBehind = commitsBehind(m.state.Shell, feed.Master)
	m.mu.Unlock()
	m.markDirty()
}

// Packages ride along so a restart doesn't show an empty list until the next daily check.
type persistedState struct {
	LastCheckUnix   int64     `json:"lastCheckUnix"`
	LastSuccessUnix int64     `json:"lastSuccessUnix"`
	Packages        []Package `json:"packages,omitempty"`
	// Survives shell restarts, not the reboot itself.
	RebootBootID   string   `json:"rebootBootId,omitempty"`
	RebootPackages []string `json:"rebootPackages,omitempty"`
}

func statePath() string {
	return filepath.Join(cacheDir(), "sysupdate.json")
}

func loadPersisted() persistedState {
	var s persistedState
	data, err := os.ReadFile(statePath())
	if err != nil {
		return s
	}
	if err := json.Unmarshal(data, &s); err != nil {
		return persistedState{}
	}
	return s
}

func savePersisted(s persistedState) {
	data, err := json.Marshal(s)
	if err != nil {
		return
	}
	if err := writeFileAtomic(statePath(), data); err != nil {
		log.Debugf("[sysupdate] persist state: %v", err)
	}
}
