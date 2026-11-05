package network

import (
	"bytes"
	"context"
	"encoding/base64"
	"errors"
	"io"
	"net"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"syscall"
	"time"
)

const (
	openConnectHelperService  = "org.freedesktop.NetworkManager.openconnect"
	openConnectHelperMaxBytes = 1 << 20
	openConnectHelperMaxValue = 256 << 10
	openConnectHelperTimeout  = 5 * time.Minute
)

var (
	errOpenConnectHelperUnavailable  = errors.New("openconnect helper unavailable")
	errOpenConnectHelperCancelled    = errors.New("openconnect helper cancelled")
	errOpenConnectHelperMalformed    = errors.New("openconnect helper malformed response")
	errOpenConnectHelperFailed       = errors.New("openconnect helper failed")
	errOpenConnectHelperInvalidInput = errors.New("openconnect helper invalid input")
)

type openConnectHelperResult struct {
	Secrets map[string]string
	// Metadata belongs to vpn.secrets, not vpn.data. Never persist Secrets.
	Metadata map[string]string
}

func findOpenConnectAuthHelper() (string, error) {
	for _, dir := range []string{"/usr/lib/NetworkManager/VPN", "/usr/lib64/NetworkManager/VPN", "/usr/local/lib/NetworkManager/VPN", "/etc/NetworkManager/VPN"} {
		path := filepath.Join(dir, "nm-openconnect-service.name")
		if !openConnectHelperTrustedPath(path) {
			continue
		}
		helper, err := parseOpenConnectAuthHelperDescriptor(path)
		if err == nil && openConnectHelperTrustedPath(helper) {
			return helper, nil
		}
	}
	return "", errOpenConnectHelperUnavailable
}

func openConnectHelperTrustedPath(path string) bool {
	resolved, err := filepath.EvalSymlinks(path)
	if err != nil || !filepath.IsAbs(resolved) {
		return false
	}
	for {
		info, err := os.Stat(resolved)
		if err != nil || info.Mode().Perm()&0022 != 0 {
			return false
		}
		stat, ok := info.Sys().(*syscall.Stat_t)
		if !ok || stat.Uid != 0 {
			return false
		}
		parent := filepath.Dir(resolved)
		if parent == resolved {
			return true
		}
		resolved = parent
	}
}

// The path-taking parser is for the trusted registry and tests, never VPN data.
func parseOpenConnectAuthHelperDescriptor(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", errOpenConnectHelperUnavailable
	}
	defer f.Close()
	content, err := io.ReadAll(io.LimitReader(f, 65537))
	if err != nil || len(content) > 65536 || bytes.IndexByte(content, 0) >= 0 {
		return "", errOpenConnectHelperUnavailable
	}
	section := ""
	values := make(map[string]string)
	for line := range strings.SplitSeq(string(content), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") || strings.HasPrefix(line, ";") {
			continue
		}
		if strings.HasPrefix(line, "[") && strings.HasSuffix(line, "]") {
			section = line[1 : len(line)-1]
			continue
		}
		key, value, ok := strings.Cut(line, "=")
		if !ok || section == "" {
			return "", errOpenConnectHelperUnavailable
		}
		key = section + "/" + strings.TrimSpace(key)
		if _, exists := values[key]; exists {
			return "", errOpenConnectHelperUnavailable
		}
		values[key] = strings.TrimSpace(value)
	}
	helper := values["GNOME/auth-dialog"]
	if values["VPN Connection/service"] != openConnectHelperService || !filepath.IsAbs(helper) {
		return "", errOpenConnectHelperUnavailable
	}
	info, err := os.Stat(helper)
	if err != nil || !info.Mode().IsRegular() || info.Mode().Perm()&0111 == 0 {
		return "", errOpenConnectHelperUnavailable
	}
	return helper, nil
}

func openConnectHelperMetadataKey(key string) bool {
	switch key {
	case "xmlconfig", "lasthost", "save_passwords", "autoconnect":
		return true
	}
	if strings.HasPrefix(key, "certificate:") {
		return openConnectHelperGateway(strings.TrimPrefix(key, "certificate:"))
	}
	if !strings.HasPrefix(key, "form:") {
		return false
	}
	form, field, ok := strings.Cut(strings.TrimPrefix(key, "form:"), ":")
	if !ok || form == "" || field == "" {
		return false
	}
	// Only remember known identity/group fields, not arbitrary TEXT answers.
	switch strings.ToLower(field) {
	case "username", "group_list":
		return true
	default:
		return false
	}
}

func openConnectHelperDataKey(key string) bool {
	switch key {
	case "gateway", "protocol", "cacert", "usercert", "userkey", "mcacert", "mcakey",
		"pem_passphrase_fsid", "prevent_invalid_cert", "proxy", "enable_csd_trojan",
		"csd_wrapper", "reported_os", "useragent", "stoken_source", "mtu", "disable_udp", "authtype":
		return true
	}
	return false
}

// libnm's read_vpn_details uses '=...' continuation lines, not C escaping.
func normalizeOpenConnectHelperMetadata(key, value string) (string, bool) {
	if !openConnectHelperMetadataKey(key) || strings.ContainsAny(key, "\x00\r\n") || len(key) > openConnectHelperMaxValue || len(value) > openConnectHelperMaxValue {
		return "", false
	}
	switch key {
	case "xmlconfig":
		value = strings.NewReplacer("\n", "", "\r", "").Replace(value)
		if _, err := base64.StdEncoding.Strict().DecodeString(value); err != nil {
			return "", false
		}
	case "save_passwords", "autoconnect":
		if value != "yes" && value != "no" {
			return "", false
		}
	}
	// The helper echoes metadata as raw lines, without stdout escaping.
	if strings.ContainsAny(value, "\x00\r\n") {
		return "", false
	}
	return value, true
}

func encodeOpenConnectHelperInput(data, secrets map[string]string) ([]byte, error) {
	var out bytes.Buffer
	for _, group := range []struct {
		prefix string
		values map[string]string
		allow  func(string) bool
	}{{"DATA", data, openConnectHelperDataKey}, {"SECRET", secrets, openConnectHelperMetadataKey}} {
		keys := make([]string, 0, len(group.values))
		for key, value := range group.values {
			if key == "" || strings.ContainsAny(key, "\x00\r\n") || strings.ContainsRune(value, 0) || len(key) > openConnectHelperMaxValue || len(value) > openConnectHelperMaxValue {
				return nil, errOpenConnectHelperInvalidInput
			}
			if group.allow(key) {
				keys = append(keys, key)
			}
		}
		sort.Strings(keys)
		for _, key := range keys {
			value := group.values[key]
			if group.prefix == "SECRET" {
				var ok bool
				value, ok = normalizeOpenConnectHelperMetadata(key, value)
				if !ok {
					continue
				}
			}
			size := len(group.prefix)*2 + len(key) + len(value) + strings.Count(value, "\n") + 12
			if out.Len()+size+len("DONE\n\nQUIT\n\n") > openConnectHelperMaxBytes {
				return nil, errOpenConnectHelperInvalidInput
			}
			out.WriteString(group.prefix + "_KEY=" + key + "\n" + group.prefix + "_VAL=")
			out.WriteString(strings.ReplaceAll(value, "\n", "\n="))
			out.WriteByte('\n')
		}
	}
	out.WriteString("DONE\n\nQUIT\n\n")
	return out.Bytes(), nil
}

func openConnectHelperGateway(gateway string) bool {
	if gateway == "" || strings.ContainsAny(gateway, "\x00\r\n\t ") {
		return false
	}
	if !strings.Contains(gateway, "://") {
		gateway = "https://" + gateway
	}
	u, err := url.Parse(gateway)
	if err != nil || u.Scheme != "https" || u.User != nil || u.Hostname() == "" || u.Fragment != "" || u.Opaque != "" {
		return false
	}
	host := u.Hostname()
	if net.ParseIP(host) == nil {
		for _, c := range host {
			if !((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-' || c == '.') {
				return false
			}
		}
		if strings.Trim(host, ".-") == "" {
			return false
		}
	}
	if port := u.Port(); port != "" {
		n, err := strconv.Atoi(port)
		if err != nil || n < 1 || n > 65535 {
			return false
		}
	}
	return !strings.HasSuffix(u.Host, ":")
}

// main.c 1.2.10 prints raw key/value lines followed by two empty lines.
// Unlike stdin, stdout has no continuation/escape codec; xmlconfig is base64.
func decodeOpenConnectHelperOutput(output []byte) (*openConnectHelperResult, error) {
	if len(output) > openConnectHelperMaxBytes || bytes.IndexByte(output, 0) >= 0 || !bytes.HasSuffix(output, []byte("\n\n")) {
		return nil, errOpenConnectHelperMalformed
	}
	body := string(output[:len(output)-2])
	result := &openConnectHelperResult{Secrets: map[string]string{"gwcert": "", "resolve": ""}, Metadata: make(map[string]string)}
	seen := make(map[string]bool)
	for body != "" {
		key, rest, ok := strings.Cut(body, "\n")
		if !ok || key == "" || len(key) > openConnectHelperMaxValue || strings.ContainsRune(key, '\r') || seen[key] {
			return nil, errOpenConnectHelperMalformed
		}
		value, rest, ok := strings.Cut(rest, "\n")
		if !ok || len(value) > openConnectHelperMaxValue {
			return nil, errOpenConnectHelperMalformed
		}
		seen[key] = true
		body = rest
		switch key {
		case "cookie", "gateway", "gwcert", "resolve":
			if strings.ContainsRune(value, '\r') {
				return nil, errOpenConnectHelperMalformed
			}
			result.Secrets[key] = value
		default:
			if value, ok := normalizeOpenConnectHelperMetadata(key, value); ok {
				result.Metadata[key] = value
			}
		}
	}
	if strings.TrimSpace(result.Secrets["cookie"]) == "" {
		return nil, errOpenConnectHelperCancelled
	}
	if !openConnectHelperGateway(result.Secrets["gateway"]) {
		return nil, errOpenConnectHelperMalformed
	}
	return result, nil
}

type openConnectHelperOutput struct {
	buffer    bytes.Buffer
	remaining int
	discard   bool
	overflow  bool
	cancel    context.CancelFunc
}

func (w *openConnectHelperOutput) Write(p []byte) (int, error) {
	if len(p) > w.remaining {
		w.overflow = true
		w.cancel()
		return 0, errOpenConnectHelperMalformed
	}
	w.remaining -= len(p)
	if w.discard {
		return len(p), nil
	}
	return w.buffer.Write(p)
}

// Only call for ALLOW_INTERACTION. helperPath is supplied by trusted discovery
// (or explicit test injection), never by a connection's data/secrets.
func runOpenConnectAuthHelper(ctx context.Context, helperPath, uuid, name string, data, secrets map[string]string, requestNew bool) (*openConnectHelperResult, error) {
	if !filepath.IsAbs(helperPath) || uuid == "" || name == "" || len(uuid) > 256 || len(name) > 4096 || strings.ContainsAny(uuid+name, "\x00\r\n") {
		return nil, errOpenConnectHelperInvalidInput
	}
	input, err := encodeOpenConnectHelperInput(data, secrets)
	if err != nil {
		return nil, err
	}
	ctx, timeoutCancel := context.WithTimeout(ctx, openConnectHelperTimeout)
	defer timeoutCancel()
	processCtx, cancel := context.WithCancel(ctx)
	defer cancel()
	args := []string{"-u", uuid, "-n", name, "-s", openConnectHelperService, "-i"}
	if requestNew {
		args = append(args, "-r")
	}
	cmd := exec.CommandContext(processCtx, helperPath, args...)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Cancel = func() error {
		err := syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
		if errors.Is(err, syscall.ESRCH) {
			return os.ErrProcessDone
		}
		return err
	}
	cmd.WaitDelay = 250 * time.Millisecond
	stdout := &openConnectHelperOutput{remaining: openConnectHelperMaxBytes, cancel: cancel}
	stderr := &openConnectHelperOutput{remaining: openConnectHelperMaxBytes, discard: true, cancel: cancel}
	cmd.Stdin = bytes.NewReader(input)
	cmd.Stdout = stdout
	cmd.Stderr = stderr
	err = cmd.Run() // Wait includes stdout EOF, stdin closure, and reaping the helper.
	if cmd.Process != nil && errors.Is(err, exec.ErrWaitDelay) {
		_ = syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
	}
	if ctx.Err() != nil {
		return nil, errors.Join(errOpenConnectHelperCancelled, ctx.Err())
	}
	if stdout.overflow {
		return nil, errOpenConnectHelperMalformed
	}
	if err != nil || stderr.overflow {
		return nil, errOpenConnectHelperFailed
	}
	return decodeOpenConnectHelperOutput(stdout.buffer.Bytes())
}
