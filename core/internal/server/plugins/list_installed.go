package plugins

import (
	"fmt"
	"sync"

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

	checks := checkUpdates(manager, installedNames, pluginMap)

	result := make([]PluginInfo, 0, len(installedNames))
	for i, id := range installedNames {
		if plugin, ok := pluginMap[id]; ok {
			info := pluginInfoFromPlugin(plugin)
			info.DiffURL = plugin.Repo
			check := checks[i]
			if check.err != nil {
				info.UpdateError = check.err.Error()
				result = append(result, info)
				continue
			}
			info.HasUpdate = check.hasUpdate
			info.DiffURL = check.diffURL
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

type updateCheck struct {
	hasUpdate bool
	diffURL   string
	err       error
}

const updateCheckWorkers = 8

// Each check is a remote ls-remote, so they run concurrently; the lockfile is
// created up front so the workers only read it.
func checkUpdates(manager *plugins.Manager, ids []string, known map[string]plugins.Plugin) []updateCheck {
	_ = manager.EnsureLockfile()
	checks := make([]updateCheck, len(ids))
	sem := make(chan struct{}, updateCheckWorkers)
	var wg sync.WaitGroup
	for i, id := range ids {
		plugin, ok := known[id]
		if !ok {
			continue
		}
		wg.Add(1)
		go func() {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			hasUpdate, diffURL, err := manager.HasUpdates(id, plugin)
			checks[i] = updateCheck{hasUpdate: hasUpdate, diffURL: diffURL, err: err}
		}()
	}
	wg.Wait()
	return checks
}
