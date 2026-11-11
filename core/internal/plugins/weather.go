package plugins

import "path/filepath"

type WeatherProvider struct {
	Command string `json:"command"`
	Name    string `json:"name"`
	URL     string `json:"url"`
}

// WeatherProvider reads an installed plugin's weather block, with Command made absolute.
func (m *Manager) WeatherProvider(pluginID string) (WeatherProvider, bool) {
	path, err := m.findInstalledPath(pluginID)
	if err != nil || path == "" {
		return WeatherProvider{}, false
	}
	manifest := m.getPluginManifest(path)
	if manifest == nil || manifest.Weather == nil || manifest.Weather.Command == "" {
		return WeatherProvider{}, false
	}
	provider := *manifest.Weather
	provider.Command = filepath.Join(path, provider.Command)
	if provider.Name == "" {
		provider.Name = manifest.Name
	}
	return provider, true
}
