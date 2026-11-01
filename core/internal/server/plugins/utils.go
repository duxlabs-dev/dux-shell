package plugins

import (
	"net/url"
	"sort"
	"strings"

	coreplugins "github.com/duxlabs-dev/dux-shell/core/internal/plugins"
)

func pluginInfoFromPlugin(plugin coreplugins.Plugin) PluginInfo {
	return PluginInfo{
		ID:           plugin.ID,
		Name:         plugin.Name,
		Category:     plugin.Category,
		Author:       plugin.Author,
		Description:  plugin.Description,
		Repo:         plugin.Repo,
		Path:         plugin.Path,
		Screenshot:   normalizeScreenshotURL(plugin.Screenshot),
		Capabilities: plugin.Capabilities,
		Compositors:  plugin.Compositors,
		Dependencies: plugin.Dependencies,
		FirstParty:   coreplugins.IsFirstPartyRepo(plugin.Repo),
		Featured:     plugin.Featured,
		RequiresDMS:  plugin.RequiresDMS,
	}
}

func applyFeedback(info *PluginInfo, fb coreplugins.Feedback) {
	info.Upvotes = fb.Upvotes
	info.Status = fb.Status
	info.IssueURL = fb.IssueURL
	info.Similar = fb.Similar
	info.Version = fb.Version
	info.Icon = fb.Icon
	info.Permissions = fb.Permissions
	info.CreatedAt = fb.CreatedAt
	info.UpdatedAt = fb.UpdatedAt
}

func normalizeScreenshotURL(raw string) string {
	screenshotURL := strings.TrimSpace(raw)
	if screenshotURL == "" {
		return ""
	}

	parsed, err := url.Parse(screenshotURL)
	if err != nil {
		return screenshotURL
	}

	host := strings.ToLower(parsed.Host)
	if host != "github.com" && host != "www.github.com" {
		return screenshotURL
	}

	parts := strings.Split(strings.Trim(parsed.EscapedPath(), "/"), "/")
	if len(parts) < 5 || (parts[2] != "blob" && parts[2] != "raw") {
		return screenshotURL
	}

	rawParts := append([]string{parts[0], parts[1], parts[3]}, parts[4:]...)
	return "https://raw.githubusercontent.com/" + strings.Join(rawParts, "/")
}

func SortPluginInfoByFirstParty(pluginInfos []PluginInfo) {
	sort.SliceStable(pluginInfos, func(i, j int) bool {
		isFirstPartyI := coreplugins.IsFirstPartyRepo(pluginInfos[i].Repo)
		isFirstPartyJ := coreplugins.IsFirstPartyRepo(pluginInfos[j].Repo)
		if isFirstPartyI != isFirstPartyJ {
			return isFirstPartyI
		}
		return false
	})
}
