package brightness

import (
	"testing"
)

func TestDDCBackend_PercentConversions(t *testing.T) {
	tests := []struct {
		name      string
		max       int
		percent   int
		wantValue int
	}{
		{
			name:      "0% should map to minValue=1",
			max:       100,
			percent:   0,
			wantValue: 1,
		},
		{
			name:      "50% should be ~50",
			max:       100,
			percent:   50,
			wantValue: 50,
		},
		{
			name:      "100% should be max",
			max:       100,
			percent:   100,
			wantValue: 100,
		},
	}

	b := &DDCBackend{}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := b.percentToValue(tt.percent, tt.max, false)
			diff := got - tt.wantValue
			if diff < 0 {
				diff = -diff
			}
			if diff > 1 {
				t.Errorf("percentToValue() = %v, want %v (±1)", got, tt.wantValue)
			}
		})
	}
}

func TestDDCBackend_ValueToPercent(t *testing.T) {
	tests := []struct {
		name        string
		max         int
		value       int
		wantPercent int
		tolerance   int
	}{
		{
			name:        "min value should be 1%",
			max:         100,
			value:       1,
			wantPercent: 1,
			tolerance:   0,
		},
		{
			name:        "mid value should be ~50%",
			max:         100,
			value:       50,
			wantPercent: 50,
			tolerance:   2,
		},
		{
			name:        "max value should be 100%",
			max:         100,
			value:       100,
			wantPercent: 100,
			tolerance:   0,
		},
	}

	b := &DDCBackend{}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := b.valueToPercent(tt.value, tt.max, false)
			diff := got - tt.wantPercent
			if diff < 0 {
				diff = -diff
			}
			if diff > tt.tolerance {
				t.Errorf("valueToPercent() = %v, want %v (±%d)", got, tt.wantPercent, tt.tolerance)
			}
		})
	}
}
