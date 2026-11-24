package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestMergedSettingsAppliesConfigD(t *testing.T) {
	dir := t.TempDir()
	write := func(name, body string) {
		path := filepath.Join(dir, name)
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	write("settings.json", `{"screenshotCursor":false,"screenshotFormat":"png","screenshotQuality":80}`)
	write("config.d/10-a.json", `{"screenshotCursor":true,"screenshotFormat":"jpg"}`)
	write("config.d/20-b.json", `{"screenshotFormat":"ppm"}`)
	write("config.d/30-bad.json", `{`)
	write("config.d/.backup.json", `{"screenshotQuality":10}`)

	var got map[string]any
	if err := json.Unmarshal(mergedSettings(dir), &got); err != nil {
		t.Fatal(err)
	}
	want := map[string]any{"screenshotCursor": true, "screenshotFormat": "ppm", "screenshotQuality": float64(80)}
	for key, value := range want {
		if got[key] != value {
			t.Errorf("%s = %v, want %v", key, got[key], value)
		}
	}
}
