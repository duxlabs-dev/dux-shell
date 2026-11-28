package config

import (
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	"github.com/duxlabs-dev/dux-shell/core/internal/utils"
)

type niriCapsCache struct {
	Key  string   `json:"key"`
	Caps []string `json:"caps"`
}

func niriCapsCachePath() string {
	return filepath.Join(utils.XDGCacheHome(), "dms", "niri-caps.json")
}

// The answer only changes with the niri binary or the probe list. Nix store files share one mtime, so the path is part of it.
func niriCapsCacheKey() string {
	exe := runningNiriExe()
	if exe == "" {
		return ""
	}
	target, err := os.Readlink(exe)
	if err != nil {
		return ""
	}
	info, err := os.Stat(exe)
	if err != nil {
		return ""
	}
	probes := sha256.Sum256([]byte(niriProbeConfig(niriFeatureProbes)))
	return fmt.Sprintf("%s:%d:%d:%x", target, info.Size(), info.ModTime().UnixNano(), probes[:8])
}

func readNiriCapsCache(key string) ([]string, bool) {
	if key == "" {
		return nil, false
	}
	data, err := os.ReadFile(niriCapsCachePath())
	if err != nil {
		return nil, false
	}
	var cache niriCapsCache
	if err := json.Unmarshal(data, &cache); err != nil || cache.Key != key {
		return nil, false
	}
	return cache.Caps, true
}

func writeNiriCapsCache(key string, caps []string) {
	if key == "" {
		return
	}
	data, err := json.Marshal(niriCapsCache{Key: key, Caps: caps})
	if err != nil {
		return
	}
	path := niriCapsCachePath()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return
	}
	tmp := fmt.Sprintf("%s.%d.tmp", path, os.Getpid())
	if err := os.WriteFile(tmp, data, 0o644); err != nil {
		return
	}
	if err := os.Rename(tmp, path); err != nil {
		os.Remove(tmp)
	}
}
