package wallpaper

import (
	"encoding/json"
	"os"
	"path/filepath"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/duxlabs-dev/dux-shell/core/internal/utils"
)

type persistentState struct {
	LastFires map[string]time.Time `json:"lastFires"`
}

func stateFilePath() string {
	return filepath.Join(utils.XDGCacheHome(), "dms", "wallpaper-schedule.json")
}

func loadLastFires() map[string]time.Time {
	data, err := os.ReadFile(stateFilePath())
	if err != nil {
		return map[string]time.Time{}
	}
	var state persistentState
	if err := json.Unmarshal(data, &state); err != nil || state.LastFires == nil {
		return map[string]time.Time{}
	}
	return state.LastFires
}

func saveLastFires(fires map[string]time.Time) {
	path := stateFilePath()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return
	}
	data, err := json.Marshal(persistentState{LastFires: fires})
	if err != nil {
		return
	}
	if err := os.WriteFile(path, data, 0o644); err != nil {
		log.Warnf("wallpaper: failed to persist schedule state: %v", err)
	}
}
