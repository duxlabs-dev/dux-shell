package network

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestGlobalProtectOutputRedacted(t *testing.T) {
	if os.Getenv("DMS_TEST_GP_REDACTION_CHILD") == "1" {
		backend := &NetworkManagerBackend{}
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		result, err := backend.runGlobalProtectSAMLAuth(ctx, "vpn.example", "gp")
		if os.Getenv("DMS_TEST_GP_FAKE_MODE") == "failure" {
			if err == nil {
				t.Fatal("expected helper failure")
			}
			t.Logf("returned error: %v", err)
		} else if err != nil || result.Cookie != "DUMMY-GP-FINAL-COOKIE" {
			t.Fatalf("authentication failed: %v", err)
		}
		return
	}

	dir := t.TempDir()
	scripts := map[string]string{
		"gp-saml-gui": `#!/bin/sh
[ "$#" = 3 ] && [ "$1" = --gateway ] && [ "$2" = --allow-insecure-crypto ] && [ "$3" = vpn.example ] || exit 9
printf '%s\n' 'DUMMY-GP-STDERR-SECRET' >&2
printf '%s\n' 'DIAGNOSTIC=DUMMY-GP-STDOUT-SECRET'
if [ "$DMS_TEST_GP_FAKE_MODE" = failure ]; then exit 1; fi
printf '%s\n' 'COOKIE=DUMMY-GP-PRELOGIN-SECRET' 'HOST=vpn.example' 'USER=synthetic-user'
`,
		"openconnect": `#!/bin/sh
[ "$#" = 7 ] && [ "$1" = --protocol=gp ] && [ "$2" = --usergroup=gateway:prelogin-cookie ] && [ "$3" = --user=synthetic-user ] && [ "$4" = --passwd-on-stdin ] && [ "$5" = --allow-insecure-crypto ] && [ "$6" = --authenticate ] && [ "$7" = vpn.example ] || exit 9
IFS= read -r secret
[ "$secret" = DUMMY-GP-PRELOGIN-SECRET ] || exit 10
printf '%s\n' 'COOKIE=DUMMY-GP-FINAL-COOKIE' 'HOST=vpn.example' 'FINGERPRINT=sha256:dummy'
`,
	}
	for name, script := range scripts {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(script), 0700); err != nil {
			t.Fatal(err)
		}
	}
	for _, mode := range []string{"success", "failure"} {
		t.Run(mode, func(t *testing.T) {
			// A subprocess captures the logger without mutating global writers.
			ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
			defer cancel()
			cmd := exec.CommandContext(ctx, os.Args[0], "-test.run=^TestGlobalProtectOutputRedacted$", "-test.v")
			cmd.Env = append(os.Environ(),
				"DMS_TEST_GP_REDACTION_CHILD=1", "DMS_TEST_GP_FAKE_MODE="+mode,
				"PATH="+dir+string(os.PathListSeparator)+os.Getenv("PATH"),
				"DBUS_SYSTEM_BUS_ADDRESS=unix:path=/nonexistent-gp-test-bus",
				"DBUS_SESSION_BUS_ADDRESS=unix:path=/nonexistent-gp-test-bus")
			output, err := cmd.CombinedOutput()
			if err != nil {
				t.Fatalf("synthetic authentication subprocess failed: %v\n%s", err, output)
			}
			for _, secret := range []string{"DUMMY-GP-PRELOGIN-SECRET", "DUMMY-GP-FINAL-COOKIE", "DUMMY-GP-STDERR-SECRET", "DUMMY-GP-STDOUT-SECRET"} {
				if strings.Contains(string(output), secret) {
					t.Error("authentication secret appeared in logs or returned error")
				}
			}
		})
	}
}
