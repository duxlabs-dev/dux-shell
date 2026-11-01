package plugins

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/internal/site"
)

const feedbackURL = site.API + "/plugins"

type Feedback struct {
	Upvotes     int
	Status      []string
	IssueURL    string
	Similar     []string
	Version     string
	Icon        string
	Permissions []string
	CreatedAt   string
	UpdatedAt   string
}

// FetchFeedback retrieves community upvotes, moderator status and directory metadata
// (version, icon, permissions, dates) from the directory API.
// Best-effort: any failure returns a nil map.
func FetchFeedback() map[string]Feedback {
	client := &http.Client{Timeout: 5 * time.Second}

	resp, err := client.Get(feedbackURL)
	if err != nil {
		return nil
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil
	}

	var payload struct {
		Plugins []struct {
			ID       string   `json:"id"`
			Upvotes  int      `json:"upvotes"`
			Status   []string `json:"status"`
			IssueURL string   `json:"issueUrl"`
			Similar  []string `json:"similar"`

			Version     string   `json:"version"`
			Icon        string   `json:"icon"`
			Permissions []string `json:"permissions"`
			CreatedAt   string   `json:"created_at"`
			UpdatedAt   string   `json:"updated_at"`
		} `json:"plugins"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&payload); err != nil {
		return nil
	}

	feedback := make(map[string]Feedback, len(payload.Plugins))
	for _, p := range payload.Plugins {
		feedback[p.ID] = Feedback{
			Upvotes:     p.Upvotes,
			Status:      p.Status,
			IssueURL:    p.IssueURL,
			Similar:     p.Similar,
			Version:     p.Version,
			Icon:        p.Icon,
			Permissions: p.Permissions,
			CreatedAt:   p.CreatedAt,
			UpdatedAt:   p.UpdatedAt,
		}
	}
	return feedback
}
