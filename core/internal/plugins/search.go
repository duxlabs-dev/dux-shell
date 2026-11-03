package plugins

import (
	"sort"
	"strings"

	"github.com/duxlabs-dev/dux-shell/core/internal/utils"
)

func FuzzySearch(query string, plugins []Plugin) []Plugin {
	if query == "" {
		return plugins
	}

	queryLower := strings.ToLower(query)
	return utils.Filter(plugins, func(p Plugin) bool {
		return fuzzyMatch(queryLower, strings.ToLower(p.Name)) ||
			fuzzyMatch(queryLower, strings.ToLower(p.Category)) ||
			fuzzyMatch(queryLower, strings.ToLower(p.Description)) ||
			fuzzyMatch(queryLower, strings.ToLower(p.Author))
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

func FilterByCategory(category string, plugins []Plugin) []Plugin {
	if category == "" {
		return plugins
	}
	categoryLower := strings.ToLower(category)
	return utils.Filter(plugins, func(p Plugin) bool {
		return strings.ToLower(p.Category) == categoryLower
	})
}

func FilterByCompositor(compositor string, plugins []Plugin) []Plugin {
	if compositor == "" {
		return plugins
	}
	compositorLower := strings.ToLower(compositor)
	return utils.Filter(plugins, func(p Plugin) bool {
		return utils.Any(p.Compositors, func(c string) bool {
			return strings.ToLower(c) == compositorLower
		})
	})
}

func FilterByCapability(capability string, plugins []Plugin) []Plugin {
	if capability == "" {
		return plugins
	}
	capabilityLower := strings.ToLower(capability)
	return utils.Filter(plugins, func(p Plugin) bool {
		return utils.Any(p.Capabilities, func(c string) bool {
			return strings.ToLower(c) == capabilityLower
		})
	})
}

func SortByFirstParty(plugins []Plugin) []Plugin {
	sort.SliceStable(plugins, func(i, j int) bool {
		if plugins[i].Featured != plugins[j].Featured {
			return plugins[i].Featured
		}
		isFirstPartyI := IsFirstPartyRepo(plugins[i].Repo)
		isFirstPartyJ := IsFirstPartyRepo(plugins[j].Repo)
		if isFirstPartyI != isFirstPartyJ {
			return isFirstPartyI
		}
		return false
	})
	return plugins
}

func FindByIDOrName(idOrName string, plugins []Plugin) *Plugin {
	if p, found := utils.Find(plugins, func(p Plugin) bool { return p.ID == idOrName }); found {
		return &p
	}
	if p, found := utils.Find(plugins, func(p Plugin) bool { return p.Name == idOrName }); found {
		return &p
	}
	return nil
}

func IsFirstPartyRepo(repo string) bool {
	return strings.HasPrefix(repo, "https://github.com/duxlabs-dev/") || strings.HasPrefix(repo, "https://github.com/AvengeMedia/")
}
