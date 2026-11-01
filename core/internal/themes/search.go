package themes

import (
	"strings"

	"github.com/duxlabs-dev/dux-shell/core/internal/utils"
)

func FuzzySearch(query string, themes []Theme) []Theme {
	if query == "" {
		return themes
	}

	queryLower := strings.ToLower(query)
	return utils.Filter(themes, func(t Theme) bool {
		return fuzzyMatch(queryLower, strings.ToLower(t.Name)) ||
			fuzzyMatch(queryLower, strings.ToLower(t.Description)) ||
			fuzzyMatch(queryLower, strings.ToLower(t.Author))
	})
}

func fuzzyMatch(query, text string) bool {
	queryIdx := 0
	for _, char := range text {
		if queryIdx < len(query) && char == rune(query[queryIdx]) {
			queryIdx++
		}
	}
	return queryIdx == len(query)
}

func FindByIDOrName(idOrName string, themes []Theme) *Theme {
	if t, found := utils.Find(themes, func(t Theme) bool { return t.ID == idOrName }); found {
		return &t
	}
	if t, found := utils.Find(themes, func(t Theme) bool { return t.Name == idOrName }); found {
		return &t
	}
	return nil
}
