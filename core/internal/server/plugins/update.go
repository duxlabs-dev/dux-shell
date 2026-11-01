package plugins

import (
	"fmt"

	"github.com/duxlabs-dev/dux-go/ipc"
	"github.com/duxlabs-dev/dux-shell/core/internal/plugins"
)

func HandleUpdate(conn *ipc.ConnWriter, req ipc.Request) {
	name, ok := req.Get[string]("name")
	if !ok {
		conn.RespondError(req.ID, "missing or invalid 'name' parameter")
		return
	}

	manager, err := plugins.NewManager()
	if err != nil {
		conn.RespondError(req.ID, fmt.Sprintf("failed to create manager: %v", err))
		return
	}

	registry, err := plugins.NewRegistry()
	if err != nil {
		conn.RespondError(req.ID, fmt.Sprintf("failed to create registry: %v", err))
		return
	}

	pluginList, _ := registry.List()
	plugin := plugins.FindByIDOrName(name, pluginList)

	if plugin != nil {
		installed, err := manager.IsInstalled(*plugin)
		if err != nil {
			conn.RespondError(req.ID, fmt.Sprintf("failed to check if plugin is installed: %v", err))
			return
		}
		if !installed {
			conn.RespondError(req.ID, fmt.Sprintf("plugin not installed: %s", name))
			return
		}
		if err := manager.Update(*plugin); err != nil {
			conn.RespondError(req.ID, fmt.Sprintf("failed to update plugin: %v", err))
			return
		}
		conn.Respond(req.ID, SuccessResult{
			Success: true,
			Message: fmt.Sprintf("plugin updated: %s", plugin.Name),
		})
		return
	}

	// Not in registry - try to update from installed plugins directly
	if err := manager.UpdateByIDOrName(name); err != nil {
		conn.RespondError(req.ID, fmt.Sprintf("plugin not found: %s", name))
		return
	}

	conn.Respond(req.ID, SuccessResult{
		Success: true,
		Message: fmt.Sprintf("plugin updated: %s", name),
	})
}
