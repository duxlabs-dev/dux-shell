package main

import (
	"bytes"
	"debug/elf"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"slices"
	"strconv"
	"strings"

	"github.com/charmbracelet/lipgloss"
	"github.com/duxlabs-dev/dux-shell/core/internal/blur"
	"github.com/duxlabs-dev/dux-shell/core/internal/clipboard"
	"github.com/duxlabs-dev/dux-shell/core/internal/config"
	"github.com/duxlabs-dev/dux-shell/core/internal/distros"
	"github.com/duxlabs-dev/dux-shell/core/internal/mangoconf"
	"github.com/duxlabs-dev/dux-shell/core/internal/matugen"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/brightness"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/network"
	"github.com/duxlabs-dev/dux-shell/core/internal/site"
	"github.com/duxlabs-dev/dux-shell/core/internal/tui"
	"github.com/duxlabs-dev/dux-shell/core/internal/utils"
	"github.com/duxlabs-dev/dux-shell/core/internal/version"
	"github.com/godbus/dbus/v5"
	"github.com/spf13/cobra"
)

type status string

const (
	statusOK    status = "ok"
	statusWarn  status = "warn"
	statusError status = "error"
	statusInfo  status = "info"
)

func (s status) IconStyle(styles tui.Styles) (string, lipgloss.Style) {
	switch s {
	case statusOK:
		return "●", styles.Success
	case statusWarn:
		return "●", styles.Warning
	case statusError:
		return "●", styles.Error
	default:
		return "○", styles.Subtle
	}
}

type DoctorStatus struct {
	Errors   []checkResult
	Warnings []checkResult
	OK       []checkResult
	Info     []checkResult
}

func (ds *DoctorStatus) Add(r checkResult) {
	switch r.status {
	case statusError:
		ds.Errors = append(ds.Errors, r)
	case statusWarn:
		ds.Warnings = append(ds.Warnings, r)
	case statusOK:
		ds.OK = append(ds.OK, r)
	case statusInfo:
		ds.Info = append(ds.Info, r)
	}
}

func (ds *DoctorStatus) HasIssues() bool {
	return len(ds.Errors) > 0 || len(ds.Warnings) > 0
}

func (ds *DoctorStatus) ErrorCount() int {
	return len(ds.Errors)
}

func (ds *DoctorStatus) WarningCount() int {
	return len(ds.Warnings)
}

func (ds *DoctorStatus) OKCount() int {
	return len(ds.OK)
}

var (
	quickshellVersionRegex = regexp.MustCompile(`(?i)quickshell (\d+\.\d+\.\d+)`)
	niriVersionRegex       = regexp.MustCompile(`niri (\d+\.\d+)`)
	swayVersionRegex       = regexp.MustCompile(`sway version (\d+\.\d+)`)
	riverVersionRegex      = regexp.MustCompile(`river (\d+\.\d+)`)
	wayfireVersionRegex    = regexp.MustCompile(`wayfire (\d+\.\d+)`)
	labwcVersionRegex      = regexp.MustCompile(`labwc (\d+\.\d+\.\d+)`)
	mangowcVersionRegex    = regexp.MustCompile(`mango (\d+\.\d+\.\d+)`)
	miracleVersionRegex    = regexp.MustCompile(`miracle-wm v?(\d+\.\d+\.\d+)`)
	scrollVersionRegex     = regexp.MustCompile(`scroll version (\d+\.\d+)`)
	aqueousVersionRegex    = regexp.MustCompile(`(?i)aqueous v?(\d+\.\d+(?:\.\d+)?)`)
	umbrielVersionRegex    = regexp.MustCompile(`umbriel (\d+\.\d+\.\d+)`)
)

var doctorCmd = &cobra.Command{
	Use:   "doctor",
	Short: "Diagnose DMS installation and dependencies",
	Long:  "Check system health, verify dependencies, and diagnose configuration issues for DMS",
	Run:   runDoctor,
}

var (
	doctorVerbose bool
	doctorJSON    bool
	doctorCopy    bool
)

func init() {
	doctorCmd.Flags().BoolVarP(&doctorVerbose, "verbose", "v", false, "Show detailed output including paths and versions")
	doctorCmd.Flags().BoolVarP(&doctorJSON, "json", "j", false, "Output results in JSON format")
	doctorCmd.Flags().BoolVarP(&doctorCopy, "copy", "C", false, "Copy results to clipboard in GitHub-friendly format")
}

type category int

const (
	catSystem category = iota
	catVersions
	catInstallation
	catCompositor
	catQuickshellFeatures
	catOptionalFeatures
	catConfigFiles
	catServices
	catEnvironment
	catFonts
)

func (c category) String() string {
	switch c {
	case catSystem:
		return "System"
	case catVersions:
		return "Versions"
	case catInstallation:
		return "Installation"
	case catCompositor:
		return "Compositor"
	case catQuickshellFeatures:
		return "Quickshell Features"
	case catOptionalFeatures:
		return "Optional Features"
	case catConfigFiles:
		return "Config Files"
	case catServices:
		return "Services"
	case catEnvironment:
		return "Environment"
	case catFonts:
		return "Fonts"
	default:
		return "Unknown"
	}
}

const (
	checkNameMaxLength = 21
	doctorDocsURL      = site.Docs + "/dms/cli-doctor"
)

type checkResult struct {
	category category
	name     string
	status   status
	message  string
	details  string
	url      string
}

type checkResultJSON struct {
	Category string `json:"category"`
	Name     string `json:"name"`
	Status   string `json:"status"`
	Message  string `json:"message"`
	Details  string `json:"details,omitempty"`
	URL      string `json:"url,omitempty"`
}

type doctorOutputJSON struct {
	Summary struct {
		Errors   int `json:"errors"`
		Warnings int `json:"warnings"`
		OK       int `json:"ok"`
		Info     int `json:"info"`
	} `json:"summary"`
	Results []checkResultJSON `json:"results"`
}

func (r checkResult) toJSON() checkResultJSON {
	return checkResultJSON{
		Category: r.category.String(),
		Name:     r.name,
		Status:   string(r.status),
		Message:  r.message,
		Details:  r.details,
		URL:      r.url,
	}
}

func runDoctor(cmd *cobra.Command, args []string) {
	if !doctorJSON && !doctorCopy {
		printDoctorHeader()
	}

	qsFeatures, qsMissingFeatures := checkQuickshellFeatures()

	versions, qsVersion := checkVersions(qsMissingFeatures)
	results := slices.Concat(
		checkSystemInfo(),
		versions,
		checkDMSInstallation(),
		checkPackageRepos(),
		checkWindowManagers(qsVersion),
		qsFeatures,
		checkOptionalDependencies(),
		checkConfigurationFiles(),
		checkSystemdServices(),
		checkSettingsPortal(),
		checkEnvironmentVars(),
		checkFonts(),
	)

	switch {
	case doctorCopy:
		text := formatResultsPlain(results)
		if err := clipboard.CopyOpts([]byte(text), "text/plain;charset=utf-8", false, false); err != nil {
			fmt.Fprintf(os.Stderr, "Failed to copy to clipboard: %v\n", err)
			os.Exit(1)
		}
		fmt.Println("Doctor report copied to clipboard")
	case doctorJSON:
		printResultsJSON(results)
	default:
		printResults(results)
		printSummary(results, qsMissingFeatures)
	}
}

func printDoctorHeader() {
	theme := tui.TerminalTheme()
	styles := tui.NewStyles(theme)

	fmt.Println(getThemedASCII())
	fmt.Println(styles.Title.Render("System Health Check"))
	fmt.Println(styles.Subtle.Render("──────────────────────────────────────"))
	fmt.Println()
}

func checkSystemInfo() []checkResult {
	var results []checkResult

	osInfo, err := distros.GetOSInfo()
	if err != nil {
		status, message, details := statusWarn, fmt.Sprintf("Unknown (%v)", err), ""

		if strings.Contains(err.Error(), "Unsupported distribution") {
			osRelease := readOSRelease()
			switch {
			case osRelease["ID"] == "nixos":
				status = statusOK
				message = osRelease["PRETTY_NAME"]
				if message == "" {
					message = fmt.Sprintf("NixOS %s", osRelease["VERSION_ID"])
				}
				details = "Supported for runtime (install via NixOS module or Flake)"
			case osRelease["PRETTY_NAME"] != "":
				message = fmt.Sprintf("%s (not supported by dms setup)", osRelease["PRETTY_NAME"])
				details = "DMS may work but automatic installation is not available"
			}
		}

		results = append(results, checkResult{catSystem, "Operating System", status, message, details, doctorDocsURL + "#operating-system"})
	} else {
		status := statusOK
		message := osInfo.PrettyName
		if message == "" {
			message = fmt.Sprintf("%s %s", osInfo.Distribution.ID, osInfo.VersionID)
		}
		details := fmt.Sprintf("ID: %s, Version: %s, Arch: %s", osInfo.ID, osInfo.VersionID, osInfo.Architecture)
		switch {
		case osInfo.Immutable:
			details += "; image-based (" + osInfo.ImmutableReason + "), duxinstall deploys configuration only"
		case distros.IsUnsupportedDistro(osInfo.Distribution.ID, osInfo.VersionID):
			status = statusWarn
			message += " (version may not be fully supported)"
		}
		results = append(results, checkResult{catSystem, "Operating System", status, message, details, doctorDocsURL + "#operating-system"})
	}

	arch := runtime.GOARCH
	archStatus := statusOK
	if arch != "amd64" && arch != "arm64" {
		archStatus = statusError
	}
	results = append(results, checkResult{catSystem, "Architecture", archStatus, arch, "", doctorDocsURL + "#architecture"})

	waylandDisplay := os.Getenv("WAYLAND_DISPLAY")
	xdgSessionType := os.Getenv("XDG_SESSION_TYPE")

	switch {
	case waylandDisplay != "" || xdgSessionType == "wayland":
		results = append(results, checkResult{
			catSystem, "Display Server", statusOK, "Wayland",
			fmt.Sprintf("WAYLAND_DISPLAY=%s", waylandDisplay),
			doctorDocsURL + "#display-server",
		})
	case xdgSessionType == "x11":
		results = append(results, checkResult{catSystem, "Display Server", statusError, "X11 (DMS requires Wayland)", "", doctorDocsURL + "#display-server"})
	default:
		results = append(results, checkResult{
			catSystem, "Display Server", statusWarn, "Unknown (ensure you're running Wayland)",
			fmt.Sprintf("XDG_SESSION_TYPE=%s", xdgSessionType),
			doctorDocsURL + "#display-server",
		})
	}

	return results
}

func checkEnvironmentVars() []checkResult {
	var results []checkResult
	results = append(results, checkEnvVar("QT_QPA_PLATFORMTHEME")...)
	results = append(results, checkQtPlatformThemePlugin("QT_QPA_PLATFORMTHEME")...)
	switch {
	case os.Getenv("QT_QPA_PLATFORMTHEME_QT6") != "":
		results = append(results, checkEnvVar("QT_QPA_PLATFORMTHEME_QT6")...)
		if os.Getenv("QT_QPA_PLATFORMTHEME_QT6") != os.Getenv("QT_QPA_PLATFORMTHEME") {
			results = append(results, checkQtPlatformThemePlugin("QT_QPA_PLATFORMTHEME_QT6")...)
		}
	case os.Getenv("QT_QPA_PLATFORMTHEME") != "":
		if doctorVerbose {
			results = append(results, checkResult{catEnvironment, "QT_QPA_PLATFORMTHEME_QT6", statusInfo, "Not set, Qt6 uses QT_QPA_PLATFORMTHEME", "", doctorDocsURL + "#environment-variables"})
		}
	default:
		results = append(results, checkEnvVar("QT_QPA_PLATFORMTHEME_QT6")...)
	}
	if matugen.QtengineActive() {
		results = append(results, checkQtengineConfig()...)
	}
	results = append(results, checkEnvVar("QS_ICON_THEME")...)
	results = append(results, checkXDGMenuPrefix()...)
	return results
}

func checkEnvVar(name string) []checkResult {
	value := os.Getenv(name)
	if value != "" {
		return []checkResult{{catEnvironment, name, statusInfo, value, "", doctorDocsURL + "#environment-variables"}}
	}
	if doctorVerbose {
		return []checkResult{{catEnvironment, name, statusInfo, "Not set", "", doctorDocsURL + "#environment-variables"}}
	}
	return nil
}

func checkXDGMenuPrefix() []checkResult {
	menuPrefix := os.Getenv("XDG_MENU_PREFIX")
	if menuPrefix != "" {
		if checkXDGMenuFile(menuPrefix) {
			return []checkResult{{catEnvironment, "XDG_MENU_PREFIX", statusInfo, menuPrefix, "", doctorDocsURL + "#xdg-menu-prefix"}}
		}
		return []checkResult{{catEnvironment, "XDG_MENU_PREFIX", statusWarn, fmt.Sprintf("%s (menu file not found)", menuPrefix), fmt.Sprintf("Dolphin 'Open with…' dialog may be empty. Ensure %sapplications.menu exists in ~/.config/menus or /etc/xdg/menus.", menuPrefix), doctorDocsURL + "#xdg-menu-prefix"}}
	}
	if _, err := exec.LookPath("keditfiletype"); err == nil {
		return []checkResult{{catEnvironment, "XDG_MENU_PREFIX", statusWarn, "Not set", "Dolphin file associations and 'Open with…' dialog may be empty. Set XDG_MENU_PREFIX=plasma- in your compositor's environment block.", doctorDocsURL + "#xdg-menu-prefix"}}
	}
	if doctorVerbose {
		return []checkResult{{catEnvironment, "XDG_MENU_PREFIX", statusInfo, "Not set", "", doctorDocsURL + "#xdg-menu-prefix"}}
	}
	return nil
}

// qtQueryBinaries are the Qt build tools that can be asked where Qt looks for
// plugins, in probe order. A binary's name does not reliably say which Qt it
// belongs to — plain "qmake" is Qt5 on Arch and Qt6 elsewhere — so each one is
// asked for QT_VERSION and the major is taken from the answer.
var qtQueryBinaries = []struct{ bin, flag string }{
	{"qmake6", "-query"},
	{"qmake-qt6", "-query"},
	{"qtpaths6", "--query"},
	{"qtpaths-qt6", "--query"},
	{"qmake-qt5", "-query"},
	{"qtpaths-qt5", "--query"},
	{"qmake", "-query"},
	{"qtpaths", "--query"},
}

// checkQtengineConfig reports whether qtengine's config points Qt apps at the
// DMS color scheme, which DMS writes there when it generates a theme.
func checkQtengineConfig() []checkResult {
	url := doctorDocsURL + "#environment-variables"
	path := matugen.QtengineConfigPath()

	data, err := os.ReadFile(path)
	if os.IsNotExist(err) || (err == nil && len(bytes.TrimSpace(data)) == 0) {
		return []checkResult{{catEnvironment, "qtengine config", statusInfo, "Not found", "Qt apps use qtengine's default palette until DMS generates a theme.", url}}
	}
	var cfg struct {
		Theme struct {
			ColorScheme string `json:"colorScheme"`
		} `json:"theme"`
	}
	if err == nil {
		err = json.Unmarshal(data, &cfg)
	}
	if err != nil {
		return []checkResult{{catEnvironment, "qtengine config", statusWarn, "Unreadable", fmt.Sprintf("DMS won't overwrite %s while it can't parse it, so Qt apps stop following DMS colors. Fix or remove the file.", path), url}}
	}

	scheme := matugen.QtengineColorSchemePath()
	if cfg.Theme.ColorScheme == scheme {
		return []checkResult{{catEnvironment, "qtengine config", statusOK, "Uses DMS colors", path, url}}
	}
	current := "No color scheme is set"
	if cfg.Theme.ColorScheme != "" {
		current = "The color scheme is " + cfg.Theme.ColorScheme
	}
	return []checkResult{{
		catEnvironment, "qtengine config", statusInfo, "Not using DMS colors",
		fmt.Sprintf("%s. DMS sets %s when it generates a theme with the qtengine and KColorScheme templates enabled.", current, scheme),
		url,
	}}
}

// checkQtPlatformThemePlugin validates one of the QT_QPA_PLATFORMTHEME
// variables beyond mere presence: the value must name a platform theme whose
// plugin Qt can actually load. A wrong value fails silently at run time — Qt
// apps fall back to a built-in theme, icon lookups return nothing, and
// Quickshell tray menus draw a placeholder for every icon an app publishes.
func checkQtPlatformThemePlugin(varName string) []checkResult {
	value := os.Getenv(varName)
	// Unset is reported by checkEnvVar.
	if value == "" {
		return nil
	}

	url := doctorDocsURL + "#environment-variables"

	// qt6ct-kde is the AUR package name, not the theme value: with it set,
	// Qt finds no platform theme at all and every Qt app falls back silently.
	if value == "qt6ct-kde" {
		return []checkResult{{
			catEnvironment, value, statusWarn, "Package name, not a theme",
			fmt.Sprintf("qt6ct-kde is the AUR package name; the theme value Qt expects is qt6ct. Qt apps get no platform theme, so palettes stay unstyled and icon lookups fail. Set %s=qt6ct, then restart the shell.", varName),
			url,
		}}
	}

	roots := qtPluginRoots()
	var results []checkResult
	for _, major := range qtPlatformThemeMajors(varName, value, roots) {
		results = append(results, checkQtPlatformThemePluginFor(varName, value, major, roots[major]))
	}
	return results
}

// qtPlatformThemeMajors lists the Qt majors whose plugin a variable's value
// must provide. DMS themes Qt6 through these variables and qt5ct is the Qt5
// counterpart. qtengine ships both, and Qt5 reads only QT_QPA_PLATFORMTHEME, so
// its Qt5 plugin is checked there when a Qt5 build tool can be asked.
func qtPlatformThemeMajors(varName, value string, roots map[string]qtInstall) []string {
	switch {
	case value == "qt5ct":
		return []string{"5"}
	case value == "qtengine" && varName == "QT_QPA_PLATFORMTHEME" && roots["5"].plugins != "":
		return []string{"5", "6"}
	}
	return []string{"6"}
}

func checkQtPlatformThemePluginFor(varName, value, major string, qt qtInstall) checkResult {
	url := doctorDocsURL + "#environment-variables"
	files := qtPlatformThemePluginFiles(value, major)
	name := fmt.Sprintf("%s plugin (Qt%s)", value, major)

	// qmake/qtpaths ship in dev packages most users lack — never warn on a Qt
	// that could not be interrogated, and never claim it is fine either.
	if qt.plugins == "" {
		return checkResult{
			catEnvironment, name, statusInfo, "Cannot verify (no qmake/qtpaths)",
			"Install a Qt development package to let dms doctor check the plugin against the path Qt actually searches.",
			url,
		}
	}

	// Qt also searches QT_PLUGIN_PATH, so a plugin found there is loadable.
	plugin := qtPluginPath(append([]string{qt.plugins}, filepath.SplitList(os.Getenv("QT_PLUGIN_PATH"))...), files...)
	if plugin == "" {
		// plasma-integration ships the kde theme under a file name that has
		// changed across versions; a miss says nothing reliable about the
		// install, so degrade to info instead of warning at a working setup.
		if value == "kde" {
			return checkResult{
				catEnvironment, name, statusInfo, "Cannot verify (plasma-integration)",
				"The kde theme comes from plasma-integration, whose plugin file name varies across versions. Verify visually that Qt apps follow your theme.",
				url,
			}
		}
		expected := filepath.Join(qt.plugins, "platformthemes", files[0])
		return checkResult{
			catEnvironment, name, statusWarn, fmt.Sprintf("Not found in Qt%s plugin path", major),
			fmt.Sprintf("Expected %s — Qt apps silently fall back to a built-in theme, breaking icon lookups and palettes. Install the package providing it, or correct %s.", expected, varName),
			url,
		}
	}
	// Qt skips QPA plugins built against another Qt major.minor without a
	// warning, so an out-of-tree plugin silently stops loading after a Qt update.
	if built, ok := qtPluginBuildVersion(plugin); ok && built != qtMinorVersion(qt.version) {
		return checkResult{
			catEnvironment, name, statusWarn, fmt.Sprintf("Built for Qt %s, Qt is %s", built, qt.version),
			fmt.Sprintf("Qt ignores platform theme plugins built for another Qt minor version, so Qt apps silently fall back to a built-in theme, breaking icon lookups and palettes. Rebuild or reinstall the package providing %s against the installed Qt, then restart the shell.", plugin),
			url,
		}
	}
	return checkResult{catEnvironment, name, statusOK, "Installed", plugin, url}
}

// qtPluginBuildVersion reads the Qt major.minor a plugin was built against
// from the ELF note Qt 6 embeds in every plugin. Qt 5 plugins carry no such
// note and report false.
func qtPluginBuildVersion(path string) (string, bool) {
	f, err := elf.Open(path)
	if err != nil {
		return "", false
	}
	defer f.Close()
	section := f.Section(".note.qt.metadata")
	if section == nil {
		return "", false
	}
	data, err := section.Data()
	if err != nil || len(data) < 12 {
		return "", false
	}
	nameSize := f.ByteOrder.Uint32(data[0:4])
	descSize := f.ByteOrder.Uint32(data[4:8])
	if f.ByteOrder.Uint32(data[8:12]) != 0x74510001 || descSize < 3 {
		return "", false
	}
	// The descriptor starts with the metadata format version, then Qt's major and minor.
	desc := 12 + (uint64(nameSize)+3)&^3
	if uint64(len(data)) < desc+uint64(descSize) {
		return "", false
	}
	return fmt.Sprintf("%d.%d", data[desc+1], data[desc+2]), true
}

func qtMinorVersion(version string) string {
	parts := strings.SplitN(version, ".", 3)
	if len(parts) < 2 {
		return version
	}
	return parts[0] + "." + parts[1]
}

// qtPlatformThemePluginFiles lists the plugin file names that can provide a
// QT_QPA_PLATFORMTHEME value, most conventional first. Qt resolves the value
// through plugin metadata keys rather than file names, so these are the names
// each integration is known to ship; unmapped values fall back to Qt's
// libq<value> naming convention.
func qtPlatformThemePluginFiles(value, major string) []string {
	if value == "qtengine" {
		return []string{fmt.Sprintf("libqt%sengine-plugin.so", major)}
	}
	if files, ok := map[string][]string{
		"qt6ct": {"libqt6ct.so"},
		"qt5ct": {"libqt5ct.so"},
		"gtk3":  {"libqgtk3.so"},
		"kde":   {"libqkdeplatformtheme.so"},
	}[value]; ok {
		return files
	}
	return []string{"libq" + value + ".so", "lib" + value + ".so"}
}

type qtInstall struct {
	plugins string
	version string
}

// qtPluginRoots asks every available Qt build tool where its Qt looks for
// plugins, keyed by Qt major. A binary's name does not reliably say which Qt
// it belongs to — plain "qmake" is Qt5 on Arch and Qt6 elsewhere — so each one
// is asked for QT_VERSION and the major is taken from the answer.
func qtPluginRoots() map[string]qtInstall {
	pluginRoots := make(map[string]qtInstall)
	for _, q := range qtQueryBinaries {
		if _, err := exec.LookPath(q.bin); err != nil {
			continue
		}
		version := qtQuery(q.bin, q.flag, "QT_VERSION")
		major, _, _ := strings.Cut(version, ".")
		if major == "" || pluginRoots[major].plugins != "" {
			continue
		}
		if root := qtQuery(q.bin, q.flag, "QT_INSTALL_PLUGINS"); root != "" {
			pluginRoots[major] = qtInstall{plugins: root, version: version}
		}
	}
	return pluginRoots
}

// qtPluginPath returns the first of roots that holds any of files under
// platformthemes/, or "" if none does.
func qtPluginPath(roots []string, files ...string) string {
	for _, root := range roots {
		if root == "" {
			continue
		}
		for _, file := range files {
			path := filepath.Join(root, "platformthemes", file)
			if _, err := os.Stat(path); err == nil {
				return path
			}
		}
	}
	return ""
}

// qtQuery asks a Qt build tool for a single QLibraryInfo property.
func qtQuery(bin, flag, key string) string {
	output, err := exec.Command(bin, flag, key).Output()
	if err != nil {
		return ""
	}
	return qtQueryValue(string(output), key)
}

// qtQueryValue extracts one property from a Qt query. Most tools print the bare
// value, but some ignore the requested property and dump every one as
// "KEY:value" lines; taking the whole output there would yield a bogus path.
func qtQueryValue(output, key string) string {
	lines := strings.Split(strings.TrimSpace(output), "\n")
	for _, line := range lines {
		if value, found := strings.CutPrefix(strings.TrimSpace(line), key+":"); found {
			return strings.TrimSpace(value)
		}
	}
	if len(lines) == 1 {
		return strings.TrimSpace(lines[0])
	}
	return ""
}

// checkXDGMenuFile looks for the menu file where the XDG menu spec does: the
// user's config dir first, then each system config dir.
func checkXDGMenuFile(prefix string) bool {
	configDirs := os.Getenv("XDG_CONFIG_DIRS")
	if configDirs == "" {
		configDirs = "/etc/xdg"
	}
	dirs := append([]string{utils.XDGConfigHome()}, filepath.SplitList(configDirs)...)
	for _, dir := range dirs {
		if dir == "" {
			continue
		}
		if _, err := os.Stat(filepath.Join(dir, "menus", prefix+"applications.menu")); err == nil {
			return true
		}
	}
	return false
}

func readOSRelease() map[string]string {
	result := make(map[string]string)
	data, err := os.ReadFile("/etc/os-release")
	if err != nil {
		return result
	}
	for line := range strings.SplitSeq(string(data), "\n") {
		if parts := strings.SplitN(line, "=", 2); len(parts) == 2 {
			result[parts[0]] = strings.Trim(parts[1], "\"")
		}
	}
	return result
}

func checkVersions(qsMissingFeatures bool) (results []checkResult, qsSemver string) {
	dmsCliPath, _ := os.Executable()
	dmsCliDetails := ""
	if doctorVerbose {
		dmsCliDetails = dmsCliPath
	}

	results = []checkResult{
		{catVersions, "DMS CLI", statusOK, formatVersion(Version), dmsCliDetails, doctorDocsURL + "#dms-cli"},
	}

	qsVersion, qsStatus, qsPath, qsDetails, qsSemver := getQuickshellVersionInfo(qsMissingFeatures)
	if doctorVerbose && qsPath != "" && qsDetails == "" {
		qsDetails = qsPath
	}
	results = append(results, checkResult{catVersions, "Quickshell", qsStatus, qsVersion, qsDetails, doctorDocsURL + "#quickshell"})

	dmsVersion, dmsPath := getDMSShellVersion()
	if dmsVersion != "" {
		results = append(results, checkResult{catVersions, "DMS Shell", statusOK, dmsVersion, dmsPath, doctorDocsURL + "#dms-shell"})
	} else {
		results = append(results, checkResult{catVersions, "DMS Shell", statusError, "Not installed or not detected", "Run 'dms setup' to install", doctorDocsURL + "#dms-shell"})
	}

	return results, qsSemver
}

func getDMSShellVersion() (version, path string) {
	if err := shellApp.ResolveConfig(nil, nil); err == nil && shellApp.ConfigPath() != "" {
		versionFile := filepath.Join(shellApp.ConfigPath(), "VERSION")
		if data, err := os.ReadFile(versionFile); err == nil {
			return strings.TrimSpace(string(data)), shellApp.ConfigPath()
		}
		return "installed", shellApp.ConfigPath()
	}

	if dmsPath, err := config.LocateDMSConfig(); err == nil {
		versionFile := filepath.Join(dmsPath, "VERSION")
		if data, err := os.ReadFile(versionFile); err == nil {
			return strings.TrimSpace(string(data)), dmsPath
		}
		return "installed", dmsPath
	}

	return "", ""
}

func getQuickshellVersionInfo(missingFeatures bool) (display string, st status, path, details, semver string) {
	if !utils.CommandExists("qs") {
		return "Not installed", statusError, "", "", ""
	}

	qsPath, _ := exec.LookPath("qs")

	output, err := exec.Command("qs", "--version").Output()
	if err != nil {
		details := "Run 'qs --version' to inspect the failure."
		var exitErr *exec.ExitError
		if errors.As(err, &exitErr) {
			details = quickshellVersionFailureDetails(string(exitErr.Stderr))
		}
		return "Installed (version check failed)", statusWarn, qsPath, details, ""
	}

	fullVersion := strings.TrimSpace(string(output))
	if matches := quickshellVersionRegex.FindStringSubmatch(fullVersion); len(matches) >= 2 {
		if version.CompareVersions(matches[1], "0.2.0") < 0 {
			return fmt.Sprintf("%s (needs >= 0.2.0)", fullVersion), statusError, qsPath, "", matches[1]
		}
		if missingFeatures {
			return fullVersion, statusWarn, qsPath, "", matches[1]
		}
		return fullVersion, statusOK, qsPath, "", matches[1]
	}

	return fullVersion, statusWarn, qsPath, "", ""
}

func quickshellVersionFailureDetails(stderr string) string {
	if strings.Contains(stderr, "undefined symbol:") && strings.Contains(stderr, "Qt_6_PRIVATE_API") {
		return "Quickshell is incompatible with the installed Qt libraries. Rebuild or reinstall Quickshell against the current Qt version."
	}

	return "Run 'qs --version' to inspect the failure."
}

func checkDMSInstallation() []checkResult {
	var results []checkResult

	dmsPath := resolveDoctorShellPath()

	if dmsPath == "" {
		return []checkResult{{catInstallation, "DMS Configuration", statusError, "Not found", "shell.qml not found in any config path", doctorDocsURL + "#dms-configuration"}}
	}

	results = append(results, checkResult{catInstallation, "DMS Configuration", statusOK, "Found", dmsPath, doctorDocsURL + "#dms-configuration"})

	shellQml := filepath.Join(dmsPath, "shell.qml")
	if _, err := os.Stat(shellQml); err != nil {
		results = append(results, checkResult{catInstallation, "shell.qml", statusError, "Missing", shellQml, doctorDocsURL + "#dms-configuration"})
	} else {
		results = append(results, checkResult{catInstallation, "shell.qml", statusOK, "Present", shellQml, doctorDocsURL + "#dms-configuration"})
	}

	if doctorVerbose {
		installType := "Unknown"
		switch {
		case strings.Contains(dmsPath, "/nix/store"):
			installType = "Nix store"
		case strings.Contains(dmsPath, ".local/share") || strings.Contains(dmsPath, "/usr/share"):
			installType = "System package"
		case strings.Contains(dmsPath, ".config"):
			installType = "User config"
		}
		results = append(results, checkResult{catInstallation, "Install Type", statusInfo, installType, dmsPath, doctorDocsURL + "#dms-configuration"})
	}

	return results
}

func checkPackageRepos() []checkResult {
	osInfo, err := distros.GetOSInfo()
	if err != nil {
		return nil
	}
	distro, err := distros.NewDistribution(osInfo.Distribution.ID, nil)
	if err != nil {
		return nil
	}
	return packageReposResult(distro)
}

func packageReposResult(distro distros.Distribution) []checkResult {
	moves, ok := distros.PlanRepoMoves(distro)
	if !ok {
		return nil
	}
	url := doctorDocsURL + "#package-repos"
	legacy := distros.LegacyRepoPaths(moves)
	if len(legacy) > 0 {
		return []checkResult{{catInstallation, "Package Repos", statusWarn, "Legacy repositories, run: " + migrateDuxCommand, strings.Join(legacy, ", "), url}}
	}
	for _, move := range moves {
		if move.NewPresent {
			return []checkResult{{catInstallation, "Package Repos", statusOK, "Current", "", url}}
		}
	}
	return []checkResult{{catInstallation, "Package Repos", statusInfo, "No DMS package repositories", "", url}}
}

func checkWindowManagers(qsVersion string) []checkResult {
	compositors := []struct {
		name, versionCmd, versionArg string
		parseVersion                 func(string) string
		commands                     []string
	}{
		{"Hyprland", "Hyprland", "--version", distros.ParseHyprlandVersion, []string{"hyprland", "Hyprland"}},
		{"niri", "niri", "--version", firstSubmatch(niriVersionRegex), []string{"niri"}},
		{"Sway", "sway", "--version", firstSubmatch(swayVersionRegex), []string{"sway"}},
		{"River", "river", "-version", firstSubmatch(riverVersionRegex), []string{"river"}},
		{"Wayfire", "wayfire", "--version", firstSubmatch(wayfireVersionRegex), []string{"wayfire"}},
		{"labwc", "labwc", "--version", firstSubmatch(labwcVersionRegex), []string{"labwc"}},
		{"mangowc", "mango", "-v", firstSubmatch(mangowcVersionRegex), []string{"mango"}},
		{"Miracle WM", "miracle-wm", "--version", firstSubmatch(miracleVersionRegex), []string{"miracle-wm"}},
		{"Scroll", "scroll", "--version", firstSubmatch(scrollVersionRegex), []string{"scroll"}},
		{"Aqueous", "aqueous", "-version", firstSubmatch(aqueousVersionRegex), []string{"aqueous"}},
		{"Umbriel", "umbriel", "--version", firstSubmatch(umbrielVersionRegex), []string{"umbriel"}},
	}

	var results []checkResult
	foundAny := false

	for _, c := range compositors {
		if !slices.ContainsFunc(c.commands, utils.CommandExists) {
			continue
		}
		foundAny = true
		var compositorPath string
		for _, cmd := range c.commands {
			if path, err := exec.LookPath(cmd); err == nil {
				compositorPath = path
				break
			}
		}
		details := ""
		if doctorVerbose && compositorPath != "" {
			details = compositorPath
		}
		display, ver := getVersionFromCommand(c.versionCmd, c.versionArg, c.parseVersion)
		results = append(results, checkResult{
			catCompositor, c.name, statusOK, display, details,
			doctorDocsURL + "#compositor-checks",
		})
		if c.name == "Hyprland" && hyprlandLacksLua(ver) {
			results = append(results, checkResult{
				catCompositor, "Hyprland Lua config", statusWarn,
				fmt.Sprintf("Hyprland %s is older than 0.55", ver),
				"DMS writes Hyprland config in Lua only, which needs Hyprland 0.55 or newer",
				doctorDocsURL + "#compositor-checks",
			})
		}
		if c.name == "Hyprland" {
			results = append(results, checkHyprlandQuickshellFloor(ver, qsVersion)...)
			results = append(results, checkHyprlandDeprecatedConfig()...)
		}
		if c.name == "mangowc" && mangoLacksSnakeCase(ver) {
			results = append(results, checkResult{
				catCompositor, "Mango config format", statusError,
				fmt.Sprintf("Mango %s is older than 0.18", ver),
				"DMS writes Mango config with the snake_case keys of Mango 0.18 and later, which this release rejects; upgrade Mango",
				doctorDocsURL + "#compositor-checks",
			})
		}
	}

	if !foundAny {
		results = append(results, checkResult{
			catCompositor, "Compositor", statusError,
			"No supported Wayland compositor found",
			"Install Hyprland, niri, Sway, River, Wayfire, labwc, mangowc, miracle-wm, Scroll, Aqueous, or Umbriel",
			doctorDocsURL + "#compositor-checks",
		})
	}

	if wm := detectRunningWM(); wm != "" {
		results = append(results, checkResult{catCompositor, "Active", statusInfo, wm, "", doctorDocsURL + "#compositor"})
	}

	if os.Getenv("AQUEOUS_SOCKET") != "" {
		results = append(results, checkAqueousConfigHelper())
	}

	if os.Getenv("MANGO_INSTANCE_SIGNATURE") != "" {
		results = append(results, checkMangoConfig(mangoconf.Dir())...)
	}

	results = append(results, checkCompositorBlurSupport())

	return results
}

var (
	mangoLegacyOverviewBinds = regexp.MustCompile(`(?im)^\s*mousebind\s*=\s*none\s*,\s*(btn_left\s*,\s*toggleoverview\s*,\s*1|btn_right\s*,\s*killclient\s*,\s*0)\s*$`)
	mangoUnknownKeyword      = regexp.MustCompile(`Unknown keyword:\s*(\S+)`)
	ansiEscape               = regexp.MustCompile(`\x1b\[[0-9;]*m`)
)

// Mango's parser follows source= and always exits 0; only its output tells.
var mangoParseConfig = func(path string) (string, error) {
	if _, err := exec.LookPath("mango"); err != nil {
		return "", err
	}
	out, _ := exec.Command("mango", "-p", "-c", path).CombinedOutput()
	return string(out), nil
}

// Each "Unknown keyword" line is followed by a location line naming the file.
func mangoUnknownKeywords(output string) []string {
	var found []string
	seen := map[string]bool{}
	key := ""
	for line := range strings.SplitSeq(ansiEscape.ReplaceAllString(output, ""), "\n") {
		if m := mangoUnknownKeyword.FindStringSubmatch(line); m != nil {
			key = m[1]
			continue
		}
		slash := strings.LastIndex(line, "/")
		if key == "" || slash < 0 {
			continue
		}
		file, _, _ := strings.Cut(line[slash+1:], ":")
		entry := key + " (" + file + ")"
		if !seen[entry] {
			seen[entry] = true
			found = append(found, entry)
		}
		key = ""
	}
	return found
}

func checkMangoConfig(mangoDir string) []checkResult {
	url := doctorDocsURL + "#compositor-checks"
	mainPath := filepath.Join(mangoDir, "config.conf")
	var results []checkResult
	if output, err := mangoParseConfig(mainPath); err == nil {
		if unknown := mangoUnknownKeywords(output); len(unknown) > 0 {
			results = append(results, checkResult{catCompositor, "Mango config keys", statusError,
				"Unknown keys: " + strings.Join(unknown, ", "),
				"Mango 0.18 renamed its config keys to snake_case. Run migrate-config-keys.sh from Mango's 0.18.0 release over ~/.config/mango, or rename the keys by hand.", url})
		}
	}

	paths, _ := filepath.Glob(filepath.Join(mangoDir, "dms", "*.conf"))
	paths = append([]string{mainPath}, paths...)
	var overviewBinds []string
	for _, path := range paths {
		data, err := os.ReadFile(path)
		if err != nil {
			continue
		}
		if mangoLegacyOverviewBinds.Match(data) {
			overviewBinds = append(overviewBinds, filepath.Base(path))
		}
	}
	if len(overviewBinds) > 0 {
		results = append(results, checkResult{catCompositor, "Mango mouse binds", statusWarn,
			"Obsolete overview binds in " + strings.Join(overviewBinds, ", "),
			"mousebind=NONE,btn_left,toggleoverview,1 and mousebind=NONE,btn_right,killclient,0 swallow normal clicks; remove them.", url})
	}
	return results
}

func checkAqueousConfigHelper() checkResult {
	url := doctorDocsURL + "#compositor-checks"
	path, err := exec.LookPath("aqueous-config")
	if err != nil {
		return checkResult{catCompositor, "aqueous-config", statusWarn, "Not found", "Keybind and display settings edits from the shell need the aqueous-config helper", url}
	}
	details := "Keybind and display settings edits from the shell"
	if doctorVerbose {
		details = path
	}
	return checkResult{catCompositor, "aqueous-config", statusOK, "Installed", details, url}
}

func checkCompositorBlurSupport() checkResult {
	supported, err := blur.ProbeSupport()
	if err != nil {
		return checkResult{catCompositor, "Background Blur", statusInfo, "Unable to verify", err.Error(), doctorDocsURL + "#compositor-checks"}
	}

	if supported {
		return checkResult{catCompositor, "Background Blur", statusOK, "Supported", "Compositor supports ext-background-effect-v1", doctorDocsURL + "#compositor-checks"}
	}

	return checkResult{catCompositor, "Background Blur", statusWarn, "Unsupported", "Compositor does not support ext-background-effect-v1", doctorDocsURL + "#compositor-checks"}
}

func checkHyprlandQuickshellFloor(hyprVer, qsVer string) []checkResult {
	if !hyprlandReadsOnlyLua(hyprVer) || qsVer == "" || version.CompareVersions(qsVer, "0.3.2") >= 0 {
		return nil
	}
	return []checkResult{{
		catCompositor, "Quickshell for Hyprland 0.57", statusWarn,
		fmt.Sprintf("Quickshell %s is older than 0.3.2", qsVer),
		"Hyprland 0.57 sends workspace addresses that older Quickshell collapses to workspace 0, breaking named and special workspaces. Upgrade Quickshell.",
		doctorDocsURL + "#compositor-checks",
	}}
}

// Hyprland before 0.57 answers `unknown request`, which fails to parse and is skipped.
func checkHyprlandDeprecatedConfig() []checkResult {
	if os.Getenv("HYPRLAND_INSTANCE_SIGNATURE") == "" {
		return nil
	}
	out, err := exec.Command("hyprctl", "-j", "deprecated-config").Output()
	if err != nil {
		return nil
	}
	return hyprlandDeprecatedConfigResults(out)
}

func hyprlandDeprecatedConfigResults(out []byte) []checkResult {
	var notices []string
	if err := json.Unmarshal(out, &notices); err != nil || len(notices) == 0 {
		return nil
	}
	return []checkResult{{
		catCompositor, "Hyprland deprecated config", statusWarn,
		fmt.Sprintf("%d deprecated option(s)", len(notices)),
		strings.Join(notices, "; "),
		doctorDocsURL + "#compositor-checks",
	}}
}

func hyprlandLacksLua(ver string) bool {
	return ver != "" && version.CompareVersions(ver, "0.55.0") < 0
}

func hyprlandReadsOnlyLua(ver string) bool {
	return ver != "" && version.CompareVersions(ver, "0.57.0") >= 0
}

func mangoLacksSnakeCase(ver string) bool {
	return ver != "" && version.CompareVersions(ver, "0.18.0") < 0
}

func firstSubmatch(re *regexp.Regexp) func(string) string {
	return func(s string) string {
		if m := re.FindStringSubmatch(s); len(m) > 1 {
			return m[1]
		}
		return ""
	}
}

func getVersionFromCommand(cmd, arg string, parse func(string) string) (display, ver string) {
	output, err := exec.Command(cmd, arg).CombinedOutput()
	if err != nil && len(output) == 0 {
		return "installed", ""
	}

	outStr := string(output)
	ver = parse(outStr)
	if ver == "" {
		return strings.TrimSpace(outStr), ""
	}
	if strings.Contains(outStr, "git") || strings.Contains(outStr, "dirty") {
		return ver + " (git)", ver
	}
	return ver, ver
}

func detectRunningWM() string {
	switch {
	case os.Getenv("AQUEOUS_SOCKET") != "":
		return "Aqueous"
	case os.Getenv("HYPRLAND_INSTANCE_SIGNATURE") != "":
		return "Hyprland"
	case os.Getenv("NIRI_SOCKET") != "":
		return "niri"
	case os.Getenv("MANGO_INSTANCE_SIGNATURE") != "":
		return "MangoWC"
	case os.Getenv("MIRACLESOCK") != "":
		return "Miracle WM"
	case os.Getenv("UMBRIEL_SOCKET") != "":
		return "Umbriel"
	case os.Getenv("XDG_CURRENT_DESKTOP") != "":
		return os.Getenv("XDG_CURRENT_DESKTOP")
	}
	return ""
}

func checkQuickshellFeatures() ([]checkResult, bool) {
	if !utils.CommandExists("qs") {
		return nil, false
	}

	tmpDir := os.TempDir()
	testScript := filepath.Join(tmpDir, "qs-feature-test.qml")
	defer os.Remove(testScript)

	qmlContent := `
import QtQuick
import Quickshell
import Quickshell.Wayland

ShellRoot {
	id: root

	property bool polkitAvailable: false
	property bool idleMonitorAvailable: false
	property bool idleInhibitorAvailable: false
	property bool shortcutInhibitorAvailable: false
	property bool backgroundBlurAvailable: false

	Timer {
		interval: 50
		running: true
		repeat: false
		onTriggered: {
			try {
				var polkitTest = Qt.createQmlObject(
					'import Quickshell.Services.Polkit; import QtQuick; Item {}',
					root
				)
				root.polkitAvailable = true
				polkitTest.destroy()
			} catch (e) {}

			try {
				var testItem = Qt.createQmlObject(
					'import Quickshell; import Quickshell.Wayland; import QtQuick; QtObject { ' +
					'readonly property bool hasIdleMonitor: typeof IdleMonitor !== "undefined"; ' +
					'readonly property bool hasIdleInhibitor: typeof IdleInhibitor !== "undefined"; ' +
					'readonly property bool hasShortcutInhibitor: typeof ShortcutInhibitor !== "undefined"; ' +
					'readonly property bool hasBackgroundBlur: typeof BackgroundEffect !== "undefined" ' +
					'}',
					root
				)
				root.idleMonitorAvailable = testItem.hasIdleMonitor
				root.idleInhibitorAvailable = testItem.hasIdleInhibitor
				root.shortcutInhibitorAvailable = testItem.hasShortcutInhibitor
				root.backgroundBlurAvailable = testItem.hasBackgroundBlur
				testItem.destroy()
			} catch (e) {}

			console.warn(root.polkitAvailable ? "FEATURE:Polkit:OK" : "FEATURE:Polkit:UNAVAILABLE")
			console.warn(root.idleMonitorAvailable ? "FEATURE:IdleMonitor:OK" : "FEATURE:IdleMonitor:UNAVAILABLE")
			console.warn(root.idleInhibitorAvailable ? "FEATURE:IdleInhibitor:OK" : "FEATURE:IdleInhibitor:UNAVAILABLE")
			console.warn(root.shortcutInhibitorAvailable ? "FEATURE:ShortcutInhibitor:OK" : "FEATURE:ShortcutInhibitor:UNAVAILABLE")

			console.warn(root.backgroundBlurAvailable ? "FEATURE:BackgroundBlur:OK" : "FEATURE:BackgroundBlur:UNAVAILABLE")

			Quickshell.execDetached(["kill", "-TERM", String(Quickshell.processId)])
		}
	}
}
`

	if err := os.WriteFile(testScript, []byte(qmlContent), 0o644); err != nil {
		return nil, false
	}

	cmd := exec.Command("qs", "-p", testScript)
	cmd.Env = append(os.Environ(), "NO_COLOR=1")
	output, _ := cmd.CombinedOutput()
	outputStr := string(output)

	features := []struct{ name, desc string }{
		{"Polkit", "Authentication prompts"},
		{"IdleMonitor", "Idle detection"},
		{"IdleInhibitor", "Prevent idle/sleep"},
		{"ShortcutInhibitor", "Allow shortcut management (niri, Aqueous)"},
		{"BackgroundBlur", "Background blur API support in Quickshell"},
	}

	var results []checkResult
	missingFeatures := false

	for _, f := range features {
		available := strings.Contains(outputStr, fmt.Sprintf("FEATURE:%s:OK", f.name))
		status, message := statusOK, "Available"
		if !available {
			status, message = statusInfo, "Not available"
			missingFeatures = true
		}
		results = append(results, checkResult{catQuickshellFeatures, f.name, status, message, f.desc, doctorDocsURL + "#quickshell-features"})
	}

	return results, missingFeatures
}

func checkI2CAvailability() checkResult {
	ddc, err := brightness.NewDDCBackend()
	if err != nil {
		return checkResult{catOptionalFeatures, "I2C/DDC", statusInfo, "Not available", "External monitor brightness control", doctorDocsURL + "#optional-features"}
	}
	defer ddc.Close()

	devices, err := ddc.GetDevices()
	if err != nil || len(devices) == 0 {
		return checkResult{catOptionalFeatures, "I2C/DDC", statusInfo, "No monitors detected", "External monitor brightness control", doctorDocsURL + "#optional-features"}
	}

	return checkResult{catOptionalFeatures, "I2C/DDC", statusOK, fmt.Sprintf("%d monitor(s) detected", len(devices)), "External monitor brightness control", doctorDocsURL + "#optional-features"}
}

func checkImageFormatPlugins() []checkResult {
	url := doctorDocsURL + "#optional-features"

	pluginDirs := findQtPluginDirs()
	if len(pluginDirs) == 0 {
		return []checkResult{
			{catOptionalFeatures, "qt6-imageformats", statusInfo, "Cannot detect (plugin dir not found)", "WebP, TIFF, JP2 support", url},
			{catOptionalFeatures, "kimageformats", statusInfo, "Cannot detect (plugin dir not found)", "AVIF, HEIF, JXL support", url},
		}
	}

	type pluginCheck struct {
		name    string
		desc    string
		plugins []struct{ file, format string }
	}

	checks := []pluginCheck{
		{
			name: "qt6-imageformats",
			desc: "WebP, TIFF, GIF, JP2 support",
			plugins: []struct{ file, format string }{
				{"libqwebp.so", "WebP"},
				{"libqtiff.so", "TIFF"},
				{"libqgif.so", "GIF"},
				{"libqjp2.so", "JP2"},
				{"libqicns.so", "ICNS"},
			},
		},
		{
			name: "kimageformats",
			desc: "AVIF, HEIF, JXL support",
			plugins: []struct{ file, format string }{
				{"kimg_avif.so", "AVIF"},
				{"kimg_heif.so", "HEIF"},
				{"kimg_jxl.so", "JXL"},
				{"kimg_exr.so", "EXR"},
			},
		},
	}

	var results []checkResult
	for _, c := range checks {
		var found []string
		var foundDirs []string
		for _, pluginDir := range pluginDirs {
			imageFormatsDir := filepath.Join(pluginDir, "imageformats")
			for _, p := range c.plugins {
				if _, err := os.Stat(filepath.Join(imageFormatsDir, p.file)); err == nil {
					if !slices.Contains(found, p.format) {
						found = append(found, p.format)
					}
					if !slices.Contains(foundDirs, imageFormatsDir) {
						foundDirs = append(foundDirs, imageFormatsDir)
					}
				}
			}
		}

		var result checkResult
		switch {
		case len(found) == 0:
			result = checkResult{catOptionalFeatures, c.name, statusWarn, "Not installed", c.desc, url}
		default:
			details := ""
			if doctorVerbose {
				details = fmt.Sprintf("Formats: %s (%s)", strings.Join(found, ", "), strings.Join(foundDirs, ":"))
			}
			result = checkResult{catOptionalFeatures, c.name, statusOK, fmt.Sprintf("Installed (%d formats)", len(found)), details, url}
		}
		results = append(results, result)
	}

	return results
}

func findQtPluginDirs() []string {
	var dirs []string

	addDir := func(dir string) {
		if dir != "" {
			if _, err := os.Stat(filepath.Join(dir, "imageformats")); err == nil {
				dirs = append(dirs, dir)
			}
		}
	}

	// Check all paths in QT_PLUGIN_PATH env var (used by NixOS and custom setups)
	for _, dir := range filepath.SplitList(os.Getenv("QT_PLUGIN_PATH")) {
		addDir(dir)
	}

	for _, q := range qtQueryBinaries {
		if _, err := exec.LookPath(q.bin); err != nil {
			continue
		}
		addDir(qtQuery(q.bin, q.flag, "QT_INSTALL_PLUGINS"))
	}

	// Fallback: common distro paths
	for _, dir := range []string{
		"/usr/lib/qt6/plugins",
		"/usr/lib64/qt6/plugins",
		"/usr/lib/x86_64-linux-gnu/qt6/plugins",
		"/usr/lib/aarch64-linux-gnu/qt6/plugins",
	} {
		addDir(dir)
	}

	return dirs
}

func detectNetworkBackend(stackResult *network.DetectResult) string {
	switch stackResult.Backend {
	case network.BackendNetworkManager:
		return "NetworkManager"
	case network.BackendIwd:
		return "iwd"
	case network.BackendNetworkd:
		if stackResult.HasIwd {
			return "iwd + systemd-networkd"
		}
		return "systemd-networkd"
	case network.BackendConnMan:
		return "ConnMan"
	case network.BackendWpaSupplicant:
		return "wpa_supplicant"
	default:
		return ""
	}
}

func getOptionalDBusStatus(busName string) (status, string) {
	if utils.IsDBusServiceAvailable(busName) {
		return statusOK, "Available"
	} else {
		return statusWarn, "Not available"
	}
}

func checkOptionalDependencies() []checkResult {
	var results []checkResult

	optionalFeaturesURL := doctorDocsURL + "#optional-features"

	accountsStatus, accountsMsg := getOptionalDBusStatus("org.freedesktop.Accounts")
	results = append(results, checkResult{catOptionalFeatures, "accountsservice", accountsStatus, accountsMsg, "User accounts", optionalFeaturesURL})

	ppdStatus, ppdMsg := getOptionalDBusStatus("org.freedesktop.UPower.PowerProfiles")
	results = append(results, checkResult{catOptionalFeatures, "power-profiles-daemon", ppdStatus, ppdMsg, "Power profile management", optionalFeaturesURL})

	logindStatus, logindMsg := getOptionalDBusStatus("org.freedesktop.login1")
	results = append(results, checkResult{catOptionalFeatures, "logind", logindStatus, logindMsg, "Session management", optionalFeaturesURL})

	cupsPkHelperBus := "org.opensuse.CupsPkHelper.Mechanism"
	var cupsPkStatus status
	var cupsPkMsg string
	switch {
	case utils.IsDBusServiceAvailable(cupsPkHelperBus):
		cupsPkStatus, cupsPkMsg = statusOK, "Running"
	case utils.IsDBusServiceActivatable(cupsPkHelperBus):
		cupsPkStatus, cupsPkMsg = statusOK, "Available"
	default:
		cupsPkStatus, cupsPkMsg = statusWarn, "Not available (install cups-pk-helper)"
	}
	results = append(results, checkResult{catOptionalFeatures, "cups-pk-helper", cupsPkStatus, cupsPkMsg, "Printer management", optionalFeaturesURL})

	results = append(results, checkI2CAvailability())
	results = append(results, checkImageFormatPlugins()...)

	terminals := []string{"ghostty", "kitty", "alacritty", "foot", "wezterm"}
	terminals = slices.DeleteFunc(terminals, func(t string) bool {
		return !utils.CommandExists(t)
	})

	if len(terminals) > 0 {
		results = append(results, checkResult{catOptionalFeatures, "Terminal", statusOK, strings.Join(terminals, ", "), "", optionalFeaturesURL})
	} else {
		results = append(results, checkResult{catOptionalFeatures, "Terminal", statusWarn, "None found", "Install ghostty, kitty, foot or alacritty", optionalFeaturesURL})
	}

	networkResult, err := network.DetectNetworkStack()
	networkStatus, networkMessage, networkDetails := statusOK, "Not available", "Network management"

	if err == nil && networkResult.Backend != network.BackendNone {
		networkMessage = detectNetworkBackend(networkResult)
		if doctorVerbose {
			networkDetails = networkResult.ChosenReason
		}
	} else {
		networkStatus = statusInfo
	}

	results = append(results, checkResult{catOptionalFeatures, "Network", networkStatus, networkMessage, networkDetails, optionalFeaturesURL})

	deps := []struct {
		name, cmd, desc string
		important       bool
	}{
		{"matugen", "matugen", "Dynamic theming", true},
		{"cava", "cava", "Audio visualizer", true},
		{"khal", "khal", "Calendar events", false},
		{"danksearch", "dsearch", "File search", false},
		{"dankcalendar", "dcal", "Calendar app", false},
		{"fprintd", "fprintd-list", "Fingerprint auth", false},
	}

	for _, d := range deps {
		found := utils.CommandExists(d.cmd)

		switch {
		case found:
			results = append(results, checkResult{catOptionalFeatures, d.name, statusOK, "Installed", d.desc, optionalFeaturesURL})
		case d.important:
			results = append(results, checkResult{catOptionalFeatures, d.name, statusWarn, "Missing", d.desc, optionalFeaturesURL})
		default:
			results = append(results, checkResult{catOptionalFeatures, d.name, statusInfo, "Not installed", d.desc, optionalFeaturesURL})
		}
	}

	results = append(results, checkAdwGtk3())

	return results
}

// Mirrors the search in quickshell/scripts/gtk.sh: user theme dirs, then XDG_DATA_DIRS.
func checkAdwGtk3() checkResult {
	optionalFeaturesURL := doctorDocsURL + "#optional-features"
	home, _ := os.UserHomeDir()
	dataHome := os.Getenv("XDG_DATA_HOME")
	if dataHome == "" {
		dataHome = filepath.Join(home, ".local", "share")
	}
	userRoots := []string{filepath.Join(dataHome, "themes"), filepath.Join(home, ".themes")}

	dataDirs := os.Getenv("XDG_DATA_DIRS")
	if dataDirs == "" {
		dataDirs = "/usr/local/share:/usr/share"
	}
	var systemRoots []string
	for _, d := range strings.Split(dataDirs, ":") {
		if d != "" {
			systemRoots = append(systemRoots, filepath.Join(d, "themes"))
		}
	}

	locate := func(roots []string, variant string) bool {
		for _, root := range roots {
			if info, err := os.Stat(filepath.Join(root, "adw-gtk3"+variant, "gtk-3.0")); err == nil && info.IsDir() {
				return true
			}
		}
		return false
	}

	userLight := locate(userRoots, "")
	userDark := locate(userRoots, "-dark")
	sysLight := locate(systemRoots, "")
	sysDark := locate(systemRoots, "-dark")

	switch {
	case userLight && userDark:
		return checkResult{catOptionalFeatures, "adw-gtk3", statusOK, "Installed", "GTK3 dynamic theming (user copy)", optionalFeaturesURL}
	case sysLight && sysDark:
		return checkResult{catOptionalFeatures, "adw-gtk3", statusOK, "Installed", "GTK3 dynamic theming (system copy, applied on next theme apply)", optionalFeaturesURL}
	case userLight || userDark || sysLight || sysDark:
		missing := "adw-gtk3-dark"
		if userDark || sysDark {
			missing = "adw-gtk3"
		}
		return checkResult{catOptionalFeatures, "adw-gtk3", statusWarn, "Missing " + missing, "GTK3 dynamic theming needs both variants", optionalFeaturesURL}
	default:
		return checkResult{catOptionalFeatures, "adw-gtk3", statusInfo, "Not installed", "GTK3 dynamic theming; without it the global CSS override applies", optionalFeaturesURL}
	}
}

func checkConfigurationFiles() []checkResult {
	configDir, _ := os.UserConfigDir()
	cacheDir, _ := os.UserCacheDir()
	dmsDir := "dms"

	configFiles := []struct{ name, path string }{
		{"settings.json", filepath.Join(configDir, dmsDir, "settings.json")},
		{"clsettings.json", filepath.Join(configDir, dmsDir, "clsettings.json")},
		{"plugin_settings.json", filepath.Join(configDir, dmsDir, "plugin_settings.json")},
		{"session.json", filepath.Join(utils.XDGStateHome(), dmsDir, "session.json")},
		{"dms-colors.json", filepath.Join(cacheDir, dmsDir, "dms-colors.json")},
	}

	var results []checkResult
	for _, cf := range configFiles {
		info, err := os.Stat(cf.path)
		if err != nil {
			results = append(results, checkResult{catConfigFiles, cf.name, statusInfo, "Not yet created", cf.path, doctorDocsURL + "#config-files"})
			continue
		}

		status := statusOK
		message := "Present"
		if info.Mode().Perm()&0o200 == 0 {
			status = statusWarn
			message += " (read-only)"
		}
		// The shell falls back to defaults on a parse failure, so a broken file must not report ok.
		if data, readErr := os.ReadFile(cf.path); readErr == nil && len(data) > 0 && !json.Valid(data) {
			status = statusError
			message = "Invalid JSON - the shell ignores this file and runs on defaults"
		}
		results = append(results, checkResult{catConfigFiles, cf.name, status, message, cf.path, doctorDocsURL + "#config-files"})
	}
	return results
}

func checkSystemdServices() []checkResult {
	if !utils.CommandExists("systemctl") {
		return nil
	}

	var results []checkResult

	dmsState := getServiceState("dms", true)
	wanted := config.SessionWanted()
	if !dmsState.exists {
		results = append(results, checkResult{catServices, "dms.service", statusInfo, "Not installed", "Optional user service", doctorDocsURL + "#services"})
	} else {
		status, message := statusOK, dmsState.enabled
		if dmsState.active != "" {
			message = fmt.Sprintf("%s, %s", dmsState.enabled, dmsState.active)
		}
		switch {
		case dmsState.active == "failed":
			status = statusError
		case dmsState.active == "active":
		case dmsState.enabled == "disabled" && len(wanted) > 0:
			message = "Started with " + strings.Join(wanted, ", ")
			if dmsState.active != "" {
				message += ", " + dmsState.active
			}
		case dmsState.enabled == "disabled" && os.Getenv("MANGO_INSTANCE_SIGNATURE") != "":
			status, message = statusInfo, "Disabled (Mango starts DMS from its config)"
		case dmsState.enabled == "disabled":
			status, message = statusWarn, "Disabled"
		case dmsState.active == "inactive":
			status = statusError
		}
		details := ""
		if len(wanted) > 0 {
			details = "Wanted by " + strings.Join(wanted, ", ")
		}
		if wm, ok := config.RunningCompositor(); ok && status != statusOK {
			if unit := config.SessionUnitName(wm); !slices.Contains(wanted, unit) {
				details = fmt.Sprintf("Nothing starts dms.service with %s. Run 'dms systemd enable'.", unit)
			}
		}
		results = append(results, checkResult{catServices, "dms.service", status, message, details, doctorDocsURL + "#services"})
	}

	if dmsState.exists && dmsState.enabled == "enabled" {
		gsState := getServiceState("graphical-session.target", true)
		if gsState.exists && gsState.active != "active" {
			results = append(results, checkResult{catServices, "graphical-session.target", statusWarn, "Inactive", "Compositor session never activated it, so dms.service cannot autostart. On Hyprland, hyprland-session.target must exist and be started by the compositor.", doctorDocsURL + "#services"})
		}
	}

	greetdState := getServiceState("greetd", false)
	switch {
	case greetdState.exists:
		status := statusOK
		if greetdState.enabled == "disabled" {
			status = statusInfo
		}
		results = append(results, checkResult{catServices, "greetd", status, greetdState.enabled, "", doctorDocsURL + "#services"})
		results = append(results, checkGreetdSession("/etc/greetd/config.toml")...)
		results = append(results, checkRetiredGreeterPackages()...)
	case doctorVerbose:
		results = append(results, checkResult{catServices, "greetd", statusInfo, "Not installed", "Optional greeter service", doctorDocsURL + "#services"})
	}

	return results
}

func greeterLuaHint() string {
	return "Hyprland 0.57 only reads Lua; switch to the dux-greeter package and rerun `dms-greeter install`. " + greeterPackageInstallHint()
}

func checkGreetdSession(configPath string) []checkResult {
	data, err := os.ReadFile(configPath)
	if err != nil {
		return nil
	}
	fields := strings.Fields(greetdDefaultSessionCommand(string(data)))
	if len(fields) == 0 {
		return nil
	}
	warn := func(message string) []checkResult {
		return []checkResult{{catServices, "Greeter session", statusWarn, message, greeterLuaHint(), doctorDocsURL + "#services"}}
	}
	if bin, err := exec.LookPath(fields[0]); err == nil && isLegacyWrapperScript(bin) {
		return warn("greetd runs a pre-1.6 greeter wrapper script")
	}
	if !strings.EqualFold(greeterFlagValue(fields, "--command"), "hyprland") {
		return nil
	}
	cfg := strings.Trim(greeterFlagValue(fields, "-C", "--config"), `"'`)
	if cfg == "" || strings.HasSuffix(cfg, ".lua") {
		return nil
	}
	content, err := os.ReadFile(cfg)
	if err != nil || greeterHyprlandLuaContent(content) {
		return nil
	}
	return warn("Greeter Hyprland config is not Lua: " + cfg)
}

var greeterHyprlandLuaPattern = regexp.MustCompile(`(^|[^[:alnum:]_])hl\.`)

// Mirrors dux-greeter's launcher.IsHyprlandLuaConfig content check.
func greeterHyprlandLuaContent(content []byte) bool {
	for line := range strings.Lines(string(content)) {
		if strings.HasPrefix(strings.TrimSpace(line), "#") {
			continue
		}
		if greeterHyprlandLuaPattern.MatchString(line) {
			return true
		}
	}
	return false
}

func greetdDefaultSessionCommand(configTOML string) string {
	inDefault := false
	for line := range strings.SplitSeq(configTOML, "\n") {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "[") {
			inDefault = line == "[default_session]"
			continue
		}
		key, value, ok := strings.Cut(line, "=")
		if !inDefault || !ok || strings.TrimSpace(key) != "command" {
			continue
		}
		value = strings.TrimSpace(value)
		if unquoted, err := strconv.Unquote(value); err == nil {
			return unquoted
		}
		return strings.Trim(value, `'`)
	}
	return ""
}

func greeterFlagValue(fields []string, flags ...string) string {
	for i, f := range fields {
		for _, flag := range flags {
			if f == flag && i+1 < len(fields) {
				return fields[i+1]
			}
			if value, ok := strings.CutPrefix(f, flag+"="); ok {
				return value
			}
		}
	}
	return ""
}

var retiredGreeterPackages = []string{"greetd-dms-greeter", "greetd-dms-greeter-bin", "greetd-dms-greeter-git"}

func checkRetiredGreeterPackages() []checkResult {
	if !utils.CommandExists("pacman") {
		return nil
	}
	// pacman -Q exits non-zero when any name is missing but still lists the installed ones
	out, _ := exec.Command("pacman", append([]string{"-Q"}, retiredGreeterPackages...)...).Output()
	installed := retiredGreeterPackagesInstalled(string(out))
	if len(installed) == 0 {
		return nil
	}
	return []checkResult{{
		catServices, "Greeter package", statusWarn,
		"Retired package installed: " + strings.Join(installed, ", "),
		greeterLuaHint(),
		doctorDocsURL + "#services",
	}}
}

// pacman -Q answers a missing name with any installed package that provides it,
// so the dux-greeter successors come back under the retired names they provide.
func retiredGreeterPackagesInstalled(pacmanQuery string) []string {
	var installed []string
	for line := range strings.SplitSeq(strings.TrimSpace(pacmanQuery), "\n") {
		name, _, _ := strings.Cut(line, " ")
		if slices.Contains(retiredGreeterPackages, name) {
			installed = append(installed, name)
		}
	}
	return installed
}

// Chromium, Electron and libadwaita follow light/dark through the settings
// portal; without it they fall back to GTK theme colours that never update.
func checkSettingsPortal() []checkResult {
	conn, err := dbus.SessionBus()
	if err != nil {
		return nil
	}
	var value dbus.Variant
	err = conn.Object("org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop").
		Call("org.freedesktop.portal.Settings.ReadOne", 0, "org.freedesktop.appearance", "color-scheme").
		Store(&value)
	if err == nil {
		return []checkResult{{catServices, "xdg-desktop-portal", statusOK, "Settings portal reachable", "", doctorDocsURL + "#services"}}
	}
	hint := "Apps cannot follow light/dark mode. The portal is D-Bus activated and needs graphical-session.target; without systemd, or a compositor that never starts that target (Mango before 0.17.1), exec the portal backend and xdg-desktop-portal at session start."
	return []checkResult{{catServices, "xdg-desktop-portal", statusWarn, "Settings portal unreachable", hint, doctorDocsURL + "#services"}}
}

type serviceState struct {
	exists  bool
	enabled string
	active  string
}

func getServiceState(name string, userService bool) serviceState {
	args := []string{"is-enabled", name}
	if userService {
		args = []string{"--user", "is-enabled", name}
	}

	output, _ := exec.Command("systemctl", args...).Output()
	enabled := strings.TrimSpace(string(output))

	if enabled == "" || enabled == "not-found" {
		return serviceState{}
	}

	state := serviceState{exists: true, enabled: enabled}

	if userService {
		output, _ = exec.Command("systemctl", "--user", "is-active", name).Output()
		if active := strings.TrimSpace(string(output)); active != "" && active != "unknown" {
			state.active = active
		}
	}

	return state
}

func printResults(results []checkResult) {
	theme := tui.TerminalTheme()
	styles := tui.NewStyles(theme)

	currentCategory := category(-1)
	for _, r := range results {
		if r.category != currentCategory {
			if currentCategory != -1 {
				fmt.Println()
			}
			fmt.Printf("  %s\n", styles.Bold.Render(r.category.String()))
			currentCategory = r.category
		}
		printResultLine(r, styles)
	}
}

func printResultsJSON(results []checkResult) {
	var ds DoctorStatus
	for _, r := range results {
		ds.Add(r)
	}

	output := doctorOutputJSON{}
	output.Summary.Errors = ds.ErrorCount()
	output.Summary.Warnings = ds.WarningCount()
	output.Summary.OK = ds.OKCount()
	output.Summary.Info = len(ds.Info)

	output.Results = make([]checkResultJSON, 0, len(results))
	for _, r := range results {
		output.Results = append(output.Results, r.toJSON())
	}

	encoder := json.NewEncoder(os.Stdout)
	encoder.SetIndent("", "  ")
	if err := encoder.Encode(output); err != nil {
		fmt.Fprintf(os.Stderr, "Error encoding JSON: %v\n", err)
		os.Exit(1)
	}
}

func printResultLine(r checkResult, styles tui.Styles) {
	icon, style := r.status.IconStyle(styles)

	name := r.name
	nameLen := len(name)

	if nameLen > checkNameMaxLength {
		name = name[:checkNameMaxLength-1] + "…"
		nameLen = checkNameMaxLength
	}
	dots := strings.Repeat("·", checkNameMaxLength-nameLen)

	fmt.Printf("    %s %s %s %s\n", style.Render(icon), name, styles.Subtle.Render(dots), r.message)

	if r.details != "" && (doctorVerbose || r.status != statusOK) {
		fmt.Printf("      %s\n", styles.Subtle.Render("└─ "+r.details))
	}

	if (r.status == statusError || r.status == statusWarn) && r.url != "" {
		fmt.Printf("      %s\n", styles.Subtle.Render("→ "+r.url))
	}
}

func printSummary(results []checkResult, qsMissingFeatures bool) {
	theme := tui.TerminalTheme()
	styles := tui.NewStyles(theme)

	var ds DoctorStatus
	for _, r := range results {
		ds.Add(r)
	}

	fmt.Println()
	fmt.Printf("  %s\n", styles.Subtle.Render("──────────────────────────────────────"))

	if !ds.HasIssues() {
		fmt.Printf("  %s\n", styles.Success.Render("✓ All checks passed!"))
	} else {
		var parts []string

		if ds.ErrorCount() > 0 {
			parts = append(parts, styles.Error.Render(fmt.Sprintf("%d error(s)", ds.ErrorCount())))
		}
		if ds.WarningCount() > 0 {
			parts = append(parts, styles.Warning.Render(fmt.Sprintf("%d warning(s)", ds.WarningCount())))
		}
		parts = append(parts, styles.Success.Render(fmt.Sprintf("%d ok", ds.OKCount())))
		fmt.Printf("  %s\n", strings.Join(parts, ", "))

		if qsMissingFeatures {
			fmt.Println()
			fmt.Printf("  %s\n", styles.Subtle.Render("→ Consider using quickshell-git for full feature support"))
		}
	}
	fmt.Println()
}

func formatResultsPlain(results []checkResult) string {
	var sb strings.Builder
	sb.WriteString("## DMS Doctor Report\n\n")

	currentCategory := category(-1)
	for _, r := range results {
		if r.category != currentCategory {
			if currentCategory != -1 {
				sb.WriteString("\n")
			}
			fmt.Fprintf(&sb, "**%s**\n", r.category.String())
			currentCategory = r.category
		}

		fmt.Fprintf(&sb, "- [%s] %s: %s\n", r.status, r.name, r.message)

		if r.details != "" && (doctorVerbose || r.status != statusOK) {
			fmt.Fprintf(&sb, "  - %s\n", r.details)
		}
	}

	var ds DoctorStatus
	for _, r := range results {
		ds.Add(r)
	}

	sb.WriteString("\n---\n")
	fmt.Fprintf(&sb, "**Summary:** %d error(s), %d warning(s), %d ok\n",
		ds.ErrorCount(), ds.WarningCount(), ds.OKCount())

	return sb.String()
}

const (
	defaultDoctorFontFamily     = "Google Sans Flex"
	defaultDoctorMonoFontFamily = "Fira Code"
	defaultDoctorDisplayFamily  = "DM Serif Display"
)

var bundledFontRelPaths = map[string][]string{
	"google sans flex": {
		"DCommon/assets/fonts/google-sans-flex/GoogleSansFlex.ttf",
	},
	"fira code": {
		"DCommon/assets/fonts/nerd-fonts/FiraCodeNerdFont-Regular.ttf",
		"assets/fonts/nerd-fonts/FiraCodeNerdFont-Regular.ttf",
	},
	"firacode nerd font": {
		"DCommon/assets/fonts/nerd-fonts/FiraCodeNerdFont-Regular.ttf",
		"assets/fonts/nerd-fonts/FiraCodeNerdFont-Regular.ttf",
	},
	"dm serif display": {
		"DCommon/assets/fonts/dm-serif-display/DMSerifDisplay-Regular.ttf",
	},
	"notable": {
		"DCommon/assets/fonts/notable/Notable-Regular.ttf",
	},
	"gochi hand": {
		"DCommon/assets/fonts/gochi-hand/GochiHand-Regular.ttf",
	},
}

func resolveDoctorShellPath() string {
	if err := shellApp.ResolveConfig(nil, nil); err == nil && shellApp.ConfigPath() != "" {
		return shellApp.ConfigPath()
	}
	if path, err := config.LocateDMSConfig(); err == nil {
		return path
	}
	return ""
}

func findBundledFontFile(shellPath, family string) string {
	if shellPath == "" {
		return ""
	}
	relPaths, ok := bundledFontRelPaths[strings.ToLower(strings.TrimSpace(family))]
	if !ok {
		return ""
	}
	for _, rel := range relPaths {
		path := filepath.Join(shellPath, rel)
		if info, err := os.Stat(path); err == nil && !info.IsDir() {
			return path
		}
	}
	return ""
}

func isBundledDefaultFont(family string) bool {
	_, ok := bundledFontRelPaths[strings.ToLower(strings.TrimSpace(family))]
	return ok
}

const fcListQtFormat = "%{family}\t%{style}\t%{foundry}\n"

var qtGenericFamilies = map[string]bool{"sans serif": true, "serif": true, "monospace": true}

func qtFontFamilies() (map[string]bool, error) {
	output, err := exec.Command("fc-list", "--format", fcListQtFormat).Output()
	if err != nil {
		return nil, err
	}
	return parseQtFontFamilies(string(output)), nil
}

// parseQtFontFamilies retrieves, from the provided fcOutput list, a new map in the style of Qt.fontFamilies()
func parseQtFontFamilies(fcOutput string) map[string]bool {
	families := map[string]bool{}
	for line := range strings.SplitSeq(fcOutput, "\n") {
		fields := strings.Split(line, "\t")
		if len(fields) != 3 || fields[0] == "" {
			continue
		}
		styleCount := len(strings.Split(fields[1], ","))
		for i, fam := range strings.Split(fields[0], ",") {
			if i > 0 && i >= styleCount {
				break
			}
			families[strings.ToLower(fam)] = true
			// Qt only lists "Family [Foundry]" for multi-foundry families but resolves it either way
			if fields[2] != "" {
				families[strings.ToLower(fam+" ["+fields[2]+"]")] = true
			}
		}
	}
	return families
}

func fontInFcList(name string, families map[string]bool) bool {
	target := strings.ToLower(strings.TrimSpace(name))
	return qtGenericFamilies[target] || families[target]
}

func checkConfiguredFont(label, family, shellPath string, fcFamilies map[string]bool, fcListAvailable bool, url string) checkResult {
	if bundled := findBundledFontFile(shellPath, family); bundled != "" {
		details := "Bundled (Qt FontLoader)"
		if doctorVerbose {
			details = bundled
		}
		return checkResult{catFonts, label, statusOK, family, details, url}
	}

	if isBundledDefaultFont(family) {
		if shellPath == "" {
			return checkResult{
				catFonts, label, statusWarn,
				fmt.Sprintf("'%s' not verified", family),
				"Could not locate shell config to verify bundled font files.",
				url,
			}
		}
		return checkResult{
			catFonts, label, statusWarn,
			fmt.Sprintf("'%s' bundled file missing", family),
			"Expected font file missing from shell install. Reinstall DMS or check DCommon assets.",
			url,
		}
	}

	if !fcListAvailable {
		return checkResult{
			catFonts, label, statusWarn,
			fmt.Sprintf("'%s' not verified", family),
			"fc-list not installed; cannot verify custom fonts in fontconfig.",
			url,
		}
	}

	if len(fcFamilies) == 0 {
		return checkResult{
			catFonts, label, statusWarn,
			fmt.Sprintf("'%s' not found", family),
			"Fontconfig cache is empty or unreadable. Try running 'fc-cache -fv'.",
			url,
		}
	}

	if fontInFcList(family, fcFamilies) {
		return checkResult{catFonts, label, statusOK, family, "Available via fontconfig", url}
	}

	return checkResult{
		catFonts, label, statusWarn,
		fmt.Sprintf("'%s' not found", family),
		"Font is not registered with fontconfig. Try running 'fc-cache -fv' or install the font.",
		url,
	}
}

func checkFonts() []checkResult {
	var results []checkResult
	url := doctorDocsURL + "#fonts"

	fontFamily := defaultDoctorFontFamily
	monoFontFamily := defaultDoctorMonoFontFamily
	displayFontFamily := defaultDoctorDisplayFamily

	if configDir, err := os.UserConfigDir(); err == nil {
		settingsPath := filepath.Join(configDir, "dms", "settings.json")
		if data, err := os.ReadFile(settingsPath); err == nil {
			var settings struct {
				FontFamily        string `json:"fontFamily"`
				MonoFontFamily    string `json:"monoFontFamily"`
				DisplayFontFamily string `json:"displayFontFamily"`
			}
			if err := json.Unmarshal(data, &settings); err == nil {
				if settings.FontFamily != "" {
					fontFamily = settings.FontFamily
				}
				if settings.MonoFontFamily != "" {
					monoFontFamily = settings.MonoFontFamily
				}
				if settings.DisplayFontFamily != "" {
					displayFontFamily = settings.DisplayFontFamily
				}
			}
		}
	}

	shellPath := resolveDoctorShellPath()
	needFontconfig := !isBundledDefaultFont(fontFamily) || !isBundledDefaultFont(monoFontFamily) || !isBundledDefaultFont(displayFontFamily)

	fcListAvailable := utils.CommandExists("fc-list")
	var fcFamilies map[string]bool

	if needFontconfig {
		if !fcListAvailable {
			results = append(results, checkResult{catFonts, "Fontconfig Tools", statusWarn, "fc-list not installed", "Cannot verify custom fonts in fontconfig cache.", url})
		} else {
			families, err := qtFontFamilies()
			if err != nil {
				results = append(results, checkResult{catFonts, "Fontconfig Cache", statusError, "Failed to query font list", "Fontconfig cache query failed. Try running 'fc-cache -fv'.", url})
			} else {
				fcFamilies = families
				if len(fcFamilies) == 0 {
					results = append(results, checkResult{catFonts, "Fontconfig Cache", statusError, "Cache is empty", "No fonts found in fontconfig cache. Try running 'fc-cache -fv'.", url})
				}
			}
		}
	}

	results = append(results,
		checkConfiguredFont("Normal Font", fontFamily, shellPath, fcFamilies, fcListAvailable, url),
		checkConfiguredFont("Monospace Font", monoFontFamily, shellPath, fcFamilies, fcListAvailable, url),
		checkConfiguredFont("Display Font", displayFontFamily, shellPath, fcFamilies, fcListAvailable, url),
	)

	return results
}
