package themes

import (
	"fmt"

	"github.com/duxlabs-dev/dux-go/ipc"
	"github.com/duxlabs-dev/dux-shell/core/internal/themes"
)

func HandleSearch(conn *ipc.ConnWriter, req ipc.Request) {
	query, ok := req.Get[string]("query")
	if !ok {
		conn.RespondError(req.ID, "missing or invalid 'query' parameter")
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

	searchResults := themes.FuzzySearch(query, themeList)

	manager, err := themes.NewManager()
	if err != nil {
		conn.RespondError(req.ID, fmt.Sprintf("failed to create manager: %v", err))
		return
	}

	result := make([]ThemeInfo, len(searchResults))
	for i, t := range searchResults {
		installed, _ := manager.IsInstalled(t)
		result[i] = ThemeInfo{
			ID:          t.ID,
			Name:        t.Name,
			Version:     t.Version,
			Author:      t.Author,
			Description: t.Description,
			Installed:   installed,
			FirstParty:  isFirstParty(t.Author),
			WCAG:        t.WCAG,
		}
	}

	conn.Respond(req.ID, result)
}
