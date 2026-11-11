package distros

import (
	"context"
	"os"
	"testing"
)

// The real probe re-execs os.Executable, which under go test is this binary: a fork bomb.
func TestMain(m *testing.M) {
	probeDuxQtBase = func(context.Context) error { return nil }
	os.Exit(m.Run())
}
