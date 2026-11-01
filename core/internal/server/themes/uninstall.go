package themes

import (
	"fmt"

	"github.com/duxlabs-dev/dux-go/ipc"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/models"
	"github.com/duxlabs-dev/dux-shell/core/internal/themes"
)

func HandleUninstall(conn *ipc.ConnWriter, req ipc.Request) {
	idOrName, ok := req.Get[string]("name")
	if !ok {
		conn.RespondError(req.ID, "missing or invalid 'name' parameter")
		return
	}

	manager, err := themes.NewManager()
	if err != nil {
		conn.RespondError(req.ID, fmt.Sprintf("failed to create manager: %v", err))
		return
	}

	registry, err := themes.NewRegistry()
	if err != nil {
		conn.RespondError(req.ID, fmt.Sprintf("failed to create registry: %v", err))
		return
	}

	themeList, _ := registry.List()
	theme := themes.FindByIDOrName(idOrName, themeList)

	if theme != nil {
		installed, err := manager.IsInstalled(*theme)
		if err != nil {
			conn.RespondError(req.ID, fmt.Sprintf("failed to check if theme is installed: %v", err))
			return
		}
		if !installed {
			conn.RespondError(req.ID, fmt.Sprintf("theme not installed: %s", idOrName))
			return
		}
		if err := manager.Uninstall(*theme); err != nil {
			conn.RespondError(req.ID, fmt.Sprintf("failed to uninstall theme: %v", err))
			return
		}
		conn.Respond(req.ID, models.SuccessResult{
			Success: true,
			Message: fmt.Sprintf("theme uninstalled: %s", theme.Name),
		})
		return
	}

	if err := manager.UninstallByID(idOrName); err != nil {
		conn.RespondError(req.ID, fmt.Sprintf("theme not found: %s", idOrName))
		return
	}

	conn.Respond(req.ID, models.SuccessResult{
		Success: true,
		Message: fmt.Sprintf("theme uninstalled: %s", idOrName),
	})
}
