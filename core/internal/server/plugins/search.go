package plugins

import (
	"fmt"

	"github.com/duxlabs-dev/dux-go/ipc"
	"github.com/duxlabs-dev/dux-shell/core/internal/plugins"
)

func HandleSearch(conn *ipc.ConnWriter, req ipc.Request) {
	query, ok := req.Get[string]("query")
	if !ok {
		conn.RespondError(req.ID, "missing or invalid 'query' parameter")
		return
	}

	registry, err := plugins.NewRegistry()
	if err != nil {
		conn.RespondError(req.ID, fmt.Sprintf("failed to create registry: %v", err))
		return
	}

	pluginList, err := registry.List()
	if err != nil {
		conn.RespondError(req.ID, fmt.Sprintf("failed to list plugins: %v", err))
		return
	}

	searchResults := plugins.FuzzySearch(query, pluginList)

	if category := req.GetOr("category", ""); category != "" {
		searchResults = plugins.FilterByCategory(category, searchResults)
	}

	if compositor := req.GetOr("compositor", ""); compositor != "" {
		searchResults = plugins.FilterByCompositor(compositor, searchResults)
	}

	if capability := req.GetOr("capability", ""); capability != "" {
		searchResults = plugins.FilterByCapability(capability, searchResults)
	}

	searchResults = plugins.SortByFirstParty(searchResults)

	manager, err := plugins.NewManager()
	if err != nil {
		conn.RespondError(req.ID, fmt.Sprintf("failed to create manager: %v", err))
		return
	}

	result := make([]PluginInfo, len(searchResults))
	for i, p := range searchResults {
		installed, _ := manager.IsInstalled(p)
		info := pluginInfoFromPlugin(p)
		info.Installed = installed
		result[i] = info
	}

	conn.Respond(req.ID, result)
}
