package network

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"
)

func TestOpenConnectHelperInput(t *testing.T) {
	data := map[string]string{"gateway": "https://vpn.example", "protocol": "anyconnect", "password": "do-not-send", "stoken_string": "do-not-send", "key_pass": "do-not-send", "auth-dialog": "/tmp/evil"}
	secrets := map[string]string{
		"cookie": "stale", "gateway": "stale", "gwcert": "stale", "resolve": "stale",
		"password": "do-not-send", "form:main:password": "do-not-send", "form:main:PIN": "do-not-send",
		"form:main:secondary_password": "do-not-send", "form:main:otp": "do-not-send", "stoken_string": "do-not-send",
		"save_passwords": "no", "autoconnect": "yes", "form:main:username": "alice", "form:main:group_list": "staff",
		"certificate:vpn.example:443": "sha256:abc", "xmlconfig": "YWJj\nZA==\r\n", "lasthost": "a\n\n=second\nDONE\nQUIT\n",
	}
	got, err := encodeOpenConnectHelperInput(data, secrets)
	if err != nil {
		t.Fatal(err)
	}
	want := "DATA_KEY=gateway\nDATA_VAL=https://vpn.example\nDATA_KEY=protocol\nDATA_VAL=anyconnect\n" +
		"SECRET_KEY=autoconnect\nSECRET_VAL=yes\nSECRET_KEY=certificate:vpn.example:443\nSECRET_VAL=sha256:abc\n" +
		"SECRET_KEY=form:main:group_list\nSECRET_VAL=staff\nSECRET_KEY=form:main:username\nSECRET_VAL=alice\n" +
		"SECRET_KEY=save_passwords\nSECRET_VAL=no\nSECRET_KEY=xmlconfig\nSECRET_VAL=YWJjZA==\nDONE\n\nQUIT\n\n"
	if string(got) != want {
		t.Fatalf("unexpected synthetic input:\n%q\nwant:\n%q", got, want)
	}
	if secrets["cookie"] != "stale" || data["password"] != "do-not-send" {
		t.Fatal("input maps mutated")
	}
	withoutPreferences, err := encodeOpenConnectHelperInput(map[string]string{"gateway": "vpn.example", "save_passwords": "yes"}, nil)
	if err != nil || strings.Contains(string(withoutPreferences), "save_passwords") {
		t.Fatal("must not enable saving or interpret a data option as a secret preference")
	}
}

func TestOpenConnectHelperRawMetadataEcho(t *testing.T) {
	metadata := map[string]string{
		"lasthost": "host\nsecond", "form:main:group_list": "staff\radmin",
		"form:main:username": "alice", "xmlconfig": "YWJj\r\nZA==\n",
	}
	input, err := encodeOpenConnectHelperInput(nil, metadata)
	if err != nil {
		t.Fatal(err)
	}
	// Model the helper's input continuation decoding followed by its unescaped
	// key/value stdout echo. Unsafe metadata must not reach that echo.
	lines := strings.Split(string(input), "\n")
	output := "cookie\nfresh\ngateway\nvpn.example\n"
	key := ""
	for i := 0; i < len(lines); i++ {
		if next, ok := strings.CutPrefix(lines[i], "SECRET_KEY="); ok {
			key = next
		}
		if value, ok := strings.CutPrefix(lines[i], "SECRET_VAL="); ok {
			for i+1 < len(lines) && strings.HasPrefix(lines[i+1], "=") {
				i++
				value += "\n" + strings.TrimPrefix(lines[i], "=")
			}
			output += key + "\n" + value + "\n"
		}
	}
	result, err := decodeOpenConnectHelperOutput([]byte(output + "\n\n"))
	if err != nil {
		t.Fatal(err)
	}
	want := map[string]string{"form:main:username": "alice", "xmlconfig": "YWJjZA=="}
	if !reflect.DeepEqual(result.Metadata, want) || result.Secrets["cookie"] != "fresh" {
		t.Fatal("unsafe metadata survived the helper round trip")
	}
	if !reflect.DeepEqual(openConnectHelperMetadata(metadata), want) {
		t.Fatal("unsafe incoming metadata would be staged for persistence")
	}
}

func TestOpenConnectHelperInvalidMetadataIsOmitted(t *testing.T) {
	for _, item := range []struct{ key, value string }{
		{"xmlconfig", "%%%"}, {"xmlconfig", "YWJ"},
		{"save_passwords", "true"}, {"autoconnect", "sometimes"},
	} {
		t.Run(item.key+"/"+item.value, func(t *testing.T) {
			metadata := map[string]string{item.key: item.value}
			input, err := encodeOpenConnectHelperInput(nil, metadata)
			if err != nil || strings.Contains(string(input), "SECRET_KEY=") {
				t.Fatal("invalid metadata was sent to helper")
			}
			output := "cookie\nfresh\ngateway\nvpn.example\n" + item.key + "\n" + item.value + "\n\n\n"
			result, err := decodeOpenConnectHelperOutput([]byte(output))
			if err != nil || len(result.Metadata) != 0 || result.Secrets["cookie"] != "fresh" {
				t.Fatal("invalid metadata was retained or prevented authentication")
			}
			if len(openConnectHelperMetadata(metadata)) != 0 {
				t.Fatal("invalid metadata was staged for persistence")
			}
		})
	}
}

func TestOpenConnectHelperInputBounds(t *testing.T) {
	for _, values := range []map[string]string{
		{"gateway": "a\x00b"}, {"bad\nkey": "x"}, {"bad\x00key": "x"}, {"": "x"},
		{"gateway": strings.Repeat("x", openConnectHelperMaxValue+1)},
		{"gateway": strings.Repeat("\n", openConnectHelperMaxValue), "proxy": strings.Repeat("\n", openConnectHelperMaxValue)},
	} {
		if _, err := encodeOpenConnectHelperInput(values, nil); !errors.Is(err, errOpenConnectHelperInvalidInput) {
			t.Fatalf("expected invalid input, got %v", err)
		}
	}
	if _, err := encodeOpenConnectHelperInput(map[string]string{"gateway": strings.Repeat("x", openConnectHelperMaxValue)}, nil); err != nil {
		t.Fatal("value at limit rejected")
	}
}

func TestOpenConnectHelperDecode(t *testing.T) {
	output := "cookie\nfresh-cookie\ngateway\nhttps://vpn.example:443/path\ngwcert\nsha256:abc\nresolve\nvpn.example:192.0.2.1\n" +
		"form:main:username\nalice\nform:main:group_list\nstaff\nxmlconfig\nYWJj\nlasthost\nvpn.example\nsave_passwords\nno\nautoconnect\nyes\ncertificate:vpn.example:443\nsha256:abc\n" +
		"password\nnever-persist\nform:main:password\nnever-persist\nform:main:token\nnever-persist\nform:main:PIN\nnever-persist\nform:main:passcode\nnever-persist\nform:main:credential\nnever-persist\nform:main:auth\nnever-persist\nstoken_string\nnever-persist\nkey_pass\nnever-persist\nunknown\nnever-persist\n\n\n"
	got, err := decodeOpenConnectHelperOutput([]byte(output))
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(got.Secrets, map[string]string{"cookie": "fresh-cookie", "gateway": "https://vpn.example:443/path", "gwcert": "sha256:abc", "resolve": "vpn.example:192.0.2.1"}) {
		t.Fatal("unexpected authentication secrets")
	}
	if !reflect.DeepEqual(got.Metadata, map[string]string{"form:main:username": "alice", "form:main:group_list": "staff", "xmlconfig": "YWJj", "lasthost": "vpn.example", "save_passwords": "no", "autoconnect": "yes", "certificate:vpn.example:443": "sha256:abc"}) {
		t.Fatal("unexpected metadata or sensitive metadata retained")
	}
	got, err = decodeOpenConnectHelperOutput([]byte("cookie\nnew\ngateway\nvpn.example:443\n\n\n"))
	if err != nil || got.Secrets["gwcert"] != "" || got.Secrets["resolve"] != "" || len(got.Secrets) != 4 {
		t.Fatal("missing empty NetworkManager defaults")
	}
}

func TestOpenConnectHelperDecodeRejects(t *testing.T) {
	valid := "cookie\nnew\ngateway\nvpn.example\n"
	for _, tt := range []struct {
		name   string
		output string
		want   error
	}{
		{"empty", "", errOpenConnectHelperMalformed},
		{"cancel", "\n\n", errOpenConnectHelperCancelled},
		{"metadata-only-cancel", "save_passwords\nyes\n\n\n", errOpenConnectHelperCancelled},
		{"empty-cookie", "cookie\n\ngateway\nvpn.example\n\n\n", errOpenConnectHelperCancelled},
		{"whitespace-cookie", "cookie\n \ngateway\nvpn.example\n\n\n", errOpenConnectHelperCancelled},
		{"no-gateway", "cookie\nnew\n\n\n", errOpenConnectHelperMalformed},
		{"bad-gateway", "cookie\nnew\ngateway\nhttps://user:pass@host\n\n\n", errOpenConnectHelperMalformed},
		{"duplicate", valid + "cookie\nother\n\n\n", errOpenConnectHelperMalformed},
		{"duplicate-ignored", valid + "password\none\npassword\ntwo\n\n\n", errOpenConnectHelperMalformed},
		{"truncated", valid + "\n", errOpenConnectHelperMalformed},
		{"odd-lines", valid + "orphan\n\n\n", errOpenConnectHelperMalformed},
		{"trailing", valid + "\n\ntrailing", errOpenConnectHelperMalformed},
		{"trailing-pair", valid + "\n\nextra\nvalue\n\n\n", errOpenConnectHelperMalformed},
		{"nul", valid + "xmlconfig\na\x00b\n\n\n", errOpenConnectHelperMalformed},
		{"large-value", valid + "xmlconfig\n" + strings.Repeat("x", openConnectHelperMaxValue+1) + "\n\n\n", errOpenConnectHelperMalformed},
		{"large-total", strings.Repeat("x", openConnectHelperMaxBytes+1), errOpenConnectHelperMalformed},
	} {
		t.Run(tt.name, func(t *testing.T) {
			if _, err := decodeOpenConnectHelperOutput([]byte(tt.output)); !errors.Is(err, tt.want) {
				t.Fatalf("got %v, want %v", err, tt.want)
			}
		})
	}
}

func TestOpenConnectHelperGateway(t *testing.T) {
	for _, value := range []string{"vpn.example", "vpn.example:443", "192.0.2.1:8443", "[2001:db8::1]:443", "https://vpn.example/path?query=1", "https://[2001:db8::1]/"} {
		if !openConnectHelperGateway(value) {
			t.Errorf("valid gateway rejected: %q", value)
		}
	}
	for _, value := range []string{"", " ", "http://vpn.example", "file:///etc/passwd", "https://", "https://user@vpn.example", "vpn.example:0", "vpn.example:65536", "vpn.example:abc", "vpn.example:", "bad host", "host\r", "https://vpn.example/#fragment", "https://..", "https://foo\\bar"} {
		if openConnectHelperGateway(value) {
			t.Errorf("invalid gateway accepted: %q", value)
		}
	}
}

func openConnectHelperScript(t *testing.T, body string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "helper")
	if err := os.WriteFile(path, []byte("#!/bin/sh\nset -eu\n"+body), 0700); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestOpenConnectHelperRun(t *testing.T) {
	for _, requestNew := range []bool{false, true} {
		t.Run(strconv.FormatBool(requestNew), func(t *testing.T) {
			count := 7
			reprompt := ""
			if requestNew {
				count = 8
				reprompt = `[ "$8" = '-r' ]` + "\n"
			}
			script := fmt.Sprintf(`[ "$#" = '%d' ]
[ "$1" = '-u' ] && [ "$2" = 'test-uuid' ]
[ "$3" = '-n' ] && [ "$4" = 'Test VPN' ]
[ "$5" = '-s' ] && [ "$6" = 'org.freedesktop.NetworkManager.openconnect' ]
[ "$7" = '-i' ]
%sinput=$(cat; printf '#')
expected=$(printf 'DATA_KEY=gateway\nDATA_VAL=vpn.example\nSECRET_KEY=save_passwords\nSECRET_VAL=no\nDONE\n\nQUIT\n\n#')
[ "$input" = "$expected" ]
printf 'cookie\nfresh\ngateway\nhttps://vpn.example/\n\n\n'
`, count, reprompt)
			path := openConnectHelperScript(t, script)
			result, err := runOpenConnectAuthHelper(context.Background(), path, "test-uuid", "Test VPN", map[string]string{"gateway": "vpn.example", "password": "never-argv"}, map[string]string{"cookie": "stale", "gateway": "stale", "gwcert": "stale", "resolve": "stale", "save_passwords": "no"}, requestNew)
			if err != nil || result.Secrets["cookie"] != "fresh" {
				t.Fatalf("run failed: %v", err)
			}
		})
	}
}

func TestOpenConnectHelperRunErrors(t *testing.T) {
	for _, tt := range []struct {
		name string
		body string
		want error
	}{
		{"zero-exit-stale-cookie", `input=$(cat); case "$input" in *stale*) exit 9;; esac; printf 'save_passwords\nyes\n\n\n'`, errOpenConnectHelperCancelled},
		{"nonzero-with-cookie", `cat >/dev/null; printf 'cookie\nfresh\ngateway\nvpn.example\n\n\n'; printf 'SENSITIVE' >&2; exit 2`, errOpenConnectHelperFailed},
		{"malformed", `cat >/dev/null; printf 'SENSITIVE'`, errOpenConnectHelperMalformed},
		{"duplicate", `cat >/dev/null; printf 'cookie\none\ncookie\ntwo\ngateway\nvpn.example\n\n\n'`, errOpenConnectHelperMalformed},
		{"stdout-limit", `cat >/dev/null; dd if=/dev/zero bs=65536 count=17 2>/dev/null`, errOpenConnectHelperMalformed},
		{"stderr-limit", `cat >/dev/null; dd if=/dev/zero bs=65536 count=17 >&2 2>/dev/null`, errOpenConnectHelperFailed},
		{"after-terminator", `cat >/dev/null; printf 'cookie\nfresh\ngateway\nvpn.example\n\n\n'; sleep 0.05; printf 'trailing'`, errOpenConnectHelperMalformed},
	} {
		t.Run(tt.name, func(t *testing.T) {
			ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
			defer cancel()
			_, err := runOpenConnectAuthHelper(ctx, openConnectHelperScript(t, tt.body), "uuid", "name", map[string]string{"gateway": "vpn.example"}, map[string]string{"cookie": "stale"}, false)
			if !errors.Is(err, tt.want) || strings.Contains(err.Error(), "SENSITIVE") {
				t.Fatalf("got %v, want %v", err, tt.want)
			}
		})
	}
	_, err := runOpenConnectAuthHelper(context.Background(), "/nonexistent/helper", "uuid", "name", nil, nil, false)
	if !errors.Is(err, errOpenConnectHelperFailed) {
		t.Fatal(err)
	}
	_, err = runOpenConnectAuthHelper(context.Background(), "relative", "uuid", "name", nil, nil, false)
	if !errors.Is(err, errOpenConnectHelperInvalidInput) {
		t.Fatal(err)
	}
}

func TestOpenConnectHelperCancellationAndChildren(t *testing.T) {
	for _, leaderExits := range []bool{false, true} {
		t.Run(strconv.FormatBool(leaderExits), func(t *testing.T) {
			pidFile := filepath.Join(t.TempDir(), "child-pid")
			body := fmt.Sprintf("cat >/dev/null\nsleep 30 &\nprintf '%%s' \"$!\" > '%s'\n", pidFile)
			if leaderExits {
				body += "printf 'cookie\\nfresh\\ngateway\\nvpn.example\\n\\n\\n'\nexit 0\n"
			} else {
				body += "wait\n"
			}
			ctx, cancel := context.WithTimeout(context.Background(), 600*time.Millisecond)
			defer cancel()
			start := time.Now()
			_, err := runOpenConnectAuthHelper(ctx, openConnectHelperScript(t, body), "uuid", "name", nil, nil, false)
			if time.Since(start) > 2*time.Second {
				t.Fatal("child holding pipes blocked return")
			}
			want := errOpenConnectHelperCancelled
			if leaderExits {
				want = errOpenConnectHelperFailed
			}
			if !errors.Is(err, want) {
				t.Fatalf("got %v, want %v", err, want)
			}
			if !leaderExits && !errors.Is(err, context.DeadlineExceeded) {
				t.Fatal("deadline cause lost")
			}
			pidBytes, err := os.ReadFile(pidFile)
			if err != nil {
				t.Fatal(err)
			}
			pid, err := strconv.Atoi(string(pidBytes))
			if err != nil || pid <= 1 {
				t.Fatal("invalid child PID")
			}
			t.Cleanup(func() { _ = syscall.Kill(pid, syscall.SIGKILL) })
			deadline := time.Now().Add(time.Second)
			for {
				stat, err := os.ReadFile(fmt.Sprintf("/proc/%d/stat", pid))
				// Orphans may await the system's reaper; they must not still run.
				if os.IsNotExist(err) || (err == nil && strings.Contains(string(stat), ") Z ")) {
					break
				}
				if time.Now().After(deadline) {
					t.Fatal("helper child remains running")
				}
				time.Sleep(10 * time.Millisecond)
			}
		})
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	_, err := runOpenConnectAuthHelper(ctx, "/nonexistent/helper", "uuid", "name", nil, nil, false)
	if !errors.Is(err, context.Canceled) || !errors.Is(err, errOpenConnectHelperCancelled) {
		t.Fatal("pre-cancelled context not preserved")
	}
}

func TestOpenConnectHelperDescriptor(t *testing.T) {
	helper := openConnectHelperScript(t, "exit 99\n")
	valid := "[VPN Connection]\nservice=" + openConnectHelperService + "\n[GNOME]\nauth-dialog=" + helper + "\n"
	for _, tt := range []struct {
		name    string
		content string
		valid   bool
	}{
		{"valid", valid, true},
		{"whitespace", "# Comment\n[VPN Connection]\n service = " + openConnectHelperService + "\n[GNOME]\nauth-dialog = " + helper + "\n", true},
		{"wrong-service", strings.ReplaceAll(valid, openConnectHelperService, "org.freedesktop.NetworkManager.openvpn"), false},
		{"wrong-section", strings.ReplaceAll(valid, "[GNOME]", "[libnm]"), false},
		{"relative", strings.ReplaceAll(valid, helper, "nm-openconnect-auth-dialog"), false},
		{"command-with-args", strings.ReplaceAll(valid, helper, helper+" --evil"), false},
		{"duplicate", valid + "auth-dialog=" + helper + "\n", false},
		{"nul", valid + "\x00", false},
		{"large", valid + strings.Repeat("#", 65537), false},
		{"missing", strings.ReplaceAll(valid, helper, "/nonexistent/helper"), false},
		{"directory", strings.ReplaceAll(valid, helper, filepath.Dir(helper)), false},
	} {
		t.Run(tt.name, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "service.name")
			if err := os.WriteFile(path, []byte(tt.content), 0600); err != nil {
				t.Fatal(err)
			}
			got, err := parseOpenConnectAuthHelperDescriptor(path)
			if tt.valid && (err != nil || got != helper) {
				t.Fatalf("got %q, %v", got, err)
			}
			if !tt.valid && !errors.Is(err, errOpenConnectHelperUnavailable) {
				t.Fatalf("invalid descriptor accepted: %q, %v", got, err)
			}
		})
	}
	if err := os.Chmod(helper, 0600); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(t.TempDir(), "service.name")
	if err := os.WriteFile(path, []byte(valid), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := parseOpenConnectAuthHelperDescriptor(path); !errors.Is(err, errOpenConnectHelperUnavailable) {
		t.Fatal("non-executable helper accepted")
	}
	if openConnectHelperTrustedPath(helper) {
		t.Fatal("temporary user-controlled helper trusted by system discovery")
	}
}
