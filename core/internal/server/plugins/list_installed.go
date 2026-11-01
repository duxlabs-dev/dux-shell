package plugins

import (
	"fmt"

	"github.com/duxlabs-dev/dux-go/ipc"
	"github.com/duxlabs-dev/dux-shell/core/internal/plugins"
)

func HandleListInstalled(conn *ipc.ConnWriter, req ipc.Request) {
	manager, err := plugins.NewManager()
	if err != nil {
		conn.RespondError(req.ID, fmt.Sprintf("failed to create manager: %v", err))
		return
	}

	installedNames, err := manager.ListInstalled()
	if err != nil {
		conn.RespondError(req.ID, fmt.Sprintf("failed to list installed plugins: %v", err))
		return
	}

	registry, err := plugins.NewRegistry()
	if err != nil {
		conn.RespondError(req.ID, fmt.Sprintf("failed to create registry: %v", err))
		return
	}

	allPlugins, err := registry.List()
	if err != nil {
		conn.RespondError(req.ID, fmt.Sprintf("failed to list plugins: %v", err))
		return
	}

	pluginMap := make(map[string]plugins.Plugin)
	for _, p := range allPlugins {
		pluginMap[p.ID] = p
	}

	result := make([]PluginInfo, 0, len(installedNames))
	for _, id := range installedNames {
		if plugin, ok := pluginMap[id]; ok {
			info := pluginInfoFromPlugin(plugin)
			info.DiffURL = plugin.Repo
			hasUpdate, diffURL, err := manager.HasUpdates(id, plugin)
			if err != nil {
				info.UpdateError = err.Error()
				result = append(result, info)
				continue
			}
			info.HasUpdate = hasUpdate
			info.DiffURL = diffURL
			result = append(result, info)
		} else {
			result = append(result, PluginInfo{
				ID:   id,
				Name: id,
				Note: "not in registry",
			})
		}
	}

	SortPluginInfoByFirstParty(result)

	conn.Respond(req.ID, result)
}
