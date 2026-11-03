package wayland

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
)

type ipAPIResponse struct {
	Lat  float64 `json:"lat"`
	Lon  float64 `json:"lon"`
	City string  `json:"city"`
}

func FetchIPLocation() (*float64, *float64, error) {
	client := &http.Client{
		Timeout: 10 * time.Second,
	}

	resp, err := client.Get("http://ip-api.com/json/")
	if err != nil {
		return nil, nil, fmt.Errorf("failed to fetch IP location: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, nil, fmt.Errorf("ip-api.com returned status %d", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to read response: %w", err)
	}

	var data ipAPIResponse
	if err := json.Unmarshal(body, &data); err != nil {
		return nil, nil, fmt.Errorf("failed to parse response: %w", err)
	}

	if data.Lat == 0 && data.Lon == 0 {
		return nil, nil, fmt.Errorf("missing location data in response")
	}

	log.Infof("Fetched IP-based location: %s (%.4f, %.4f)", data.City, data.Lat, data.Lon)
	return &data.Lat, &data.Lon, nil
}
