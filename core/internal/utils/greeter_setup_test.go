package utils

import (
	"context"
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

func fakeDmsGreeter(t *testing.T, script string) {
	t.Helper()
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "dms-greeter"), []byte("#!/bin/sh\n"+script), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
}

func stubValidate(t *testing.T, fn func(context.Context, string) error) {
	t.Helper()
	saved := validateSudoPassword
	validateSudoPassword = fn
	t.Cleanup(func() { validateSudoPassword = saved })
}

func TestRunDmsGreeterInstallRunsAsUserAfterCachingSudo(t *testing.T) {
	fakeDmsGreeter(t, `echo "args=$*"; echo "sudo_user=${SUDO_USER:-none} privesc=${DMS_PRIVESC:-unset}"`+"\n")
	t.Setenv("SUDO_USER", "")
	var validated string
	stubValidate(t, func(_ context.Context, password string) error {
		validated = password
		return nil
	})

	var lines []string
	if err := RunDmsGreeterInstall("hunter2", func(l string) { lines = append(lines, l) }); err != nil {
		t.Fatalf("RunDmsGreeterInstall: %v", err)
	}
	if validated != "hunter2" {
		t.Fatalf("validated password %q, want hunter2", validated)
	}
	want := []string{"args=install --yes", "sudo_user=none privesc=sudo"}
	if !reflect.DeepEqual(lines, want) {
		t.Fatalf("output = %v, want %v", lines, want)
	}
}
