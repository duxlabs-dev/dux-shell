package wayland

import (
	"testing"
	"time"
)

func TestCalculateSunTimes(t *testing.T) {
	tests := []struct {
		name      string
		lat       float64
		lon       float64
		date      time.Time
		checkFunc func(*testing.T, SunTimes)
	}{
		{
			name: "london_winter",
			lat:  51.5074,
			lon:  -0.1278,
			date: time.Date(2024, 12, 21, 12, 0, 0, 0, time.UTC),
			checkFunc: func(t *testing.T, times SunTimes) {
				if times.Sunrise.Hour() < 7 || times.Sunrise.Hour() > 9 {
					t.Errorf("unexpected sunrise hour: %d", times.Sunrise.Hour())
				}
				if times.Sunset.Hour() < 15 || times.Sunset.Hour() > 17 {
					t.Errorf("unexpected sunset hour: %d", times.Sunset.Hour())
				}
			},
		},
		{
			name: "equator_equinox",
			lat:  0.0,
			lon:  0.0,
			date: time.Date(2024, 3, 20, 12, 0, 0, 0, time.UTC),
			checkFunc: func(t *testing.T, times SunTimes) {
				if times.Sunrise.Hour() < 5 || times.Sunrise.Hour() > 7 {
					t.Errorf("unexpected sunrise hour: %d", times.Sunrise.Hour())
				}
				if times.Sunset.Hour() < 17 || times.Sunset.Hour() > 19 {
					t.Errorf("unexpected sunset hour: %d", times.Sunset.Hour())
				}
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			times := CalculateSunTimes(tt.lat, tt.lon, tt.date)
			tt.checkFunc(t, times)
		})
	}
}
