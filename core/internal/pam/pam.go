package pam

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"

	"github.com/duxlabs-dev/dux-shell/core/internal/privesc"
	"github.com/duxlabs-dev/dux-shell/core/internal/utils"
)

const (
	LockscreenPamManagedBlockStart = "# BEGIN DMS LOCKSCREEN AUTH (managed by dms greeter sync)"
	LockscreenPamManagedBlockEnd   = "# END DMS LOCKSCREEN AUTH"

	LockscreenU2FPamManagedBlockStart = "# BEGIN DMS LOCKSCREEN U2F AUTH (managed by dms auth sync)"
	LockscreenU2FPamManagedBlockEnd   = "# END DMS LOCKSCREEN U2F AUTH"

	DankshellPamPath    = "/etc/pam.d/dankshell"
	DankshellU2FPamPath = "/etc/pam.d/dankshell-u2f"
)

// lockscreenPamEntryCandidates are the /etc/pam.d entry-point services tried in
// order. "login" is first so systems that ship it behave exactly as before; the
// rest cover distros (or minimal installs) with no /etc/pam.d/login.
// lockscreenPamBaseDirs mirrors libpam's search order: /etc overrides, then the
// vendor dir (/usr/lib) and the stateless-distro default (/usr/share).
// /usr/local/etc/pam.d is OpenPAM's ports dir on FreeBSD (openpam_configure).
var lockscreenPamBaseDirs = []string{"/etc/pam.d", "/usr/lib/pam.d", "/usr/share/pam.d", "/usr/local/etc/pam.d"}

// Standalone auth+account services, most universal first. login exists almost
// everywhere (util-linux); system-* cover Fedora/Arch/Gentoo/SUSE-Leap.
var lockscreenPamEntryCandidates = []string{
	"login",
	"system-auth",
	"system-login",
	"system-local-login",
}

// Fallback for distros with no standalone login service, only shared building
// blocks: openSUSE/Debian (common-*), Alpine/postmarketOS (base-*), FreeBSD
// (system holds both stanzas, included by login).
var lockscreenPamSharedIncludePairs = []struct {
	auth    string
	account string
}{
	{auth: "common-auth", account: "common-account"},
	{auth: "base-auth", account: "base-account"},
	{auth: "system", account: "system"},
}

var includedPamAuthFiles = []string{
	"system-auth",
	"common-auth",
	"password-auth",
	"system-login",
	"system-local-login",
	"common-auth-pc",
	"login",
	"system",
}

type AuthSettings struct {
	EnableFprint bool `json:"enableFprint"`
	EnableU2f    bool `json:"enableU2f"`
}

type SyncAuthOptions struct {
	HomeDir string
}

type syncDeps struct {
	pamDir           string
	dankshellPath    string
	dankshellU2fPath string
	isNixOS          func() bool
	readFile         func(string) ([]byte, error)
	stat             func(string) (os.FileInfo, error)
	createTemp       func(string, string) (*os.File, error)
	removeFile       func(string) error
	runSudoCmd       func(string, string, ...string) error
}

type lockscreenPamIncludeDirective struct {
	target     string
	filterType string
}

type lockscreenPamResolver struct {
	baseDirs []string
	readFile func(string) ([]byte, error)
}

// locate resolves a service/include name across baseDirs (libpam vendor-dir
// fallback). Targets may not escape the base dirs.
func (r lockscreenPamResolver) locate(target string) (string, error) {
	target = strings.TrimSpace(target)
	if target == "" {
		return "", fmt.Errorf("empty PAM include target")
	}

	if filepath.IsAbs(target) {
		clean := filepath.Clean(target)
		for _, dir := range r.baseDirs {
			if filepath.Dir(clean) == filepath.Clean(dir) {
				return clean, nil
			}
		}
		return "", fmt.Errorf("unsupported PAM include outside PAM dirs: %s", target)
	}

	clean := filepath.Clean(target)
	if clean == "." || clean == ".." || strings.HasPrefix(clean, ".."+string(os.PathSeparator)) {
		return "", fmt.Errorf("invalid PAM include target: %s", target)
	}

	var firstErr error
	for _, dir := range r.baseDirs {
		path := filepath.Join(filepath.Clean(dir), clean)
		if _, err := r.readFile(path); err != nil {
			if firstErr == nil {
				firstErr = err
			}
			continue
		}
		return path, nil
	}
	if firstErr == nil {
		firstErr = os.ErrNotExist
	}
	return "", firstErr
}

func defaultSyncDeps() syncDeps {
	return syncDeps{
		pamDir:           "/etc/pam.d",
		dankshellPath:    DankshellPamPath,
		dankshellU2fPath: DankshellU2FPamPath,
		isNixOS:          IsNixOS,
		readFile:         os.ReadFile,
		stat:             os.Stat,
		createTemp:       os.CreateTemp,
		removeFile:       os.Remove,
		runSudoCmd: func(password, command string, args ...string) error {
			return privesc.Run(context.Background(), password, append([]string{command}, args...)...)
		},
	}
}

func IsNixOS() bool {
	_, err := os.Stat("/etc/NIXOS")
	return err == nil
}

func ReadAuthSettings(homeDir string) (AuthSettings, error) {
	settingsPath := filepath.Join(homeDir, ".config", "dms", "settings.json")
	data, err := os.ReadFile(settingsPath)
	if err != nil {
		if os.IsNotExist(err) {
			return AuthSettings{}, nil
		}
		return AuthSettings{}, fmt.Errorf("failed to read settings at %s: %w", settingsPath, err)
	}
	if strings.TrimSpace(string(data)) == "" {
		return AuthSettings{}, nil
	}

	var settings AuthSettings
	if err := json.Unmarshal(data, &settings); err != nil {
		return AuthSettings{}, fmt.Errorf("failed to parse settings at %s: %w", settingsPath, err)
	}
	return settings, nil
}

func SyncAuthConfig(logFunc func(string), sudoPassword string, options SyncAuthOptions) error {
	return syncAuthConfigWithDeps(logFunc, sudoPassword, options, defaultSyncDeps())
}

func syncAuthConfigWithDeps(logFunc func(string), sudoPassword string, options SyncAuthOptions, deps syncDeps) error {
	homeDir := strings.TrimSpace(options.HomeDir)
	if homeDir == "" {
		var err error
		homeDir, err = os.UserHomeDir()
		if err != nil {
			return fmt.Errorf("failed to get user home directory: %w", err)
		}
	}

	settings, err := ReadAuthSettings(homeDir)
	if err != nil {
		return err
	}

	if err := syncLockscreenPamConfigWithDeps(logFunc, sudoPassword, deps); err != nil {
		return err
	}
	if err := syncLockscreenU2FPamConfigWithDeps(logFunc, sudoPassword, settings.EnableU2f, deps); err != nil {
		return err
	}

	return nil
}

func PamTextIncludesFile(pamText, filename string) bool {
	lines := strings.SplitSeq(pamText, "\n")
	for line := range lines {
		trimmed := strings.TrimSpace(line)
		if trimmed == "" || strings.HasPrefix(trimmed, "#") {
			continue
		}
		if strings.Contains(trimmed, filename) &&
			(strings.Contains(trimmed, "include") || strings.Contains(trimmed, "substack") || strings.HasPrefix(trimmed, "@include")) {
			return true
		}
	}
	return false
}

func PamFileHasModule(pamFilePath, module string) bool {
	data, err := os.ReadFile(pamFilePath)
	if err != nil {
		return false
	}
	return pamContentHasModule(string(data), module)
}

func DetectIncludedPamModule(pamText, module string) string {
	return detectIncludedPamModule(pamText, module, defaultSyncDeps())
}

func detectIncludedPamModule(pamText, module string, deps syncDeps) string {
	for _, includedFile := range includedPamAuthFiles {
		if !PamTextIncludesFile(pamText, includedFile) {
			continue
		}
		path := filepath.Join(deps.pamDir, includedFile)
		data, err := deps.readFile(path)
		if err != nil {
			continue
		}
		if pamContentHasModule(string(data), module) {
			return includedFile
		}
	}
	return ""
}

func pamContentHasModule(content, module string) bool {
	lines := strings.SplitSeq(content, "\n")
	for line := range lines {
		trimmed := strings.TrimSpace(line)
		if trimmed == "" || strings.HasPrefix(trimmed, "#") {
			continue
		}
		if strings.Contains(trimmed, module) {
			return true
		}
	}
	return false
}

func hasManagedLockscreenPamFile(content string) bool {
	return strings.Contains(content, LockscreenPamManagedBlockStart) &&
		strings.Contains(content, LockscreenPamManagedBlockEnd)
}

func hasManagedLockscreenU2FPamFile(content string) bool {
	return strings.Contains(content, LockscreenU2FPamManagedBlockStart) &&
		strings.Contains(content, LockscreenU2FPamManagedBlockEnd)
}

func pamDirectiveType(line string) string {
	fields := strings.Fields(line)
	if len(fields) == 0 {
		return ""
	}

	directiveType := strings.TrimPrefix(fields[0], "-")
	switch directiveType {
	case "auth", "account", "password", "session":
		return directiveType
	default:
		return ""
	}
}

func isExcludedLockscreenPamLine(line string) bool {
	for field := range strings.FieldsSeq(line) {
		if strings.HasPrefix(field, "#") {
			break
		}
		if strings.Contains(field, "pam_u2f") || strings.Contains(field, "pam_fprintd") {
			return true
		}
	}
	return false
}

func parseLockscreenPamIncludeDirective(trimmed string, inheritedFilter string) (lockscreenPamIncludeDirective, bool) {
	fields := strings.Fields(trimmed)
	if len(fields) >= 2 && fields[0] == "@include" {
		return lockscreenPamIncludeDirective{
			target:     fields[1],
			filterType: inheritedFilter,
		}, true
	}

	if len(fields) >= 3 && (fields[1] == "include" || fields[1] == "substack") {
		lineType := pamDirectiveType(trimmed)
		if lineType == "" {
			return lockscreenPamIncludeDirective{}, false
		}
		return lockscreenPamIncludeDirective{
			target:     fields[2],
			filterType: lineType,
		}, true
	}

	if len(fields) >= 3 && fields[1] == "@include" {
		lineType := pamDirectiveType(trimmed)
		if lineType == "" {
			return lockscreenPamIncludeDirective{}, false
		}
		return lockscreenPamIncludeDirective{
			target:     fields[2],
			filterType: lineType,
		}, true
	}

	return lockscreenPamIncludeDirective{}, false
}

func (r lockscreenPamResolver) resolveService(serviceName string, filterType string, stack []string) ([]string, error) {
	path, err := r.locate(serviceName)
	if err != nil {
		return nil, fmt.Errorf("failed to read PAM file %s: %w", serviceName, err)
	}

	if slices.Contains(stack, path) {
		chain := append(append([]string{}, stack...), path)
		display := make([]string, 0, len(chain))
		for _, item := range chain {
			display = append(display, filepath.Base(item))
		}
		return nil, fmt.Errorf("cyclic PAM include detected: %s", strings.Join(display, " -> "))
	}

	data, err := r.readFile(path)
	if err != nil {
		return nil, fmt.Errorf("failed to read PAM file %s: %w", path, err)
	}

	var resolved []string
	for rawLine := range strings.SplitSeq(strings.ReplaceAll(string(data), "\r\n", "\n"), "\n") {
		rawLine = strings.TrimRight(rawLine, "\r")
		trimmed := strings.TrimSpace(rawLine)
		if trimmed == "" || strings.HasPrefix(trimmed, "#") || trimmed == "#%PAM-1.0" {
			continue
		}

		if include, ok := parseLockscreenPamIncludeDirective(trimmed, filterType); ok {
			lineType := pamDirectiveType(trimmed)
			if filterType != "" && lineType != "" && lineType != filterType {
				continue
			}

			nested, err := r.resolveService(include.target, include.filterType, append(stack, path))
			if err != nil {
				return nil, err
			}
			resolved = append(resolved, nested...)
			continue
		}

		lineType := pamDirectiveType(trimmed)
		if lineType == "" {
			return nil, fmt.Errorf("unsupported PAM directive in %s: %s", filepath.Base(path), trimmed)
		}
		if filterType != "" && lineType != filterType {
			continue
		}
		if isExcludedLockscreenPamLine(trimmed) {
			continue
		}

		resolved = append(resolved, rawLine)
	}

	return resolved, nil
}

func resolvedLinesHaveAuth(lines []string) bool {
	for _, line := range lines {
		if pamDirectiveType(strings.TrimSpace(line)) == "auth" {
			return true
		}
	}
	return false
}

func (r lockscreenPamResolver) resolveLines() ([]string, error) {
	var lastErr error

	// Standalone login-like services: an existing one is authoritative.
	for _, service := range lockscreenPamEntryCandidates {
		if _, err := r.locate(service); err != nil {
			lastErr = err
			continue
		}
		lines, err := r.resolveService(service, "", nil)
		if err != nil {
			return nil, err
		}
		if !resolvedLinesHaveAuth(lines) {
			return nil, fmt.Errorf("no auth directives remained after filtering %s", service)
		}
		return lines, nil
	}

	// Shared building blocks for distros without a login service (openSUSE,
	// Alpine): stitch the auth stanza to the account stanza when present.
	for _, pair := range lockscreenPamSharedIncludePairs {
		if _, err := r.locate(pair.auth); err != nil {
			lastErr = err
			continue
		}
		authLines, err := r.resolveService(pair.auth, "auth", nil)
		if err != nil {
			return nil, err
		}
		if !resolvedLinesHaveAuth(authLines) {
			lastErr = fmt.Errorf("no auth directives remained after filtering %s", pair.auth)
			continue
		}

		resolved := append([]string{}, authLines...)
		if _, err := r.locate(pair.account); err == nil {
			acctLines, err := r.resolveService(pair.account, "account", nil)
			if err != nil {
				return nil, err
			}
			resolved = append(resolved, acctLines...)
		}
		return resolved, nil
	}

	if lastErr != nil {
		return nil, fmt.Errorf("no usable PAM auth service found: %w", lastErr)
	}
	return nil, fmt.Errorf("no usable PAM auth service found")
}

func buildManagedLockscreenPamContent(baseDirs []string, readFile func(string) ([]byte, error)) (string, error) {
	resolver := lockscreenPamResolver{baseDirs: baseDirs, readFile: readFile}

	resolvedLines, err := resolver.resolveLines()
	if err != nil {
		return "", err
	}

	var b strings.Builder
	b.WriteString("#%PAM-1.0\n")
	b.WriteString(LockscreenPamManagedBlockStart + "\n")
	for _, line := range resolvedLines {
		b.WriteString(line)
		b.WriteByte('\n')
	}
	b.WriteString(LockscreenPamManagedBlockEnd + "\n")
	return b.String(), nil
}

var lockscreenPamCandidateServices = []string{
	"login",
	"system-auth",
	"system-login",
	"system-local-login",
	"common-auth",
	"base-auth",
}

type LockscreenPamServiceInfo struct {
	Name              string `json:"name"`
	Dir               string `json:"dir"`
	Path              string `json:"path"`
	HasAuth           bool   `json:"hasAuth"`
	InlineFingerprint bool   `json:"inlineFingerprint"`
	InlineU2f         bool   `json:"inlineU2f"`
}

type LockscreenPamValidation struct {
	Valid             bool     `json:"valid"`
	Path              string   `json:"path"`
	HasAuth           bool     `json:"hasAuth"`
	InlineFingerprint bool     `json:"inlineFingerprint"`
	InlineU2f         bool     `json:"inlineU2f"`
	MissingModules    []string `json:"missingModules"`
	Warnings          []string `json:"warnings"`
	Errors            []string `json:"errors"`
}

type lockscreenPamValidateDeps struct {
	baseDirs        []string
	readFile        func(string) ([]byte, error)
	stat            func(string) (os.FileInfo, error)
	pamModuleExists func(string) bool
}

func defaultValidateDeps() lockscreenPamValidateDeps {
	return lockscreenPamValidateDeps{
		baseDirs:        lockscreenPamBaseDirs,
		readFile:        os.ReadFile,
		stat:            os.Stat,
		pamModuleExists: pamModuleExists,
	}
}

// lockscreenPamAnalysis is a non-destructive walk of a PAM service. Unlike
// resolveService it detects (rather than strips) pam_fprintd/pam_u2f and
// records unknown directives instead of hard-failing on them.
type lockscreenPamAnalysis struct {
	lines             []string
	hasAuth           bool
	inlineFingerprint bool
	inlineU2f         bool
	modules           []string
	authModules       []string
	unknownDirectives []string
	err               error
}

func (r lockscreenPamResolver) analyzePath(path string) lockscreenPamAnalysis {
	var acc lockscreenPamAnalysis
	if err := r.analyzeInto(filepath.Clean(path), "", nil, &acc); err != nil {
		acc.err = err
	}
	return acc
}

func (r lockscreenPamResolver) analyzeInto(path string, filterType string, stack []string, acc *lockscreenPamAnalysis) error {
	if slices.Contains(stack, path) {
		chain := append(append([]string{}, stack...), path)
		display := make([]string, 0, len(chain))
		for _, item := range chain {
			display = append(display, filepath.Base(item))
		}
		return fmt.Errorf("cyclic PAM include detected: %s", strings.Join(display, " -> "))
	}

	data, err := r.readFile(path)
	if err != nil {
		return fmt.Errorf("failed to read PAM file %s: %w", path, err)
	}

	for rawLine := range strings.SplitSeq(strings.ReplaceAll(string(data), "\r\n", "\n"), "\n") {
		rawLine = strings.TrimRight(rawLine, "\r")
		trimmed := strings.TrimSpace(rawLine)
		if trimmed == "" || strings.HasPrefix(trimmed, "#") {
			continue
		}

		if include, ok := parseLockscreenPamIncludeDirective(trimmed, filterType); ok {
			lineType := pamDirectiveType(trimmed)
			if filterType != "" && lineType != "" && lineType != filterType {
				continue
			}
			nestedPath := include.target
			if filepath.IsAbs(nestedPath) {
				nestedPath = filepath.Clean(nestedPath)
			} else {
				located, err := r.locate(include.target)
				if err != nil {
					return fmt.Errorf("failed to read PAM file %s: %w", include.target, err)
				}
				nestedPath = located
			}
			if err := r.analyzeInto(nestedPath, include.filterType, append(stack, path), acc); err != nil {
				return err
			}
			continue
		}

		lineType := pamDirectiveType(trimmed)
		if lineType == "" {
			acc.unknownDirectives = append(acc.unknownDirectives, trimmed)
			continue
		}
		if filterType != "" && lineType != filterType {
			continue
		}

		acc.lines = append(acc.lines, rawLine)
		if lineType == "auth" {
			acc.hasAuth = true
		}

		foundModule := false
		for field := range strings.FieldsSeq(trimmed) {
			if strings.HasPrefix(field, "#") {
				break
			}
			if strings.Contains(field, "pam_fprintd") {
				acc.inlineFingerprint = true
			}
			if strings.Contains(field, "pam_u2f") {
				acc.inlineU2f = true
			}
			if !foundModule && strings.HasSuffix(field, ".so") {
				acc.modules = append(acc.modules, field)
				if lineType == "auth" {
					acc.authModules = append(acc.authModules, field)
				}
				foundModule = true
			}
		}
	}

	return nil
}

// Earlier base dir wins per name (libpam precedence).
func ListLockscreenPamServices() []LockscreenPamServiceInfo {
	return listLockscreenPamServices(lockscreenPamBaseDirs, os.ReadFile)
}

func listLockscreenPamServices(baseDirs []string, readFile func(string) ([]byte, error)) []LockscreenPamServiceInfo {
	resolver := lockscreenPamResolver{baseDirs: baseDirs, readFile: readFile}
	out := make([]LockscreenPamServiceInfo, 0, len(lockscreenPamCandidateServices))
	for _, name := range lockscreenPamCandidateServices {
		path, err := resolver.locate(name)
		if err != nil {
			continue
		}
		info := LockscreenPamServiceInfo{
			Name: name,
			Dir:  filepath.Dir(path),
			Path: path,
		}
		if analysis := resolver.analyzePath(path); analysis.err == nil {
			info.HasAuth = analysis.hasAuth
			info.InlineFingerprint = analysis.inlineFingerprint
			info.InlineU2f = analysis.inlineU2f
		}
		out = append(out, info)
	}
	return out
}

func ValidateLockscreenPamService(name string) LockscreenPamValidation {
	return validateLockscreenPam(name, "", defaultValidateDeps())
}

func ValidateLockscreenPamPath(path string) LockscreenPamValidation {
	return validateLockscreenPam("", path, defaultValidateDeps())
}

func ValidateLockscreenU2fPamService(name string) LockscreenPamValidation {
	return validateLockscreenU2fPam(name, "", defaultValidateDeps())
}

func ValidateLockscreenU2fPamPath(path string) LockscreenPamValidation {
	return validateLockscreenU2fPam("", path, defaultValidateDeps())
}

func validateLockscreenPam(serviceName string, path string, deps lockscreenPamValidateDeps) LockscreenPamValidation {
	result := LockscreenPamValidation{
		MissingModules: []string{},
		Warnings:       []string{},
		Errors:         []string{},
	}
	resolver := lockscreenPamResolver{baseDirs: deps.baseDirs, readFile: deps.readFile}

	var analysis lockscreenPamAnalysis
	if path != "" {
		result.Path = path
		analysis = resolver.analyzePath(path)
	} else {
		located, err := resolver.locate(serviceName)
		if err != nil {
			result.Errors = append(result.Errors, fmt.Sprintf("PAM service %q not found: %v", serviceName, err))
			return result
		}
		result.Path = located
		analysis = resolver.analyzePath(located)
	}

	if analysis.err != nil {
		result.Errors = append(result.Errors, analysis.err.Error())
		return result
	}

	result.HasAuth = analysis.hasAuth
	result.InlineFingerprint = analysis.inlineFingerprint
	result.InlineU2f = analysis.inlineU2f

	if !analysis.hasAuth {
		result.Errors = append(result.Errors, "no auth directives found after include resolution")
	}

	for _, directive := range analysis.unknownDirectives {
		result.Warnings = append(result.Warnings, "unsupported PAM directive (libpam may still handle it at runtime): "+directive)
	}

	seen := map[string]bool{}
	for _, ref := range analysis.modules {
		name := filepath.Base(ref)
		if seen[name] {
			continue
		}
		seen[name] = true
		if moduleReferenceExists(ref, deps) {
			continue
		}
		result.MissingModules = append(result.MissingModules, name)
		result.Warnings = append(result.Warnings, "referenced PAM module not found: "+name)
	}

	if analysis.inlineFingerprint {
		result.Warnings = append(result.Warnings, "pam_fprintd is present in the resolved stack; may double-prompt with DMS's separate fingerprint context")
	}
	if analysis.inlineU2f {
		result.Warnings = append(result.Warnings, "pam_u2f is present in the resolved stack; may double-prompt with DMS's separate U2F context")
	}

	result.Valid = len(result.Errors) == 0
	return result
}

func validateLockscreenU2fPam(serviceName string, path string, deps lockscreenPamValidateDeps) LockscreenPamValidation {
	result := validateLockscreenPam(serviceName, path, deps)
	if result.Path == "" {
		return result
	}

	resolver := lockscreenPamResolver{baseDirs: deps.baseDirs, readFile: deps.readFile}
	analysis := resolver.analyzePath(result.Path)
	if analysis.err != nil {
		return result
	}

	filteredWarnings := result.Warnings[:0]
	for _, warning := range result.Warnings {
		if strings.Contains(warning, "pam_u2f is present") && strings.Contains(warning, "double-prompt") {
			continue
		}
		filteredWarnings = append(filteredWarnings, warning)
	}
	result.Warnings = filteredWarnings

	hasU2fAuth := false
	unsafeModules := []string{}
	unsafeSeen := map[string]bool{}
	for _, ref := range analysis.authModules {
		name := filepath.Base(ref)
		if name == "pam_u2f.so" {
			hasU2fAuth = true
			continue
		}
		switch name {
		case "pam_env.so", "pam_faildelay.so", "pam_nologin.so":
			continue
		default:
			if !unsafeSeen[name] {
				unsafeSeen[name] = true
				unsafeModules = append(unsafeModules, name)
			}
		}
	}

	if !hasU2fAuth {
		result.Errors = append(result.Errors, "no pam_u2f auth directive found; select a dedicated security-key PAM service")
	}
	for _, name := range unsafeModules {
		result.Errors = append(result.Errors, fmt.Sprintf("additional auth module %s is not allowed in a dedicated security-key PAM service", name))
	}
	for _, name := range result.MissingModules {
		if strings.Contains(name, "pam_u2f") {
			result.Errors = append(result.Errors, fmt.Sprintf("%s is not installed or its configured path is unavailable", name))
			break
		}
	}

	result.Valid = len(result.Errors) == 0
	return result
}

func moduleReferenceExists(ref string, deps lockscreenPamValidateDeps) bool {
	if filepath.IsAbs(ref) {
		_, err := deps.stat(ref)
		return err == nil
	}
	return deps.pamModuleExists(ref)
}

const UserLockscreenPamService = "dankshell"

const UserLockscreenPamFallbackService = "other"

const userLockscreenPamFallbackContent = `#%PAM-1.0
auth     required    pam_deny.so
account  required    pam_deny.so
password required    pam_deny.so
session  required    pam_deny.so
`

func UserLockscreenPamDir() string {
	return filepath.Join(utils.XDGStateHome(), "dms", "pam")
}

// WriteUserLockscreenPamConfig resolves the distro's real auth stack into a
// self-contained lock-screen service under the user state dir, unprivileged
// (reads world-readable PAM dirs, writes the user's own state dir). Rewrites
// only on change to avoid inotify churn. Returns the written path.
func WriteUserLockscreenPamConfig(logFunc func(string)) (string, error) {
	return writeUserLockscreenPamConfig(logFunc, lockscreenPamBaseDirs, os.ReadFile)
}

func writeUserLockscreenPamConfig(logFunc func(string), baseDirs []string, readFile func(string) ([]byte, error)) (string, error) {
	content, err := buildManagedLockscreenPamContent(baseDirs, readFile)
	if err != nil {
		return "", fmt.Errorf("failed to resolve system PAM auth stack: %w", err)
	}

	dir := UserLockscreenPamDir()
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return "", fmt.Errorf("failed to create %s: %w", dir, err)
	}

	// pam_start_confdir warns "no default config other" and can stall without it.
	fallback := filepath.Join(dir, UserLockscreenPamFallbackService)
	if _, err := writePamFileIfChanged(fallback, userLockscreenPamFallbackContent); err != nil {
		return "", err
	}

	path := filepath.Join(dir, UserLockscreenPamService)
	changed, err := writePamFileIfChanged(path, content)
	if err != nil {
		return "", err
	}

	if changed && logFunc != nil {
		logFunc("✓ Wrote lock-screen PAM config " + path)
	}
	return path, nil
}

func writePamFileIfChanged(path, content string) (bool, error) {
	if existing, err := os.ReadFile(path); err == nil && string(existing) == content {
		return false, nil
	}
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		return false, fmt.Errorf("failed to write %s: %w", path, err)
	}
	return true, nil
}

func buildManagedLockscreenU2FPamContent() string {
	var b strings.Builder
	b.WriteString("#%PAM-1.0\n")
	b.WriteString(LockscreenU2FPamManagedBlockStart + "\n")
	b.WriteString("auth    required    pam_u2f.so  cue nouserok timeout=10\n")
	b.WriteString("account required    pam_permit.so\n")
	b.WriteString("password required   pam_deny.so\n")
	b.WriteString("session required    pam_permit.so\n")
	b.WriteString(LockscreenU2FPamManagedBlockEnd + "\n")
	return b.String()
}

func syncLockscreenPamConfigWithDeps(logFunc func(string), sudoPassword string, deps syncDeps) error {
	if deps.isNixOS() {
		logFunc("ℹ NixOS detected. DMS does not write /etc/pam.d/dankshell; the lock screen uses a sanitized password-only service in the user state directory unless you select a custom PAM source.")
		return nil
	}

	existingData, err := deps.readFile(deps.dankshellPath)
	if err == nil {
		if !hasManagedLockscreenPamFile(string(existingData)) {
			logFunc("ℹ Custom /etc/pam.d/dankshell found (no DMS block). Skipping.")
			return nil
		}
	} else if !os.IsNotExist(err) {
		return fmt.Errorf("failed to read %s: %w", deps.dankshellPath, err)
	}

	content, err := buildManagedLockscreenPamContent([]string{deps.pamDir}, deps.readFile)
	if err != nil {
		return fmt.Errorf("failed to build %s from %s: %w", deps.dankshellPath, filepath.Join(deps.pamDir, "login"), err)
	}

	if err := writeManagedPamFile(content, deps.dankshellPath, sudoPassword, deps); err != nil {
		return fmt.Errorf("failed to write %s: %w", deps.dankshellPath, err)
	}

	logFunc("✓ Created or updated /etc/pam.d/dankshell for lock screen authentication")
	return nil
}

func syncLockscreenU2FPamConfigWithDeps(logFunc func(string), sudoPassword string, enabled bool, deps syncDeps) error {
	if deps.isNixOS() {
		logFunc("ℹ NixOS detected. DMS does not manage /etc/pam.d/dankshell-u2f on NixOS. Keep using the bundled U2F helper or configure a custom PAM service yourself.")
		return nil
	}

	existingData, err := deps.readFile(deps.dankshellU2fPath)
	if err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("failed to read %s: %w", deps.dankshellU2fPath, err)
	}

	if enabled {
		if err == nil && !hasManagedLockscreenU2FPamFile(string(existingData)) {
			logFunc("ℹ Custom /etc/pam.d/dankshell-u2f found (no DMS block). Skipping.")
			return nil
		}
		if err := writeManagedPamFile(buildManagedLockscreenU2FPamContent(), deps.dankshellU2fPath, sudoPassword, deps); err != nil {
			return fmt.Errorf("failed to write %s: %w", deps.dankshellU2fPath, err)
		}
		logFunc("✓ Created or updated /etc/pam.d/dankshell-u2f for lock screen security-key authentication")
		return nil
	}

	if os.IsNotExist(err) {
		return nil
	}
	if err == nil && !hasManagedLockscreenU2FPamFile(string(existingData)) {
		logFunc("ℹ Custom /etc/pam.d/dankshell-u2f found (no DMS block). Leaving it untouched.")
		return nil
	}

	if err := deps.runSudoCmd(sudoPassword, "rm", "-f", deps.dankshellU2fPath); err != nil {
		return fmt.Errorf("failed to remove %s: %w", deps.dankshellU2fPath, err)
	}
	logFunc("✓ Removed DMS-managed /etc/pam.d/dankshell-u2f")
	return nil
}

func writeManagedPamFile(content string, destPath string, sudoPassword string, deps syncDeps) error {
	tmpFile, err := deps.createTemp("", "dms-pam-*.conf")
	if err != nil {
		return err
	}
	tmpPath := tmpFile.Name()
	defer func() {
		_ = deps.removeFile(tmpPath)
	}()

	if _, err := tmpFile.WriteString(content); err != nil {
		tmpFile.Close()
		return err
	}
	if err := tmpFile.Close(); err != nil {
		return err
	}
	if err := deps.runSudoCmd(sudoPassword, "cp", tmpPath, destPath); err != nil {
		return err
	}
	if err := deps.runSudoCmd(sudoPassword, "chmod", "644", destPath); err != nil {
		return fmt.Errorf("failed to set permissions on %s: %w", destPath, err)
	}
	return nil
}

func pamModuleExists(module string) bool {
	for _, libDir := range []string{
		"/usr/lib64/security",
		"/usr/lib/security",
		"/lib64/security",
		"/lib/security",
		"/lib/x86_64-linux-gnu/security",
		"/usr/lib/x86_64-linux-gnu/security",
		"/lib/aarch64-linux-gnu/security",
		"/usr/lib/aarch64-linux-gnu/security",
		"/run/current-system/sw/lib64/security",
		"/run/current-system/sw/lib/security",
		"/usr/local/lib/security",
		"/usr/local/lib",
		"/usr/lib",
	} {
		if _, err := os.Stat(filepath.Join(libDir, module)); err == nil {
			return true
		}
	}
	return false
}
