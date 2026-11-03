package plugins

type PluginInfo struct {
	ID           string   `json:"id"`
	Name         string   `json:"name"`
	Category     string   `json:"category,omitempty"`
	Author       string   `json:"author,omitempty"`
	Description  string   `json:"description,omitempty"`
	Repo         string   `json:"repo,omitempty"`
	Path         string   `json:"path,omitempty"`
	Screenshot   string   `json:"screenshot,omitempty"`
	Capabilities []string `json:"capabilities,omitempty"`
	Compositors  []string `json:"compositors,omitempty"`
	Dependencies []string `json:"dependencies,omitempty"`
	Installed    bool     `json:"installed,omitempty"`
	FirstParty   bool     `json:"firstParty,omitempty"`
	Featured     bool     `json:"featured,omitempty"`
	Note         string   `json:"note,omitempty"`
	HasUpdate    bool     `json:"hasUpdate,omitempty"`
	UpdateError  string   `json:"updateError,omitempty"`
	RequiresDMS  string   `json:"requires_dms,omitempty"`
	DiffURL      string   `json:"diffUrl,omitempty"`
	Upvotes      int      `json:"upvotes,omitempty"`
	Status       []string `json:"status,omitempty"`
	IssueURL     string   `json:"issueUrl,omitempty"`
	Similar      []string `json:"similar,omitempty"`
	Version      string   `json:"version,omitempty"`
	Icon         string   `json:"icon,omitempty"`
	Permissions  []string `json:"permissions,omitempty"`
	CreatedAt    string   `json:"created_at,omitempty"`
	UpdatedAt    string   `json:"updated_at,omitempty"`
}

type SuccessResult struct {
	Success bool   `json:"success"`
	Message string `json:"message"`
}
