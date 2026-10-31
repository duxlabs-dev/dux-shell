package main

import (
	"bytes"
	"debug/elf"
	"encoding/binary"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

func TestQuickshellVersionFailureDetails(t *testing.T) {
	tests := []struct {
		name   string
		stderr string
		want   string
	}{
		{
			name:   "Qt private API symbol mismatch",
			stderr: "qs: symbol lookup error: qs: undefined symbol: _ZN23QUntypedPropertyBindingC1EP23QPropertyBindingPrivate, version Qt_6_PRIVATE_API",
			want:   "Quickshell is incompatible with the installed Qt libraries. Rebuild or reinstall Quickshell against the current Qt version.",
		},
		{
			name:   "other failure",
			stderr: "qs: unsupported option --version",
			want:   "Run 'qs --version' to inspect the failure.",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			if got := quickshellVersionFailureDetails(tc.stderr); got != tc.want {
				t.Fatalf("quickshellVersionFailureDetails(%q) = %q, want %q", tc.stderr, got, tc.want)
			}
		})
	}
}

// Parsing a full property dump as a bare value would yield a bogus plugin root,
// making the qtengine check warn at a user whose install is fine.
func TestQtQueryValue(t *testing.T) {
	const dumpAll = `QT_INSTALL_PREFIX:/usr
QT_INSTALL_PLUGINS:/usr/lib/qt/plugins
QT_VERSION:5.15.19`

	tests := []struct {
		name   string
		output string
		key    string
		want   string
	}{
		{
			name:   "bare value as qmake prints it",
			output: "/usr/lib/qt6/plugins\n",
			key:    "QT_INSTALL_PLUGINS",
			want:   "/usr/lib/qt6/plugins",
		},
		{
			name:   "key:value line among a full property dump",
			output: dumpAll,
			key:    "QT_INSTALL_PLUGINS",
			want:   "/usr/lib/qt/plugins",
		},
		{
			name:   "key absent from a multi line dump yields nothing",
			output: dumpAll,
			key:    "QT_INSTALL_LIBEXECS",
			want:   "",
		},
		{
			name:   "surrounding whitespace is trimmed",
			output: "  QT_INSTALL_PLUGINS:  /usr/lib/qt/plugins  \n",
			key:    "QT_INSTALL_PLUGINS",
			want:   "/usr/lib/qt/plugins",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			if got := qtQueryValue(tc.output, tc.key); got != tc.want {
				t.Fatalf("qtQueryValue(%q, %q) = %q, want %q", tc.output, tc.key, got, tc.want)
			}
		})
	}
}

// stubQtQueryTool writes a fake Qt build tool answering QT_VERSION and
// QT_INSTALL_PLUGINS from the given values, and points PATH at its directory
// alone so the real toolchain cannot interfere.
func stubQtQueryTool(t *testing.T, bin, version, plugins string) string {
	t.Helper()
	dir := t.TempDir()
	script := "#!/bin/sh\ncase \"$2\" in\n  QT_VERSION) echo " + version +
		" ;;\n  QT_INSTALL_PLUGINS) echo " + plugins + " ;;\nesac\n"
	if err := os.WriteFile(filepath.Join(dir, bin), []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir)
	return dir
}

func writePlugin(t *testing.T, pluginsDir, file string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Join(pluginsDir, "platformthemes"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(pluginsDir, "platformthemes", file), nil, 0o644); err != nil {
		t.Fatal(err)
	}
}

// writeQtPluginELF writes a minimal ELF holding only the .note.qt.metadata
// note Qt 6 embeds in plugins, recording the Qt version it was built against.
func writeQtPluginELF(t *testing.T, pluginsDir, file string, major, minor byte) {
	t.Helper()
	var note bytes.Buffer
	binary.Write(&note, binary.LittleEndian, []uint32{12, 4, 0x74510001})
	note.WriteString("qt-project!\x00")
	note.Write([]byte{1, major, minor, 1})
	shstrtab := []byte("\x00.note.qt.metadata\x00.shstrtab\x00")

	noteOff := uint64(64)
	strOff := noteOff + uint64(note.Len())
	shOff := strOff + uint64(len(shstrtab))
	var out bytes.Buffer
	header := elf.Header64{
		Type: uint16(elf.ET_DYN), Machine: uint16(elf.EM_X86_64), Version: uint32(elf.EV_CURRENT),
		Shoff: shOff, Ehsize: 64, Shentsize: 64, Shnum: 3, Shstrndx: 2,
	}
	copy(header.Ident[:], elf.ELFMAG)
	header.Ident[elf.EI_CLASS] = byte(elf.ELFCLASS64)
	header.Ident[elf.EI_DATA] = byte(elf.ELFDATA2LSB)
	header.Ident[elf.EI_VERSION] = byte(elf.EV_CURRENT)
	binary.Write(&out, binary.LittleEndian, header)
	out.Write(note.Bytes())
	out.Write(shstrtab)
	binary.Write(&out, binary.LittleEndian, []elf.Section64{
		{},
		{Name: 1, Type: uint32(elf.SHT_NOTE), Off: noteOff, Size: uint64(note.Len()), Addralign: 4},
		{Name: 20, Type: uint32(elf.SHT_STRTAB), Off: strOff, Size: uint64(len(shstrtab)), Addralign: 1},
	})

	if err := os.MkdirAll(filepath.Join(pluginsDir, "platformthemes"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(pluginsDir, "platformthemes", file), out.Bytes(), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestCheckQtPlatformThemePlugin(t *testing.T) {
	t.Run("qt6ct-kde is flagged as a package name, not a theme", func(t *testing.T) {
		t.Setenv("QT_QPA_PLATFORMTHEME", "qt6ct-kde")
		t.Setenv("PATH", t.TempDir()) // no Qt tools reachable
		results := checkQtPlatformThemePlugin("QT_QPA_PLATFORMTHEME")
		if len(results) != 1 {
			t.Fatalf("got %d results, want 1: %+v", len(results), results)
		}
		if results[0].status != statusWarn {
			t.Fatalf("status = %q, want warn", results[0].status)
		}
		if !strings.Contains(results[0].details, "package name") || !strings.Contains(results[0].details, "qt6ct") {
			t.Fatalf("details should name the package/value mixup, got %q", results[0].details)
		}
	})

	t.Run("installed plugin reports OK", func(t *testing.T) {
		t.Setenv("QT_QPA_PLATFORMTHEME", "qt6ct")
		plugins := t.TempDir()
		writePlugin(t, plugins, "libqt6ct.so")
		stubQtQueryTool(t, "qmake6", "6.11.2", plugins)
		results := checkQtPlatformThemePlugin("QT_QPA_PLATFORMTHEME")
		if len(results) != 1 || results[0].status != statusOK {
			t.Fatalf("got %+v, want one OK result", results)
		}
		if !strings.Contains(results[0].details, "libqt6ct.so") {
			t.Fatalf("details should point at the plugin, got %q", results[0].details)
		}
	})

	t.Run("plugin built for the installed Qt minor reports OK", func(t *testing.T) {
		t.Setenv("QT_QPA_PLATFORMTHEME", "qt6ct")
		plugins := t.TempDir()
		writeQtPluginELF(t, plugins, "libqt6ct.so", 6, 12)
		stubQtQueryTool(t, "qmake6", "6.12.3", plugins)
		results := checkQtPlatformThemePlugin("QT_QPA_PLATFORMTHEME")
		if len(results) != 1 || results[0].status != statusOK {
			t.Fatalf("got %+v, want one OK result", results)
		}
	})

	t.Run("plugin built for another Qt minor warns", func(t *testing.T) {
		t.Setenv("QT_QPA_PLATFORMTHEME", "qt6ct")
		plugins := t.TempDir()
		writeQtPluginELF(t, plugins, "libqt6ct.so", 6, 11)
		stubQtQueryTool(t, "qmake6", "6.12.0", plugins)
		results := checkQtPlatformThemePlugin("QT_QPA_PLATFORMTHEME")
		if len(results) != 1 || results[0].status != statusWarn {
			t.Fatalf("got %+v, want one warn result", results)
		}
		if results[0].message != "Built for Qt 6.11, Qt is 6.12.0" {
			t.Fatalf("message = %q, want both Qt versions", results[0].message)
		}
		if !strings.Contains(results[0].details, filepath.Join(plugins, "platformthemes", "libqt6ct.so")) {
			t.Fatalf("details should name the stale plugin, got %q", results[0].details)
		}
	})

	t.Run("missing plugin warns with the expected path", func(t *testing.T) {
		t.Setenv("QT_QPA_PLATFORMTHEME", "qt6ct")
		plugins := t.TempDir()
		stubQtQueryTool(t, "qtpaths6", "6.11.2", plugins)
		results := checkQtPlatformThemePlugin("QT_QPA_PLATFORMTHEME")
		if len(results) != 1 || results[0].status != statusWarn {
			t.Fatalf("got %+v, want one warn result", results)
		}
		want := filepath.Join(plugins, "platformthemes", "libqt6ct.so")
		if !strings.Contains(results[0].details, want) {
			t.Fatalf("details should contain expected path %s, got %q", want, results[0].details)
		}
	})

	t.Run("no Qt build tools degrades to info", func(t *testing.T) {
		t.Setenv("QT_QPA_PLATFORMTHEME", "qt6ct")
		t.Setenv("PATH", t.TempDir())
		results := checkQtPlatformThemePlugin("QT_QPA_PLATFORMTHEME")
		if len(results) != 1 || results[0].status != statusInfo {
			t.Fatalf("got %+v, want one info result", results)
		}
	})

	t.Run("unset is left to checkEnvVar", func(t *testing.T) {
		t.Setenv("PATH", t.TempDir())
		t.Setenv("QT_QPA_PLATFORMTHEME", "")
		if results := checkQtPlatformThemePlugin("QT_QPA_PLATFORMTHEME"); results != nil {
			t.Fatalf("unset should yield no results, got %+v", results)
		}
	})

	t.Run("qtengine checks the Qt5 and Qt6 plugins", func(t *testing.T) {
		t.Setenv("QT_QPA_PLATFORMTHEME", "qtengine")
		qt5, qt6 := t.TempDir(), t.TempDir()
		writePlugin(t, qt6, "libqt6engine-plugin.so")
		dir5 := stubQtQueryTool(t, "qmake-qt5", "5.15.19", qt5)
		dir6 := stubQtQueryTool(t, "qmake6", "6.11.2", qt6)
		t.Setenv("PATH", dir6+string(os.PathListSeparator)+dir5)
		results := checkQtPlatformThemePlugin("QT_QPA_PLATFORMTHEME")
		if len(results) != 2 {
			t.Fatalf("got %d results, want 2: %+v", len(results), results)
		}
		if results[0].name != "qtengine plugin (Qt5)" || results[0].status != statusWarn {
			t.Fatalf("Qt5 result = %+v, want a warning for the missing plugin", results[0])
		}
		if !strings.Contains(results[0].details, filepath.Join(qt5, "platformthemes", "libqt5engine-plugin.so")) {
			t.Fatalf("Qt5 details should contain the expected path, got %q", results[0].details)
		}
		if results[1].name != "qtengine plugin (Qt6)" || results[1].status != statusOK {
			t.Fatalf("Qt6 result = %+v, want OK", results[1])
		}
	})

	t.Run("qtengine in the qt6 variable skips Qt5", func(t *testing.T) {
		t.Setenv("QT_QPA_PLATFORMTHEME_QT6", "qtengine")
		qt5, qt6 := t.TempDir(), t.TempDir()
		writePlugin(t, qt6, "libqt6engine-plugin.so")
		dir5 := stubQtQueryTool(t, "qmake-qt5", "5.15.19", qt5)
		dir6 := stubQtQueryTool(t, "qmake6", "6.11.2", qt6)
		t.Setenv("PATH", dir6+string(os.PathListSeparator)+dir5)
		results := checkQtPlatformThemePlugin("QT_QPA_PLATFORMTHEME_QT6")
		if len(results) != 1 || results[0].name != "qtengine plugin (Qt6)" || results[0].status != statusOK {
			t.Fatalf("got %+v, want one OK Qt6 result", results)
		}
	})

	t.Run("qtengine without Qt tools degrades to one info", func(t *testing.T) {
		t.Setenv("QT_QPA_PLATFORMTHEME", "qtengine")
		t.Setenv("PATH", t.TempDir())
		results := checkQtPlatformThemePlugin("QT_QPA_PLATFORMTHEME")
		if len(results) != 1 || results[0].status != statusInfo || results[0].name != "qtengine plugin (Qt6)" {
			t.Fatalf("got %+v, want one Qt6 info result", results)
		}
	})

	t.Run("qt6 variable is not satisfied by a Qt5 tool alone", func(t *testing.T) {
		t.Setenv("QT_QPA_PLATFORMTHEME_QT6", "qt6ct")
		plugins := t.TempDir()
		stubQtQueryTool(t, "qmake-qt5", "5.15.19", plugins)
		results := checkQtPlatformThemePlugin("QT_QPA_PLATFORMTHEME_QT6")
		if len(results) != 1 || results[0].status != statusInfo {
			t.Fatalf("got %+v, want one info result", results)
		}
	})

	t.Run("kde plugin miss degrades to info", func(t *testing.T) {
		t.Setenv("QT_QPA_PLATFORMTHEME", "kde")
		plugins := t.TempDir()
		stubQtQueryTool(t, "qmake6", "6.11.2", plugins)
		results := checkQtPlatformThemePlugin("QT_QPA_PLATFORMTHEME")
		if len(results) != 1 || results[0].status != statusInfo {
			t.Fatalf("got %+v, want one info result", results)
		}
	})

	t.Run("gtk3 resolves through the libq convention", func(t *testing.T) {
		t.Setenv("QT_QPA_PLATFORMTHEME", "gtk3")
		plugins := t.TempDir()
		writePlugin(t, plugins, "libqgtk3.so")
		stubQtQueryTool(t, "qmake6", "6.11.2", plugins)
		results := checkQtPlatformThemePlugin("QT_QPA_PLATFORMTHEME")
		if len(results) != 1 || results[0].status != statusOK {
			t.Fatalf("got %+v, want one OK result", results)
		}
	})
}

func TestCheckQtengineConfig(t *testing.T) {
	configHome, dataHome := t.TempDir(), t.TempDir()
	t.Setenv("XDG_CONFIG_HOME", configHome)
	t.Setenv("XDG_DATA_HOME", dataHome)
	path := filepath.Join(configHome, "qtengine", "config.json")
	scheme := filepath.Join(dataHome, "color-schemes", "DankMatugen.colors")

	write := func(t *testing.T, content string) {
		t.Helper()
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}

	tests := []struct {
		name    string
		content string // "" leaves the file absent
		status  status
		message string
	}{
		{"missing", "", statusInfo, "Not found"},
		{"empty", "\n", statusInfo, "Not found"},
		{"unparseable", "{", statusWarn, "Unreadable"},
		{"theme is not an object", `{"theme": 1}`, statusWarn, "Unreadable"},
		{"dms scheme", `{"theme": {"colorScheme": "` + scheme + `"}}`, statusOK, "Uses DMS colors"},
		{"other scheme", `{"theme": {"colorScheme": "/usr/share/color-schemes/BreezeDark.colors"}}`, statusInfo, "Not using DMS colors"},
		{"no scheme", `{"theme": {}}`, statusInfo, "Not using DMS colors"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			os.Remove(path)
			if tc.content != "" {
				write(t, tc.content)
			}
			results := checkQtengineConfig()
			if len(results) != 1 || results[0].status != tc.status || results[0].message != tc.message {
				t.Fatalf("got %+v, want %s %q", results, tc.status, tc.message)
			}
		})
	}
}

func TestCheckXDGMenuFile(t *testing.T) {
	configHome, systemDir := t.TempDir(), t.TempDir()
	t.Setenv("XDG_CONFIG_HOME", configHome)
	t.Setenv("XDG_CONFIG_DIRS", systemDir)

	if checkXDGMenuFile("hyprland-") {
		t.Fatal("no menu file anywhere should not be found")
	}
	for _, dir := range []string{configHome, systemDir} {
		menus := filepath.Join(dir, "menus")
		if err := os.MkdirAll(menus, 0o755); err != nil {
			t.Fatal(err)
		}
		file := filepath.Join(menus, "hyprland-applications.menu")
		if err := os.WriteFile(file, nil, 0o644); err != nil {
			t.Fatal(err)
		}
		if !checkXDGMenuFile("hyprland-") {
			t.Fatalf("menu file in %s should be found", menus)
		}
		os.Remove(file)
	}
}

func TestCheckMangoConfigReportsUnknownKeysAndOverviewBinds(t *testing.T) {
	dir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(dir, "dms"), 0o755); err != nil {
		t.Fatal(err)
	}
	_ = os.WriteFile(filepath.Join(dir, "config.conf"), []byte("exec-once=dms run\nmousebind=NONE,btn_left,toggleoverview,1\n"), 0o644)
	// Shape of `mango -p` 0.18.2 output, colours included; the same key twice collapses.
	parsed := "\x1b[1m\x1b[31m[ERROR]:\x1b[0m Unknown keyword: \x1b[1m\x1b[31mexec-once\x1b[0m\n" +
		"\x1b[1;31m╰─\x1b[1;33m[Index]\x1b[0m \x1b[1;36m" + dir + "/config.conf\x1b[0m:\x1b[1;35m1\x1b[0m\n   ╰─exec-once=dms run\n\n" +
		"[ERROR]: Unknown keyword: overviewgappo\n╰─[Index] " + dir + "/dms/layout.conf:10\n   ╰─overviewgappo=30\n" +
		"[ERROR]: Unknown keyword: overviewgappo\n╰─[Index] " + dir + "/dms/layout.conf:12\n"
	prev := mangoParseConfig
	mangoParseConfig = func(string) (string, error) { return parsed, nil }
	t.Cleanup(func() { mangoParseConfig = prev })

	got := checkMangoConfig(dir)
	if len(got) != 2 || got[0].message != "Unknown keys: exec-once (config.conf), overviewgappo (layout.conf)" || got[1].name != "Mango mouse binds" {
		t.Fatalf("got %+v", got)
	}
	mangoParseConfig = func(string) (string, error) { return "", os.ErrNotExist }
	if got := checkMangoConfig(dir); len(got) != 1 {
		t.Fatalf("without mango on PATH only the bind check should run, got %+v", got)
	}
}

func TestMangoLacksSnakeCase(t *testing.T) {
	for ver, want := range map[string]bool{
		"0.17.5": true,
		"0.18.0": false,
		"0.18.2": false,
		"":       false,
	} {
		if got := mangoLacksSnakeCase(ver); got != want {
			t.Errorf("mangoLacksSnakeCase(%q) = %v, want %v", ver, got, want)
		}
	}
}

func TestHyprlandLacksLua(t *testing.T) {
	for ver, want := range map[string]bool{
		"0.54.9": true,
		"0.55.0": false,
		"":       false,
	} {
		if got := hyprlandLacksLua(ver); got != want {
			t.Errorf("hyprlandLacksLua(%q) = %v, want %v", ver, got, want)
		}
	}
}

func TestCheckHyprlandQuickshellFloor(t *testing.T) {
	for _, tc := range []struct {
		hypr, qs string
		warn     bool
	}{
		{"0.57.0", "0.3.1", true},
		{"0.57.0", "0.3.2", false},
		{"0.56.1", "0.2.1", false},
		{"0.57.0", "", false},
	} {
		if got := checkHyprlandQuickshellFloor(tc.hypr, tc.qs); (len(got) == 1 && got[0].status == statusWarn) != tc.warn || (!tc.warn && len(got) != 0) {
			t.Errorf("hyprland %q quickshell %q: got %+v, want warn=%v", tc.hypr, tc.qs, got, tc.warn)
		}
	}
}

func TestHyprlandDeprecatedConfigResults(t *testing.T) {
	got := hyprlandDeprecatedConfigResults([]byte(`["general:no_border_on_floating", "decoration:shadow:range"]`))
	if len(got) != 1 || got[0].status != statusWarn || !strings.Contains(got[0].details, "decoration:shadow:range") {
		t.Fatalf("got %+v, want one warning listing both keys", got)
	}
	for _, out := range []string{"[]", "unknown request"} {
		if got := hyprlandDeprecatedConfigResults([]byte(out)); len(got) != 0 {
			t.Errorf("%q: got %+v, want nothing", out, got)
		}
	}
}

func TestCheckGreetdSession(t *testing.T) {
	dir := t.TempDir()
	wrapper := filepath.Join(dir, "dms-greeter")
	if err := os.WriteFile(wrapper, []byte("#!/bin/sh\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	hyprlang := filepath.Join(dir, "dms-hypr.conf")
	if err := os.WriteFile(hyprlang, []byte("# see hl.dsp docs\nexec-once = waybar\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	luaConf := filepath.Join(dir, "lua-hypr.conf")
	if err := os.WriteFile(luaConf, []byte("hl.config({ misc = { disable_hyprland_logo = true } })\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	for name, tc := range map[string]struct {
		command string
		warn    bool
	}{
		"pre-1.6 wrapper":           {wrapper + " --command niri", true},
		"hyprlang greeter config":   {"dux-greeter --command hyprland -C " + hyprlang, true},
		"hyprlang via --config=":    {"dux-greeter --command hyprland --config='" + hyprlang + "'", true},
		"lua content in a .conf":    {"dux-greeter --command hyprland -C " + luaConf, false},
		"lua greeter config":        {"dux-greeter --command hyprland -C /etc/greetd/dms-hypr.lua", false},
		"unreadable greeter config": {"dux-greeter --command hyprland -C " + filepath.Join(dir, "missing.conf"), false},
		"niri greeter":              {"dux-greeter --command niri -C /etc/greetd/niri.kdl", false},
	} {
		config := filepath.Join(t.TempDir(), "config.toml")
		toml := "[terminal]\nvt = 1\n\n[default_session]\ncommand = \"" + tc.command + "\"\nuser = \"greeter\"\n"
		if err := os.WriteFile(config, []byte(toml), 0o644); err != nil {
			t.Fatal(err)
		}
		if got := checkGreetdSession(config); (len(got) == 1 && got[0].status == statusWarn) != tc.warn || (!tc.warn && len(got) != 0) {
			t.Errorf("%s: got %+v, want warn=%v", name, got, tc.warn)
		}
	}
}

func TestRetiredGreeterPackagesInstalled(t *testing.T) {
	tests := map[string]struct {
		query string
		want  []string
	}{
		"dux successor satisfying the retired names": {"dux-greeter-git 2.0.0.r165.g7cf13f1-1\ndux-greeter-git 2.0.0.r165.g7cf13f1-1\ndux-greeter-git 2.0.0.r165.g7cf13f1-1\n", nil},
		"retired package still installed":            {"greetd-dms-greeter-git 1:1.6.2.r0.g0175be5-1\ngreetd-dms-greeter-git 1:1.6.2.r0.g0175be5-1\n", []string{"greetd-dms-greeter-git", "greetd-dms-greeter-git"}},
		"nothing installed":                          {"", nil},
	}
	for name, tc := range tests {
		t.Run(name, func(t *testing.T) {
			if got := retiredGreeterPackagesInstalled(tc.query); !slices.Equal(got, tc.want) {
				t.Fatalf("got %v, want %v", got, tc.want)
			}
		})
	}
}
