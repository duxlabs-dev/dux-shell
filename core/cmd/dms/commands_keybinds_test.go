package main

import (
	"errors"
	"fmt"
	"testing"

	"github.com/duxlabs-dev/dux-shell/core/internal/keybinds/providers"
)

func TestKeybindEditFailure(t *testing.T) {
	for _, tc := range []struct {
		err  error
		code string
	}{
		{&providers.AqueousError{Code: "external_change", Message: "changed"}, "external_change"},
		{fmt.Errorf("helper: %w", &providers.AqueousError{Code: "read_only", Message: "denied"}), "read_only"},
		{errors.New("transport failed"), "command_failed"},
	} {
		result := keybindEditFailure(tc.err)
		if result["success"] != false || result["code"] != tc.code || result["message"] != tc.err.Error() {
			t.Fatalf("unexpected failure result: %#v", result)
		}
	}
}
