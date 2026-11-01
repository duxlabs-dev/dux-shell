package plugins

import (
	"fmt"

	"github.com/duxlabs-dev/dux-go/ipc"
	"github.com/duxlabs-dev/dux-shell/core/internal/plugins"
)

func HandleList(conn *ipc.ConnWriter, req ipc.Request) {
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

	manager, err := plugins.NewManager()
	if err != nil {
		conn.RespondError(req.ID, fmt.Sprintf("failed to create manager: %v", err))
		return
	}

	var feedback map[string]plugins.Feedback
	if len(pluginList) > 0 {
		feedback = plugins.FetchFeedback()
	}

	result := make([]PluginInfo, len(pluginList))
	for i, p := range pluginList {
		installed, _ := manager.IsInstalled(p)
		info := pluginInfoFromPlugin(p)
		info.Installed = installed
		applyFeedback(&info, feedback[p.ID])
		result[i] = info
	}

	conn.Respond(req.ID, result)
}
