package themes

import (
	"fmt"

	"github.com/duxlabs-dev/dux-go/ipc"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/models"
	"github.com/duxlabs-dev/dux-shell/core/internal/themes"
)

func HandleInstall(conn *ipc.ConnWriter, req ipc.Request) {
	idOrName, ok := req.Get[string]("name")
	if !ok {
		conn.RespondError(req.ID, "missing or invalid 'name' parameter")
		return
	}

	registry, err := themes.NewRegistry()
	if err != nil {
		conn.RespondError(req.ID, fmt.Sprintf("failed to create registry: %v", err))
		return
	}

	themeList, err := registry.List()
	if err != nil {
		conn.RespondError(req.ID, fmt.Sprintf("failed to list themes: %v", err))
		return
	}

	theme := themes.FindByIDOrName(idOrName, themeList)
	if theme == nil {
		conn.RespondError(req.ID, fmt.Sprintf("theme not found: %s", idOrName))
		return
	}

	manager, err := themes.NewManager()
	if err != nil {
		conn.RespondError(req.ID, fmt.Sprintf("failed to create manager: %v", err))
		return
	}

	registryThemeDir := registry.GetThemeDir(theme.SourceDir)
	if err := manager.Install(*theme, registryThemeDir); err != nil {
		conn.RespondError(req.ID, fmt.Sprintf("failed to install theme: %v", err))
		return
	}

	conn.Respond(req.ID, models.SuccessResult{
		Success: true,
		Message: fmt.Sprintf("theme installed: %s", theme.Name),
	})
}
