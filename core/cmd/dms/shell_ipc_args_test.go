package main

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestFillOptionalIPCArgs(t *testing.T) {
	tests := []struct {
		name string
		args []string
		want []string
	}{
		{"increment without device", []string{"call", "brightness", "increment", "5"}, []string{"call", "brightness", "increment", "5", ""}},
		{"decrement without device", []string{"call", "brightness", "decrement", "5"}, []string{"call", "brightness", "decrement", "5", ""}},
		{"set without device", []string{"call", "brightness", "set", "100"}, []string{"call", "brightness", "set", "100", ""}},
		{"exponential without device", []string{"call", "brightness", "toggleExponential"}, []string{"call", "brightness", "toggleExponential", ""}},
		{"empty device stays", []string{"call", "brightness", "increment", "5", ""}, []string{"call", "brightness", "increment", "5", ""}},
		{"named device stays", []string{"call", "brightness", "set", "100", "backlight:a"}, []string{"call", "brightness", "set", "100", "backlight:a"}},
		{"missing step keeps the arity error", []string{"call", "brightness", "increment"}, []string{"call", "brightness", "increment"}},
		{"other brightness function", []string{"call", "brightness", "status"}, []string{"call", "brightness", "status"}},
		{"other target", []string{"call", "audio", "increment", "5"}, []string{"call", "audio", "increment", "5"}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.want, fillOptionalIPCArgs(tt.args))
		})
	}
}
