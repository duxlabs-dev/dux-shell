package plugins

import "path/filepath"

type LyricsProvider struct {
	Command  string `json:"command"`
	Name     string `json:"name"`
	URL      string `json:"url"`
	WordSync bool   `json:"wordSync"`
}

// LyricsProvider reads an installed plugin's lyrics block, with Command made absolute.
func (m *Manager) LyricsProvider(pluginID string) (LyricsProvider, bool) {
	path, err := m.findInstalledPath(pluginID)
	if err != nil || path == "" {
		return LyricsProvider{}, false
	}
	manifest := m.getPluginManifest(path)
	if manifest == nil || manifest.Lyrics == nil || manifest.Lyrics.Command == "" {
		return LyricsProvider{}, false
	}
	provider := *manifest.Lyrics
	provider.Command = filepath.Join(path, provider.Command)
	if provider.Name == "" {
		provider.Name = manifest.Name
	}
	return provider, true
}
