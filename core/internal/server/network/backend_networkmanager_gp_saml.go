package network

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"os/exec"
	"strings"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
)

type openConnectAuthResult struct {
	Cookie      string
	Host        string
	User        string
	Fingerprint string
}

type openConnectAuthError struct {
	cause      error
	serverCert string
}

func (e *openConnectAuthError) Error() string {
	return fmt.Sprintf("openconnect --authenticate failed: %v", e.cause)
}

func (e *openConnectAuthError) Unwrap() error {
	return e.cause
}

// runGlobalProtectSAMLAuth handles GlobalProtect SAML/SSO authentication using gp-saml-gui.
// Only supports protocol=gp. Other protocols need their own implementations.
func (b *NetworkManagerBackend) runGlobalProtectSAMLAuth(ctx context.Context, gateway, protocol string) (*openConnectAuthResult, error) {
	if gateway == "" {
		return nil, fmt.Errorf("GP SAML auth: gateway is empty")
	}
	if protocol != "gp" {
		return nil, fmt.Errorf("only GlobalProtect (protocol=gp) SAML is supported, got: %s", protocol)
	}

	log.Infof("[GP-SAML] Starting GlobalProtect SAML authentication with gp-saml-gui for gateway=%s", gateway)

	gpSamlPath, err := exec.LookPath("gp-saml-gui")
	if err != nil {
		return nil, fmt.Errorf("GlobalProtect SAML requires gp-saml-gui (install: pip install gp-saml-gui): %w", err)
	}

	args := []string{
		"--gateway",
		"--allow-insecure-crypto",
		gateway,
	}

	cmd := exec.CommandContext(ctx, gpSamlPath, args...)

	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return nil, fmt.Errorf("GP SAML auth: failed to create stdout pipe: %w", err)
	}

	stderr, err := cmd.StderrPipe()
	if err != nil {
		return nil, fmt.Errorf("GP SAML auth: failed to create stderr pipe: %w", err)
	}

	if err := cmd.Start(); err != nil {
		return nil, fmt.Errorf("GP SAML auth: failed to start gp-saml-gui: %w", err)
	}

	go func() {
		scanner := bufio.NewScanner(stderr)
		for scanner.Scan() {
			log.Debugf("[GP-SAML] gp-saml-gui: %s", scanner.Text())
		}
	}()

	result := &openConnectAuthResult{Host: gateway}
	var allOutput []string

	scanner := bufio.NewScanner(stdout)
	for scanner.Scan() {
		line := scanner.Text()
		allOutput = append(allOutput, line)
		log.Infof("[GP-SAML] stdout: %s", line)

		switch {
		case strings.HasPrefix(line, "COOKIE="):
			result.Cookie = unshellQuote(strings.TrimPrefix(line, "COOKIE="))
		case strings.HasPrefix(line, "HOST="):
			result.Host = unshellQuote(strings.TrimPrefix(line, "HOST="))
		case strings.HasPrefix(line, "USER="):
			result.User = unshellQuote(strings.TrimPrefix(line, "USER="))
		case strings.HasPrefix(line, "FINGERPRINT="):
			result.Fingerprint = unshellQuote(strings.TrimPrefix(line, "FINGERPRINT="))
		default:
			parseGPSamlFromCommandLine(line, result)
		}
	}

	if err := cmd.Wait(); err != nil {
		if ctx.Err() != nil {
			return nil, fmt.Errorf("GP SAML auth timed out or was cancelled: %w", ctx.Err())
		}
		if result.Cookie == "" {
			return nil, fmt.Errorf("GP SAML auth failed: %w (output: %s)", err, strings.Join(allOutput, "\n"))
		}
		log.Warnf("[GP-SAML] gp-saml-gui exited with error but cookie was captured: %v", err)
	}

	if result.Cookie == "" {
		return nil, fmt.Errorf("GP SAML auth: no cookie in gp-saml-gui output")
	}

	log.Infof("[GP-SAML] Got prelogin-cookie from gp-saml-gui, converting to openconnect cookie via --authenticate")

	// Convert prelogin-cookie to full openconnect cookie format
	ocResult, err := convertGPPreloginCookie(ctx, gateway, result.Cookie, result.User)
	if err != nil {
		return nil, fmt.Errorf("GP SAML auth: failed to convert prelogin-cookie: %w", err)
	}

	result.Cookie = ocResult.Cookie
	result.Host = ocResult.Host
	result.Fingerprint = ocResult.Fingerprint

	log.Infof("[GP-SAML] Authentication successful: user=%s, host=%s, cookie_len=%d, has_fingerprint=%v",
		result.User, result.Host, len(result.Cookie), result.Fingerprint != "")
	return result, nil
}

func convertGPPreloginCookie(ctx context.Context, gateway, preloginCookie, user string) (*openConnectAuthResult, error) {
	return runOpenConnectAuthenticate(ctx, []string{
		"--protocol=gp",
		"--usergroup=gateway:prelogin-cookie",
		"--user=" + user,
		"--passwd-on-stdin",
		"--allow-insecure-crypto",
		"--authenticate",
		gateway,
	}, preloginCookie)
}

func runOpenConnectPasswordAuth(
	ctx context.Context,
	data map[string]string,
	username, password, serverCert string,
) (*openConnectAuthResult, error) {
	if data["protocol"] != "fortinet" {
		return nil, fmt.Errorf("only Fortinet password authentication is supported")
	}
	gateway := data["gateway"]
	if gateway == "" {
		return nil, fmt.Errorf("OpenConnect gateway is empty")
	}
	if username == "" || password == "" {
		return nil, fmt.Errorf("OpenConnect username and password are required")
	}

	args := []string{
		"--protocol=fortinet",
		"--user=" + username,
		"--passwd-on-stdin",
		"--non-inter",
	}
	if usergroup := data["usergroup"]; usergroup != "" {
		args = append(args, "--usergroup="+usergroup)
	}
	if serverCert != "" {
		args = append(args, "--servercert="+serverCert)
	}
	args = append(args, "--authenticate", gateway)

	result, err := runOpenConnectAuthenticate(ctx, args, password)
	if err == nil {
		result.Host = gateway
		if result.Fingerprint == "" {
			result.Fingerprint = serverCert
		}
	}
	return result, err
}

func runOpenConnectAuthenticate(ctx context.Context, args []string, secret string) (*openConnectAuthResult, error) {
	ocPath, err := exec.LookPath("openconnect")
	if err != nil {
		return nil, fmt.Errorf("openconnect not found: %w", err)
	}

	cmd := exec.CommandContext(ctx, ocPath, args...)
	cmd.Stdin = strings.NewReader(secret + "\n")

	output, err := cmd.CombinedOutput()
	result := parseOpenConnectAuthenticateOutput(string(output))
	serverCert := suggestedOpenConnectServerCert(string(output))
	if err != nil {
		if ctx.Err() != nil {
			return nil, fmt.Errorf("openconnect authentication timed out or was cancelled: %w", ctx.Err())
		}
		return nil, &openConnectAuthError{cause: err, serverCert: serverCert}
	}
	if result.Cookie == "" {
		return nil, &openConnectAuthError{
			cause:      errors.New("no COOKIE in command output"),
			serverCert: serverCert,
		}
	}

	log.Infof("[OpenConnect] Authentication successful: cookie_len=%d, host=%s, has_fingerprint=%v",
		len(result.Cookie), result.Host, result.Fingerprint != "")

	return result, nil
}

func parseOpenConnectAuthenticateOutput(output string) *openConnectAuthResult {
	result := &openConnectAuthResult{}
	for line := range strings.SplitSeq(output, "\n") {
		line = strings.TrimSpace(line)
		switch {
		case strings.HasPrefix(line, "COOKIE="):
			result.Cookie = unshellQuote(strings.TrimPrefix(line, "COOKIE="))
		case strings.HasPrefix(line, "HOST="):
			result.Host = unshellQuote(strings.TrimPrefix(line, "HOST="))
		case strings.HasPrefix(line, "FINGERPRINT="):
			result.Fingerprint = unshellQuote(strings.TrimPrefix(line, "FINGERPRINT="))
		case strings.HasPrefix(line, "CONNECT_URL="):
			connectURL := unshellQuote(strings.TrimPrefix(line, "CONNECT_URL="))
			if connectURL != "" && result.Host == "" {
				result.Host = connectURL
			}
		}
	}
	return result
}

func unshellQuote(s string) string {
	if len(s) >= 2 {
		if (s[0] == '\'' && s[len(s)-1] == '\'') ||
			(s[0] == '"' && s[len(s)-1] == '"') {
			return s[1 : len(s)-1]
		}
	}
	return s
}

func parseGPSamlFromCommandLine(line string, result *openConnectAuthResult) {
	if !strings.Contains(line, "openconnect") {
		return
	}

	for part := range strings.FieldsSeq(line) {
		switch {
		case strings.HasPrefix(part, "--cookie="):
			if result.Cookie == "" {
				result.Cookie = strings.TrimPrefix(part, "--cookie=")
			}
		case strings.HasPrefix(part, "--servercert="):
			if result.Fingerprint == "" {
				result.Fingerprint = strings.TrimPrefix(part, "--servercert=")
			}
		case strings.HasPrefix(part, "--user="):
			if result.User == "" {
				result.User = strings.TrimPrefix(part, "--user=")
			}
		}
	}
}
