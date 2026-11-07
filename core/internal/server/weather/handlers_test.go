package weather

import (
	"testing"

	coreweather "github.com/duxlabs-dev/dux-go/weather"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestParseRequest(t *testing.T) {
	request, err := parseRequest(map[string]any{"latitude": 47.5, "longitude": 8.25})
	require.NoError(t, err)
	assert.Equal(t, coreweather.Request{Latitude: 47.5, Longitude: 8.25}, request)
}

func TestParseRequestMissingCoordinates(t *testing.T) {
	_, err := parseRequest(map[string]any{"latitude": 47.5})
	assert.Error(t, err)
	_, err = parseRequest(map[string]any{"longitude": 8.25})
	assert.Error(t, err)
}

func TestParseRequestProviders(t *testing.T) {
	request, err := parseRequest(map[string]any{
		"latitude": 1.0, "longitude": 2.0,
		"providers": []any{"metno", "plugin_example"},
	})
	require.NoError(t, err)
	assert.Equal(t, []coreweather.Provider{"metno", "plugin_example"}, request.Providers)

	request, err = parseRequest(map[string]any{"latitude": 1.0, "longitude": 2.0, "providers": []any{}})
	require.NoError(t, err)
	assert.Equal(t, []coreweather.Provider{coreweather.OpenMeteo}, request.Providers)
}

func TestParseRequestAirQuality(t *testing.T) {
	request, err := parseRequest(map[string]any{"latitude": 1.0, "longitude": 2.0, "air_quality": true})
	require.NoError(t, err)
	assert.True(t, request.AirQuality)

	request, err = parseRequest(map[string]any{"latitude": 1.0, "longitude": 2.0, "air_quality": false})
	require.NoError(t, err)
	assert.False(t, request.AirQuality)

	request, err = parseRequest(map[string]any{"latitude": 1.0, "longitude": 2.0})
	require.NoError(t, err)
	assert.False(t, request.AirQuality)

	// Like the other handlers' bool params, anything but a bool is off.
	request, err = parseRequest(map[string]any{"latitude": 1.0, "longitude": 2.0, "air_quality": "true"})
	require.NoError(t, err)
	assert.False(t, request.AirQuality)
}
