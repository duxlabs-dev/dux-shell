package wayland

import (
	"testing"
	"time"
)

func TestConfigValidate(t *testing.T) {
	tests := []struct {
		name    string
		config  Config
		wantErr bool
	}{
		{
			name:    "valid_default",
			config:  DefaultConfig(),
			wantErr: false,
		},
		{
			name: "invalid_low_temp_too_low",
			config: Config{
				LowTemp:  500,
				HighTemp: 6500,
				Gamma:    1.0,
				Contrast: 1.0,
			},
			wantErr: true,
		},
		{
			name: "invalid_high_temp_too_low",
			config: Config{
				LowTemp:  4000,
				HighTemp: 500,
				Gamma:    1.0,
				Contrast: 1.0,
			},
			wantErr: true,
		},
		{
			name: "valid_temps_equal",
			config: Config{
				LowTemp:  5000,
				HighTemp: 5000,
				Gamma:    1.0,
				Contrast: 1.0,
			},
			wantErr: false,
		},
		{
			name: "invalid_temps_reversed",
			config: Config{
				LowTemp:  6500,
				HighTemp: 4000,
				Gamma:    1.0,
				Contrast: 1.0,
			},
			wantErr: true,
		},
		{
			name: "invalid_gamma_zero",
			config: Config{
				LowTemp:  4000,
				HighTemp: 6500,
				Gamma:    0,
			},
			wantErr: true,
		},
		{
			name: "invalid_latitude_too_high",
			config: Config{
				LowTemp:   4000,
				HighTemp:  6500,
				Latitude:  new(100.0),
				Longitude: new(0.0),
				Gamma:     1.0,
				Contrast:  1.0,
			},
			wantErr: true,
		},
		{
			name: "invalid_longitude_too_high",
			config: Config{
				LowTemp:   4000,
				HighTemp:  6500,
				Latitude:  new(40.0),
				Longitude: new(200.0),
				Gamma:     1.0,
				Contrast:  1.0,
			},
			wantErr: true,
		},
		{
			name: "invalid_latitude_without_longitude",
			config: Config{
				LowTemp:  4000,
				HighTemp: 6500,
				Latitude: new(40.0),
				Gamma:    1.0,
				Contrast: 1.0,
			},
			wantErr: true,
		},
		{
			name: "invalid_sunrise_without_sunset",
			config: Config{
				LowTemp:       4000,
				HighTemp:      6500,
				ManualSunrise: new(time.Date(0, 1, 1, 6, 30, 0, 0, time.Local)),
				Gamma:         1.0,
				Contrast:      1.0,
			},
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := tt.config.Validate()
			if (err != nil) != tt.wantErr {
				t.Errorf("Validate() error = %v, wantErr %v", err, tt.wantErr)
			}
		})
	}
}

func TestStateChanged(t *testing.T) {
	baseState := &State{
		CurrentTemp:    5000,
		NextTransition: time.Now(),
		SunriseTime:    time.Now().Add(6 * time.Hour),
		SunsetTime:     time.Now().Add(18 * time.Hour),
		IsDay:          true,
		Config:         DefaultConfig(),
	}

	tests := []struct {
		name        string
		old         *State
		new         *State
		wantChanged bool
	}{
		{
			name:        "nil_old",
			old:         nil,
			new:         baseState,
			wantChanged: true,
		},
		{
			name:        "output list changed",
			old:         baseState,
			new:         func() *State { st := *baseState; st.Outputs = []string{"DP-1"}; return &st }(),
			wantChanged: true,
		},
		{
			name:        "same_state",
			old:         baseState,
			new:         baseState,
			wantChanged: false,
		},
		{
			name: "temp_changed",
			old:  baseState,
			new: &State{
				CurrentTemp:    6000,
				NextTransition: baseState.NextTransition,
				SunriseTime:    baseState.SunriseTime,
				SunsetTime:     baseState.SunsetTime,
				IsDay:          baseState.IsDay,
				Config:         baseState.Config,
			},
			wantChanged: true,
		},
		{
			name: "is_day_changed",
			old:  baseState,
			new: &State{
				CurrentTemp:    baseState.CurrentTemp,
				NextTransition: baseState.NextTransition,
				SunriseTime:    baseState.SunriseTime,
				SunsetTime:     baseState.SunsetTime,
				IsDay:          false,
				Config:         baseState.Config,
			},
			wantChanged: true,
		},
		{
			name: "enabled_changed",
			old:  baseState,
			new: &State{
				CurrentTemp:    baseState.CurrentTemp,
				NextTransition: baseState.NextTransition,
				SunriseTime:    baseState.SunriseTime,
				SunsetTime:     baseState.SunsetTime,
				IsDay:          baseState.IsDay,
				Config: Config{
					LowTemp:  4000,
					HighTemp: 6500,
					Gamma:    1.0,
					Contrast: 1.0,
					Enabled:  true,
				},
			},
			wantChanged: true,
		},
		{
			// Applying or removing a profile changes nothing else, so the push
			// that carries it to the settings page must not be suppressed.
			name: "profile_applied",
			old:  baseState,
			new: &State{
				CurrentTemp:    baseState.CurrentTemp,
				NextTransition: baseState.NextTransition,
				SunriseTime:    baseState.SunriseTime,
				SunsetTime:     baseState.SunsetTime,
				IsDay:          baseState.IsDay,
				Config:         baseState.Config,
				ICCProfiles: map[string]*ICCStatus{
					"DP-1": {Path: "/tmp/dp1.icc", Active: true},
				},
			},
			wantChanged: true,
		},
		{
			name: "profile_description_changed",
			old: &State{
				Config:      baseState.Config,
				ICCProfiles: map[string]*ICCStatus{"DP-1": {Path: "/tmp/dp1.icc", Description: "Old"}},
			},
			new: &State{
				Config:      baseState.Config,
				ICCProfiles: map[string]*ICCStatus{"DP-1": {Path: "/tmp/dp1.icc", Description: "New"}},
			},
			wantChanged: true,
		},
		{
			name: "output_temp_changed",
			old:  baseState,
			new: &State{
				CurrentTemp:    baseState.CurrentTemp,
				NextTransition: baseState.NextTransition,
				SunriseTime:    baseState.SunriseTime,
				SunsetTime:     baseState.SunsetTime,
				IsDay:          baseState.IsDay,
				Config:         baseState.Config,
				OutputTemps:    map[string]int{"DP-1": 7000},
			},
			wantChanged: true,
		},
		{
			name: "same_icc_state",
			old: &State{
				Config:      baseState.Config,
				ICCProfiles: map[string]*ICCStatus{"DP-1": {Path: "/tmp/dp1.icc", Active: true}},
				OutputTemps: map[string]int{"DP-1": 7000},
			},
			new: &State{
				Config:      baseState.Config,
				ICCProfiles: map[string]*ICCStatus{"DP-1": {Path: "/tmp/dp1.icc", Active: true}},
				OutputTemps: map[string]int{"DP-1": 7000},
			},
			wantChanged: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			changed := stateChanged(tt.old, tt.new)
			if changed != tt.wantChanged {
				t.Errorf("stateChanged() = %v, want %v", changed, tt.wantChanged)
			}
		})
	}
}
