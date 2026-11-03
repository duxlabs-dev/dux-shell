package themes

import (
	"fmt"
	"strings"

	"github.com/duxlabs-dev/dux-go/ipc"
	"github.com/duxlabs-dev/dux-shell/core/internal/themes"
)

func HandleList(conn *ipc.ConnWriter, req ipc.Request) {
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

	manager, err := themes.NewManager()
	if err != nil {
		conn.RespondError(req.ID, fmt.Sprintf("failed to create manager: %v", err))
		return
	}

	result := make([]ThemeInfo, len(themeList))
	for i, t := range themeList {
		installed, _ := manager.IsInstalled(t)
		info := ThemeInfo{
			ID:          t.ID,
			Name:        t.Name,
			Version:     t.Version,
			Author:      t.Author,
			Description: t.Description,
			PreviewPath: t.PreviewPath,
			SourceDir:   t.SourceDir,
			Installed:   installed,
			FirstParty:  isFirstParty(t.Author),
			WCAG:        t.WCAG,
		}
		addVariantsInfo(&info, t.Variants)
		result[i] = info
	}

	conn.Respond(req.ID, result)
}

func isFirstParty(author string) bool {
	return strings.EqualFold(author, "Dux Labs") || strings.EqualFold(author, "Avenge Media") || strings.EqualFold(author, "AvengeMedia")
}
