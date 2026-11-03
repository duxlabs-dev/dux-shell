package plugins

import (
	"encoding/json"
	"net/http"
	"sync"
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

const feedbackMaxAge = 5 * time.Minute

var feedbackCache struct {
	sync.Mutex
	at   time.Time
	data map[string]Feedback
}

// FetchFeedback retrieves community upvotes, moderator status and directory metadata
// (version, icon, permissions, dates) from the directory API, reusing the last
// answer for feedbackMaxAge unless refresh is set.
// Best-effort: a failed fetch returns the last answer, or nil when there is none.
func FetchFeedback(refresh bool) map[string]Feedback {
	feedbackCache.Lock()
	defer feedbackCache.Unlock()
	if !refresh && feedbackCache.data != nil && time.Since(feedbackCache.at) < feedbackMaxAge {
		return feedbackCache.data
	}
	data := fetchFeedback()
	if data == nil {
		return feedbackCache.data
	}
	feedbackCache.at = time.Now()
	feedbackCache.data = data
	return data
}

func fetchFeedback() map[string]Feedback {
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
