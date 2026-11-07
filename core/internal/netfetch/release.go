package netfetch

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"path"
	"strings"
	"time"
)

const (
	latestReleaseRedirectURL = "https://github.com/duxlabs-dev/dux-shell/releases/latest"
	latestReleaseAPIURL      = "https://api.github.com/repos/duxlabs-dev/dux-shell/releases/latest"
	releaseLookupTimeout     = 10 * time.Second
)

var ErrGitHubRateLimited = errors.New("github api rate limit exceeded (60 unauthenticated requests per hour per ip)")

func LatestReleaseTag(ctx context.Context) (string, error) {
	tag, redirectErr := latestTagFromRedirect(ctx, latestReleaseRedirectURL)
	if redirectErr == nil {
		return tag, nil
	}

	tag, apiErr := latestTagFromAPI(ctx, latestReleaseAPIURL)
	if apiErr == nil {
		return tag, nil
	}
	return "", fmt.Errorf("release redirect: %w; release api: %w", redirectErr, apiErr)
}

func latestTagFromRedirect(ctx context.Context, url string) (string, error) {
	opts := Options{
		Timeout: releaseLookupTimeout,
		CheckRedirect: func(*http.Request, []*http.Request) error {
			return http.ErrUseLastResponse
		},
	}
	req, err := opts.request(ctx, url)
	if err != nil {
		return "", err
	}
	req.Method = http.MethodHead

	resp, err := opts.client().Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode < 300 || resp.StatusCode >= 400 {
		return "", &StatusError{Code: resp.StatusCode}
	}

	location := resp.Header.Get("Location")
	tag := path.Base(location)
	if tag == "" || tag == "." || tag == "/" || !strings.Contains(location, "/releases/tag/") {
		return "", fmt.Errorf("unexpected release redirect: %q", location)
	}
	return tag, nil
}

func latestTagFromAPI(ctx context.Context, url string) (string, error) {
	body, err := Bytes(ctx, url, Options{Timeout: releaseLookupTimeout})
	var status *StatusError
	if errors.As(err, &status) && (status.Code == http.StatusForbidden || status.Code == http.StatusTooManyRequests) {
		return "", ErrGitHubRateLimited
	}
	if err != nil {
		return "", err
	}

	var release struct {
		TagName string `json:"tag_name"`
	}
	if err := json.Unmarshal(body, &release); err != nil {
		return "", fmt.Errorf("failed to parse latest release: %w", err)
	}
	if release.TagName == "" {
		return "", fmt.Errorf("latest release has no tag")
	}
	return release.TagName, nil
}
