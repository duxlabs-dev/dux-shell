package matugen

import (
	"encoding/json"
	"fmt"
	"image"
	stdcolor "image/color"
	"image/png"
	"math"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
	"time"

	matcolor "github.com/duxlabs-dev/dux-go/material/color"
	mocks_utils "github.com/duxlabs-dev/dux-shell/core/internal/mocks/utils"
	"github.com/duxlabs-dev/dux-shell/core/internal/utils"
	"github.com/stretchr/testify/assert"
)

func TestAppendConfigBinaryExists(t *testing.T) {
	tempDir := t.TempDir()

	shellDir := filepath.Join(tempDir, "shell")
	configsDir := filepath.Join(shellDir, "matugen", "configs")
	if err := os.MkdirAll(configsDir, 0o755); err != nil {
		t.Fatalf("failed to create configs dir: %v", err)
	}

	testConfig := "test config content"
	configPath := filepath.Join(configsDir, "test.toml")
	if err := os.WriteFile(configPath, []byte(testConfig), 0o644); err != nil {
		t.Fatalf("failed to write config: %v", err)
	}

	outFile := filepath.Join(tempDir, "output.toml")
	cfgFile, err := os.Create(outFile)
	if err != nil {
		t.Fatalf("failed to create output file: %v", err)
	}
	defer cfgFile.Close()

	mockChecker := mocks_utils.NewMockAppChecker(t)
	mockChecker.EXPECT().AnyCommandExists("sh").Return(true)

	opts := &Options{ShellDir: shellDir, AppChecker: mockChecker}

	appendConfig(opts, cfgFile, []string{"sh"}, nil, nil, "test.toml")

	cfgFile.Close()
	output, err := os.ReadFile(outFile)
	if err != nil {
		t.Fatalf("failed to read output: %v", err)
	}

	if len(output) == 0 {
		t.Errorf("expected config to be written when binary exists")
	}
	if string(output) != testConfig+"\n" {
		t.Errorf("expected %q, got %q", testConfig+"\n", string(output))
	}
}

func TestAppendConfigFlatpakExists(t *testing.T) {
	tempDir := t.TempDir()

	shellDir := filepath.Join(tempDir, "shell")
	configsDir := filepath.Join(shellDir, "matugen", "configs")
	if err := os.MkdirAll(configsDir, 0o755); err != nil {
		t.Fatalf("failed to create configs dir: %v", err)
	}

	testConfig := "zen config content"
	configPath := filepath.Join(configsDir, "test.toml")
	if err := os.WriteFile(configPath, []byte(testConfig), 0o644); err != nil {
		t.Fatalf("failed to write config: %v", err)
	}

	outFile := filepath.Join(tempDir, "output.toml")
	cfgFile, err := os.Create(outFile)
	if err != nil {
		t.Fatalf("failed to create output file: %v", err)
	}
	defer cfgFile.Close()

	mockChecker := mocks_utils.NewMockAppChecker(t)
	mockChecker.EXPECT().AnyFlatpakExists("app.zen_browser.zen").Return(true)

	opts := &Options{ShellDir: shellDir, AppChecker: mockChecker}

	appendConfig(opts, cfgFile, nil, []string{"app.zen_browser.zen"}, nil, "test.toml")

	cfgFile.Close()
	output, err := os.ReadFile(outFile)
	if err != nil {
		t.Fatalf("failed to read output: %v", err)
	}

	if len(output) == 0 {
		t.Errorf("expected config to be written when flatpak exists")
	}
}

func TestAppendConfigNeitherExists(t *testing.T) {
	tempDir := t.TempDir()

	shellDir := filepath.Join(tempDir, "shell")
	configsDir := filepath.Join(shellDir, "matugen", "configs")
	if err := os.MkdirAll(configsDir, 0o755); err != nil {
		t.Fatalf("failed to create configs dir: %v", err)
	}

	testConfig := "test config content"
	configPath := filepath.Join(configsDir, "test.toml")
	if err := os.WriteFile(configPath, []byte(testConfig), 0o644); err != nil {
		t.Fatalf("failed to write config: %v", err)
	}

	outFile := filepath.Join(tempDir, "output.toml")
	cfgFile, err := os.Create(outFile)
	if err != nil {
		t.Fatalf("failed to create output file: %v", err)
	}
	defer cfgFile.Close()

	mockChecker := mocks_utils.NewMockAppChecker(t)
	mockChecker.EXPECT().AnyCommandExists("nonexistent-binary-12345").Return(false)
	mockChecker.EXPECT().AnyFlatpakExists("com.nonexistent.flatpak").Return(false)

	opts := &Options{ShellDir: shellDir, AppChecker: mockChecker}

	appendConfig(opts, cfgFile, []string{"nonexistent-binary-12345"}, []string{"com.nonexistent.flatpak"}, nil, "test.toml")

	cfgFile.Close()
	output, err := os.ReadFile(outFile)
	if err != nil {
		t.Fatalf("failed to read output: %v", err)
	}

	if len(output) != 0 {
		t.Errorf("expected no config when neither exists, got: %q", string(output))
	}
}

func TestAppendConfigNoChecks(t *testing.T) {
	tempDir := t.TempDir()

	shellDir := filepath.Join(tempDir, "shell")
	configsDir := filepath.Join(shellDir, "matugen", "configs")
	if err := os.MkdirAll(configsDir, 0o755); err != nil {
		t.Fatalf("failed to create configs dir: %v", err)
	}

	testConfig := "always include"
	configPath := filepath.Join(configsDir, "test.toml")
	if err := os.WriteFile(configPath, []byte(testConfig), 0o644); err != nil {
		t.Fatalf("failed to write config: %v", err)
	}

	outFile := filepath.Join(tempDir, "output.toml")
	cfgFile, err := os.Create(outFile)
	if err != nil {
		t.Fatalf("failed to create output file: %v", err)
	}
	defer cfgFile.Close()

	opts := &Options{ShellDir: shellDir}

	appendConfig(opts, cfgFile, nil, nil, nil, "test.toml")

	cfgFile.Close()
	output, err := os.ReadFile(outFile)
	if err != nil {
		t.Fatalf("failed to read output: %v", err)
	}

	if len(output) == 0 {
		t.Errorf("expected config to be written when no checks specified")
	}
}

func TestAppendConfigFileDoesNotExist(t *testing.T) {
	tempDir := t.TempDir()

	shellDir := filepath.Join(tempDir, "shell")
	configsDir := filepath.Join(shellDir, "matugen", "configs")
	if err := os.MkdirAll(configsDir, 0o755); err != nil {
		t.Fatalf("failed to create configs dir: %v", err)
	}

	outFile := filepath.Join(tempDir, "output.toml")
	cfgFile, err := os.Create(outFile)
	if err != nil {
		t.Fatalf("failed to create output file: %v", err)
	}
	defer cfgFile.Close()

	opts := &Options{ShellDir: shellDir}

	appendConfig(opts, cfgFile, nil, nil, nil, "nonexistent.toml")

	cfgFile.Close()
	output, err := os.ReadFile(outFile)
	if err != nil {
		t.Fatalf("failed to read output: %v", err)
	}

	if len(output) != 0 {
		t.Errorf("expected no config when file doesn't exist, got: %q", string(output))
	}
}

func TestSourceSelectionArgs(t *testing.T) {
	tests := []struct {
		name           string
		sourceMode     string
		supportsPrefer bool
		expected       []string
	}{
		{"darkness", "darkness", true, []string{"--prefer", "darkness"}},
		{"empty falls back to dominant", "", true, []string{"--source-color-index", "0"}},
		{"typo falls back", "bogus", true, []string{"--source-color-index", "0"}},
		{"wrong case is not allowlisted", "DARKNESS", true, []string{"--source-color-index", "0"}},
		{"closest-to-fallback is deliberately excluded", "closest-to-fallback", true, []string{"--source-color-index", "0"}},
		{"injection-shaped value cannot escape the allowlist", "value; --exec touch /tmp/pwned", true, []string{"--source-color-index", "0"}},
		// matugen 4.0.x has --source-color-index but not --prefer, and aborts on
		// an unknown argument. Every prefer mode must degrade, not fail.
		{"4.0.x: darkness degrades", "darkness", false, []string{"--source-color-index", "0"}},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			result := sourceSelectionArgs(tc.sourceMode, tc.supportsPrefer)
			assert.Equal(t, tc.expected, result)
			if !tc.supportsPrefer {
				assert.NotContains(t, result, "--prefer", "matugen 4.0.x must never see --prefer")
			}
		})
	}
}

func TestBuildMatugenArgsSourceModes(t *testing.T) {
	baseArgs := []string{"-c", "/tmp/merged.toml", "-t", "scheme-tonal-spot"}

	t.Run("v4", func(t *testing.T) {
		args := buildMatugenArgs(baseArgs, matugenFlags{isV4: true, supportsPrefer: true}, "darkness")
		assert.Equal(t, append(append([]string{}, baseArgs...), "--prefer", "darkness"), args)
	})

	t.Run("v4.0", func(t *testing.T) {
		// matugen 4.0.x: --source-color-index exists, --prefer does not.
		args := buildMatugenArgs(baseArgs, matugenFlags{isV4: true, supportsPrefer: false}, "darkness")
		assert.Equal(t, append(append([]string{}, baseArgs...), "--source-color-index", "0"), args)
	})

	t.Run("v3", func(t *testing.T) {
		// matugen 3 has neither --prefer nor --source-color-index. Adding
		// either would break every user still on it, so under isV4=false
		// no source-selection args may appear for any mode.
		args := buildMatugenArgs(baseArgs, matugenFlags{isV4: false}, "darkness")
		assert.Equal(t, baseArgs, args)
	})
}

func TestBuildImportData(t *testing.T) {
	const dank16 = `{"color0":"#000000"}`

	assert.Equal(t, `{"dank16": {"color0":"#000000"}}`, buildImportData(dank16, "", "", nil),
		"no image must produce byte-identical import data to pre-feature behavior")
	assert.Equal(t, `{"dank16": {"color0":"#000000"}, "image": "/home/u/My Wallpaper.png"}`,
		buildImportData(dank16, "/home/u/My Wallpaper.png", "", nil))
	assert.Equal(t, `{"dank16": {"color0":"#000000"}, "image": "/home/u/a\"b\\c.png"}`,
		buildImportData(dank16, `/home/u/a"b\c.png`, "", nil), "paths must be escaped, not interpolated raw")
}

// writeTestPNG encodes img as a PNG at path, failing the test on any error.
func writeTestPNG(t *testing.T, path string, img image.Image) {
	t.Helper()
	f, err := os.Create(path)
	if err != nil {
		t.Fatalf("failed to create test image: %v", err)
	}
	defer f.Close()
	if err := png.Encode(f, img); err != nil {
		t.Fatalf("failed to encode test image: %v", err)
	}
}

func TestExtractSourceColorPrefersVividOverDull(t *testing.T) {
	dir := t.TempDir()

	const w, h = 50, 50
	img := image.NewRGBA(image.Rect(0, 0, w, h))
	dull := stdcolor.RGBA{R: 190, G: 200, B: 210, A: 255} // pale grey-blue, low chroma
	vivid := stdcolor.RGBA{R: 255, G: 140, B: 0, A: 255}  // strong warm orange

	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			img.Set(x, y, dull)
		}
	}
	// ~19% of the image, in a corner, well clear of 80/20.
	const vividSize = 22
	for y := 0; y < vividSize; y++ {
		for x := 0; x < vividSize; x++ {
			img.Set(x, y, vivid)
		}
	}

	path := filepath.Join(dir, "mixed.png")
	writeTestPNG(t, path, img)

	seed, err := ExtractSourceColor(path)
	if err != nil {
		t.Fatalf("ExtractSourceColor returned an error: %v", err)
	}

	var r, g, b uint8
	if _, err := fmt.Sscanf(seed, "#%02x%02x%02x", &r, &g, &b); err != nil {
		t.Fatalf("seed %q is not a #RRGGBB hex string: %v", seed, err)
	}
	hct := matcolor.NewARGB(255, r, g, b).ToHct()

	dullHue := matcolor.NewARGB(255, dull.R, dull.G, dull.B).ToHct().Hue

	// The failure this feature targets is landing on the large dull region.
	// Assert the hue family, not an exact value: it must be nowhere near the
	// dull blue-grey (~240) and it must sit in the warm orange/yellow band
	// the vivid region occupies (~58, with generous tolerance either side).
	assert.InDelta(t, 58.0, hct.Hue, 40.0, "expected the seed's hue to be in the vivid orange family, got hue=%.2f from %s", hct.Hue, seed)
	assert.Greater(t, hueDistance(hct.Hue, dullHue), 60.0, "seed hue %.2f should not be in the dull region's hue family (%.2f)", hct.Hue, dullHue)
}

// hueDistance is the shortest angular distance between two hues on a 360
// degree wheel.
func hueDistance(a, b float64) float64 {
	d := math.Abs(a - b)
	if d > 180 {
		d = 360 - d
	}
	return d
}

func TestExtractSourceColorDeterministic(t *testing.T) {
	dir := t.TempDir()

	const w, h = 50, 50
	img := image.NewRGBA(image.Rect(0, 0, w, h))
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			if x < 22 && y < 22 {
				img.Set(x, y, stdcolor.RGBA{R: 255, G: 140, B: 0, A: 255})
			} else {
				img.Set(x, y, stdcolor.RGBA{R: 190, G: 200, B: 210, A: 255})
			}
		}
	}
	path := filepath.Join(dir, "deterministic.png")
	writeTestPNG(t, path, img)

	first, err := ExtractSourceColor(path)
	if err != nil {
		t.Fatalf("ExtractSourceColor returned an error: %v", err)
	}

	for i := 0; i < 3; i++ {
		next, err := ExtractSourceColor(path)
		if err != nil {
			t.Fatalf("ExtractSourceColor returned an error on repeat run %d: %v", i, err)
		}
		assert.Equal(t, first, next, "the same wallpaper must yield a byte-identical seed every run")
	}
}

func TestExtractSourceColorFullyTransparentImage(t *testing.T) {
	dir := t.TempDir()
	// image.NewRGBA zero-values to fully transparent black.
	img := image.NewRGBA(image.Rect(0, 0, 8, 8))
	path := filepath.Join(dir, "transparent.png")
	writeTestPNG(t, path, img)

	seed, err := ExtractSourceColor(path)

	assert.Error(t, err)
	assert.Empty(t, seed)
	assert.Contains(t, err.Error(), "no opaque pixels")
}

func TestExtractSourceColorAllBlackImage(t *testing.T) {
	dir := t.TempDir()
	img := image.NewRGBA(image.Rect(0, 0, 8, 8))
	for y := 0; y < 8; y++ {
		for x := 0; x < 8; x++ {
			img.Set(x, y, stdcolor.RGBA{R: 0, G: 0, B: 0, A: 255})
		}
	}
	path := filepath.Join(dir, "black.png")
	writeTestPNG(t, path, img)

	seed, err := ExtractSourceColor(path)

	assert.Error(t, err)
	assert.Empty(t, seed)
	assert.Contains(t, err.Error(), "no usable color")
}

func TestExtractSourceColorOnePixelDoesNotPanic(t *testing.T) {
	dir := t.TempDir()
	img := image.NewRGBA(image.Rect(0, 0, 1, 1))
	img.Set(0, 0, stdcolor.RGBA{R: 255, G: 0, B: 0, A: 255})
	path := filepath.Join(dir, "one-pixel.png")
	writeTestPNG(t, path, img)

	assert.NotPanics(t, func() {
		_, _ = ExtractSourceColor(path)
	})
}

func TestSubstituteVars(t *testing.T) {
	configDir := utils.XDGConfigHome()
	dataDir := utils.XDGDataHome()
	cacheDir := utils.XDGCacheHome()

	tests := []struct {
		name     string
		input    string
		shellDir string
		expected string
	}{
		{
			name:     "substitutes all dir types",
			input:    "'SHELL_DIR/a' 'CONFIG_DIR/b' 'DATA_DIR/c' 'CACHE_DIR/d'",
			shellDir: "/shell",
			expected: "'/shell/a' '" + configDir + "/b' '" + dataDir + "/c' '" + cacheDir + "/d'",
		},
		{
			name:     "no substitution when no placeholders",
			input:    "input_path = '/absolute/path/foo.conf'",
			shellDir: "/home/user/shell",
			expected: "input_path = '/absolute/path/foo.conf'",
		},
		{
			name:     "multiple SHELL_DIR occurrences",
			input:    "'SHELL_DIR/a' and 'SHELL_DIR/b'",
			shellDir: "/shell",
			expected: "'/shell/a' and '/shell/b'",
		},
		{
			name:     "only substitutes quoted paths",
			input:    "SHELL_DIR/unquoted and 'SHELL_DIR/quoted'",
			shellDir: "/shell",
			expected: "SHELL_DIR/unquoted and '/shell/quoted'",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			result := substituteVars(tc.input, tc.shellDir)
			assert.Equal(t, tc.expected, result)
		})
	}
}

func TestBuildMergedConfigColorsOnly(t *testing.T) {
	tempDir := t.TempDir()

	shellDir := filepath.Join(tempDir, "shell")
	configsDir := filepath.Join(shellDir, "matugen", "configs")
	if err := os.MkdirAll(configsDir, 0o755); err != nil {
		t.Fatalf("failed to create configs dir: %v", err)
	}

	baseConfig := "[config]\ncustom_keywords = []\n"
	if err := os.WriteFile(filepath.Join(configsDir, "base.toml"), []byte(baseConfig), 0o644); err != nil {
		t.Fatalf("failed to write base config: %v", err)
	}

	cfgFile, err := os.CreateTemp(tempDir, "merged-*.toml")
	if err != nil {
		t.Fatalf("failed to create temp config: %v", err)
	}
	defer os.Remove(cfgFile.Name())
	defer cfgFile.Close()

	opts := &Options{
		ShellDir:   shellDir,
		ConfigDir:  filepath.Join(tempDir, "config"),
		StateDir:   filepath.Join(tempDir, "state"),
		ColorsOnly: true,
	}

	if err := buildMergedConfig(opts, cfgFile, filepath.Join(tempDir, "templates")); err != nil {
		t.Fatalf("buildMergedConfig failed: %v", err)
	}

	if err := cfgFile.Close(); err != nil {
		t.Fatalf("failed to close merged config: %v", err)
	}

	output, err := os.ReadFile(cfgFile.Name())
	if err != nil {
		t.Fatalf("failed to read merged config: %v", err)
	}

	content := string(output)
	assert.Contains(t, content, "[templates.dank]")
	assert.Contains(t, content, "output_path = '"+opts.colorsStaging()+"'")
	assert.NotContains(t, content, "[templates.gtk]")
	assert.False(t, strings.Contains(content, "output_path = 'CONFIG_DIR/"), "colors-only config should not emit app template outputs")
}

func TestBuildMergedConfigMangoSession(t *testing.T) {
	t.Setenv("MANGO_INSTANCE_SIGNATURE", "")

	tempDir := t.TempDir()
	shellDir := filepath.Join(tempDir, "shell")
	configsDir := filepath.Join(shellDir, "matugen", "configs")
	if err := os.MkdirAll(configsDir, 0o755); err != nil {
		t.Fatalf("failed to create configs dir: %v", err)
	}

	if err := os.WriteFile(filepath.Join(configsDir, "base.toml"), []byte("[config]\n"), 0o644); err != nil {
		t.Fatalf("failed to write base config: %v", err)
	}
	mangowcConfig := "[templates.dmsmango]\ninput_path = 'in'\noutput_path = 'out'\n"
	if err := os.WriteFile(filepath.Join(configsDir, "mangowc.toml"), []byte(mangowcConfig), 0o644); err != nil {
		t.Fatalf("failed to write mangowc config: %v", err)
	}

	cfgFile, err := os.CreateTemp(tempDir, "merged-*.toml")
	if err != nil {
		t.Fatalf("failed to create temp config: %v", err)
	}
	defer os.Remove(cfgFile.Name())
	defer cfgFile.Close()

	opts := &Options{
		ShellDir:      shellDir,
		ConfigDir:     filepath.Join(tempDir, "config"),
		StateDir:      filepath.Join(tempDir, "state"),
		SkipTemplates: "gtk,niri,hyprland,qt5ct,qt6ct,firefox,pywalfox,zenbrowser,vesktop,vencord,equibop,ghostty,kitty,foot,alacritty,wezterm,nvim,dgop,kcolorscheme,vscode,emacs,zed",
	}

	if err := buildMergedConfig(opts, cfgFile, filepath.Join(tempDir, "templates")); err != nil {
		t.Fatalf("buildMergedConfig failed: %v", err)
	}
	if err := cfgFile.Close(); err != nil {
		t.Fatalf("failed to close merged config: %v", err)
	}

	output, err := os.ReadFile(cfgFile.Name())
	if err != nil {
		t.Fatalf("failed to read merged config: %v", err)
	}
	assert.NotContains(t, string(output), "[templates.dmsmango]")

	socket := filepath.Join(tempDir, "mango.sock")
	if err := os.WriteFile(socket, nil, 0o600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("MANGO_INSTANCE_SIGNATURE", socket)
	checker := mocks_utils.NewMockAppChecker(t)
	checker.EXPECT().AnyCommandExists("mango").Return(true)
	opts.AppChecker = checker
	cfgFile, err = os.CreateTemp(tempDir, "merged-active-*.toml")
	if err != nil {
		t.Fatal(err)
	}
	defer cfgFile.Close()
	if err := buildMergedConfig(opts, cfgFile, filepath.Join(tempDir, "templates")); err != nil {
		t.Fatal(err)
	}
	if err := cfgFile.Close(); err != nil {
		t.Fatal(err)
	}
	output, err = os.ReadFile(cfgFile.Name())
	if err != nil {
		t.Fatal(err)
	}
	assert.Contains(t, string(output), mangowcConfig)
}

func TestAppendConfigConfigDirExists(t *testing.T) {
	tempDir := t.TempDir()

	shellDir := filepath.Join(tempDir, "shell")
	configsDir := filepath.Join(shellDir, "matugen", "configs")
	if err := os.MkdirAll(configsDir, 0o755); err != nil {
		t.Fatalf("failed to create configs dir: %v", err)
	}

	testConfig := "vencord config content"
	if err := os.WriteFile(filepath.Join(configsDir, "vencord.toml"), []byte(testConfig), 0o644); err != nil {
		t.Fatalf("failed to write config: %v", err)
	}

	configHome := filepath.Join(tempDir, "config")
	if err := os.MkdirAll(filepath.Join(configHome, "Vencord"), 0o755); err != nil {
		t.Fatalf("failed to create Vencord config dir: %v", err)
	}
	t.Setenv("XDG_CONFIG_HOME", configHome)

	outFile := filepath.Join(tempDir, "output.toml")
	cfgFile, err := os.Create(outFile)
	if err != nil {
		t.Fatalf("failed to create output file: %v", err)
	}
	defer cfgFile.Close()

	mockChecker := mocks_utils.NewMockAppChecker(t)
	mockChecker.EXPECT().AnyCommandExists("nonexistent-binary-12345").Return(false)
	mockChecker.EXPECT().AnyFlatpakExists("com.nonexistent.flatpak").Return(false)

	opts := &Options{ShellDir: shellDir, AppChecker: mockChecker}

	appendConfig(opts, cfgFile, []string{"nonexistent-binary-12345"}, []string{"com.nonexistent.flatpak"}, []string{"Vencord"}, "vencord.toml")

	cfgFile.Close()
	output, err := os.ReadFile(outFile)
	if err != nil {
		t.Fatalf("failed to read output: %v", err)
	}

	assert.Equal(t, testConfig+"\n", string(output))
}

func TestAppendConfigConfigDirDoesNotExist(t *testing.T) {
	tempDir := t.TempDir()

	shellDir := filepath.Join(tempDir, "shell")
	configsDir := filepath.Join(shellDir, "matugen", "configs")
	if err := os.MkdirAll(configsDir, 0o755); err != nil {
		t.Fatalf("failed to create configs dir: %v", err)
	}

	if err := os.WriteFile(filepath.Join(configsDir, "vencord.toml"), []byte("vencord config content"), 0o644); err != nil {
		t.Fatalf("failed to write config: %v", err)
	}

	configHome := filepath.Join(tempDir, "config")
	if err := os.MkdirAll(configHome, 0o755); err != nil {
		t.Fatalf("failed to create config home: %v", err)
	}
	t.Setenv("XDG_CONFIG_HOME", configHome)

	outFile := filepath.Join(tempDir, "output.toml")
	cfgFile, err := os.Create(outFile)
	if err != nil {
		t.Fatalf("failed to create output file: %v", err)
	}
	defer cfgFile.Close()

	mockChecker := mocks_utils.NewMockAppChecker(t)
	mockChecker.EXPECT().AnyCommandExists("nonexistent-binary-12345").Return(false)
	mockChecker.EXPECT().AnyFlatpakExists("com.nonexistent.flatpak").Return(false)

	opts := &Options{ShellDir: shellDir, AppChecker: mockChecker}

	appendConfig(opts, cfgFile, []string{"nonexistent-binary-12345"}, []string{"com.nonexistent.flatpak"}, []string{"Vencord"}, "vencord.toml")

	cfgFile.Close()
	output, err := os.ReadFile(outFile)
	if err != nil {
		t.Fatalf("failed to read output: %v", err)
	}

	assert.Empty(t, string(output))
}

func TestAppendFlatpakConfigRewritesOutputAndTemplateName(t *testing.T) {
	tempDir := t.TempDir()
	shellDir := filepath.Join(tempDir, "shell")
	configDir := filepath.Join(shellDir, "matugen", "configs")
	if err := os.MkdirAll(configDir, 0o755); err != nil {
		t.Fatalf("failed to create config directory: %v", err)
	}

	config := "[templates.dmsvesktop]\ninput_path = 'SHELL_DIR/matugen/templates/vesktop.css'\noutput_path = 'CONFIG_DIR/vesktop/themes/dank-discord.css'\n"
	if err := os.WriteFile(filepath.Join(configDir, "vesktop.toml"), []byte(config), 0o644); err != nil {
		t.Fatalf("failed to write config: %v", err)
	}

	outPath := filepath.Join(tempDir, "merged.toml")
	cfgFile, err := os.Create(outPath)
	if err != nil {
		t.Fatalf("failed to create output: %v", err)
	}
	defer cfgFile.Close()

	mockChecker := mocks_utils.NewMockAppChecker(t)
	mockChecker.EXPECT().AnyFlatpakExists("dev.vencord.Vesktop").Return(true)
	t.Setenv("HOME", "/home/test")

	appendFlatpakConfig(&Options{ShellDir: shellDir, AppChecker: mockChecker}, cfgFile, []string{"dev.vencord.Vesktop"}, "vesktop.toml", "dev.vencord.Vesktop/config")
	if err := cfgFile.Close(); err != nil {
		t.Fatalf("failed to close output: %v", err)
	}

	output, err := os.ReadFile(outPath)
	if err != nil {
		t.Fatalf("failed to read output: %v", err)
	}

	assert.Contains(t, string(output), "[templates.dmsvesktop-flatpak]")
	assert.Contains(t, string(output), "'/home/test/.var/app/dev.vencord.Vesktop/config/vesktop/themes/dank-discord.css'")
}

func TestQtengineActive(t *testing.T) {
	tests := []struct {
		name string
		env  map[string]string
		want bool
	}{
		{name: "both unset", want: false},
		{name: "qtengine on QT_QPA_PLATFORMTHEME", env: map[string]string{"QT_QPA_PLATFORMTHEME": "qtengine"}, want: true},
		{name: "qtengine on QT_QPA_PLATFORMTHEME_QT6", env: map[string]string{"QT_QPA_PLATFORMTHEME_QT6": "qtengine"}, want: true},
		{name: "gtk3", env: map[string]string{"QT_QPA_PLATFORMTHEME": "gtk3"}, want: false},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			for _, key := range []string{"QT_QPA_PLATFORMTHEME", "QT_QPA_PLATFORMTHEME_QT6"} {
				t.Setenv(key, "")
				os.Unsetenv(key)
			}
			for key, value := range tc.env {
				t.Setenv(key, value)
			}

			assert.Equal(t, tc.want, QtengineActive())
		})
	}
}

func TestSyncQtengineConfig(t *testing.T) {
	const (
		uiFont    = "Inter,11,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
		fixedFont = "JetBrainsMono Nerd Font,11,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
	)

	existingConfig := `{
  "theme": {
    "style": "Fusion",
    "font": "` + uiFont + `",
    "fontFixed": "` + fixedFont + `",
    "colorScheme": "/stale/path/Old.colors",
    "iconTheme": "breeze"
  },
  "misc": {
    "wheelScrollLines": 3,
    "dialogButtonsHaveIcons": true
  },
  "somethingQtengineAddsLater": ["keep", "me"]
}
`

	tests := []struct {
		name          string
		existing      string
		writeEmpty    bool
		noColorScheme bool
		iconTheme     string
		wantErr       bool
		check         func(t *testing.T, cfg, theme map[string]any)
	}{
		{
			name:      "creates config when none exists",
			iconTheme: "Papirus-Dark",
			check: func(t *testing.T, cfg, theme map[string]any) {
				assert.Equal(t, "Papirus-Dark", theme["iconTheme"])
			},
		},
		{
			name:      "preserves user keys at every level",
			existing:  existingConfig,
			iconTheme: "Papirus-Dark",
			check: func(t *testing.T, cfg, theme map[string]any) {
				assert.Equal(t, "Fusion", theme["style"])
				assert.Equal(t, uiFont, theme["font"])
				assert.Equal(t, fixedFont, theme["fontFixed"])
				assert.Equal(t, "Papirus-Dark", theme["iconTheme"])
				assert.Equal(t, map[string]any{"wheelScrollLines": float64(3), "dialogButtonsHaveIcons": true}, cfg["misc"])
				assert.Equal(t, []any{"keep", "me"}, cfg["somethingQtengineAddsLater"])
			},
		},
		{
			name:      "System Default leaves the existing icon theme alone",
			existing:  existingConfig,
			iconTheme: "System Default",
			check: func(t *testing.T, cfg, theme map[string]any) {
				assert.Equal(t, "breeze", theme["iconTheme"])
			},
		},
		{
			name:      "empty icon theme writes no iconTheme key",
			iconTheme: "",
			check: func(t *testing.T, cfg, theme map[string]any) {
				_, ok := theme["iconTheme"]
				assert.False(t, ok, "iconTheme must stay absent when none was requested")
			},
		},
		{
			name:      "a top level null is a fresh start, not a panic",
			existing:  "null",
			iconTheme: "Papirus-Dark",
			check: func(t *testing.T, cfg, theme map[string]any) {
				assert.Equal(t, "Papirus-Dark", theme["iconTheme"])
			},
		},
		{
			name:       "an empty file is a fresh start",
			writeEmpty: true,
			iconTheme:  "Papirus-Dark",
			check: func(t *testing.T, cfg, theme map[string]any) {
				assert.Equal(t, "Papirus-Dark", theme["iconTheme"])
			},
		},
		{
			name:      "a null theme is treated as absent",
			existing:  "{\n  \"theme\": null,\n  \"misc\": {\"wheelScrollLines\": 3}\n}\n",
			iconTheme: "Papirus-Dark",
			check: func(t *testing.T, cfg, theme map[string]any) {
				assert.Equal(t, "Papirus-Dark", theme["iconTheme"])
				assert.Equal(t, map[string]any{"wheelScrollLines": float64(3)}, cfg["misc"])
			},
		},
		{
			name:          "leaves a hand set colorScheme alone when DMS generated none",
			existing:      existingConfig,
			noColorScheme: true,
			iconTheme:     "Papirus-Dark",
			check: func(t *testing.T, cfg, theme map[string]any) {
				assert.Equal(t, "/stale/path/Old.colors", theme["colorScheme"], "pointing qtengine at a scheme that does not exist resets the user's palette")
				assert.Equal(t, "Papirus-Dark", theme["iconTheme"])
				assert.Equal(t, "Fusion", theme["style"])
			},
		},
		{
			name:          "writes no colorScheme at all when there is none to point at",
			noColorScheme: true,
			iconTheme:     "Papirus-Dark",
			check: func(t *testing.T, cfg, theme map[string]any) {
				_, ok := theme["colorScheme"]
				assert.False(t, ok, "colorScheme must stay absent rather than name a missing file")
				assert.Equal(t, "Papirus-Dark", theme["iconTheme"])
			},
		},
		{
			name:      "refuses to clobber malformed json",
			existing:  "{ this is not json",
			iconTheme: "Papirus-Dark",
			wantErr:   true,
		},
		{
			name:      "refuses to clobber a non-object theme",
			existing:  "{\n  \"theme\": \"Fusion\"\n}\n",
			iconTheme: "Papirus-Dark",
			wantErr:   true,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			tempDir := t.TempDir()
			configDir := filepath.Join(tempDir, "config")
			dataHome := filepath.Join(tempDir, "data")
			t.Setenv("XDG_CONFIG_HOME", configDir)
			t.Setenv("XDG_DATA_HOME", dataHome)

			path := QtengineConfigPath()
			assert.Equal(t, filepath.Join(configDir, "qtengine", "config.json"), path)

			scheme := filepath.Join(dataHome, "color-schemes", "DankMatugen.colors")
			if !tc.noColorScheme {
				if err := os.MkdirAll(filepath.Dir(scheme), 0o755); err != nil {
					t.Fatalf("failed to create color-schemes dir: %v", err)
				}
				if err := os.WriteFile(scheme, []byte("[Colors:Window]\n"), 0o644); err != nil {
					t.Fatalf("failed to write color scheme: %v", err)
				}
			}

			if tc.existing != "" || tc.writeEmpty {
				if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
					t.Fatalf("failed to create qtengine config dir: %v", err)
				}
				if err := os.WriteFile(path, []byte(tc.existing), 0o644); err != nil {
					t.Fatalf("failed to write existing config: %v", err)
				}
			}

			err := SyncQtengineConfig(tc.iconTheme)

			if tc.wantErr {
				assert.Error(t, err)
				after, readErr := os.ReadFile(path)
				assert.NoError(t, readErr)
				assert.Equal(t, tc.existing, string(after), "a rejected merge must leave the file byte-identical")
				return
			}

			assert.NoError(t, err)

			info, err := os.Stat(path)
			if err != nil {
				t.Fatalf("failed to stat written config: %v", err)
			}
			assert.Equal(t, os.FileMode(0o644), info.Mode().Perm())

			data, err := os.ReadFile(path)
			if err != nil {
				t.Fatalf("failed to read written config: %v", err)
			}
			assert.True(t, strings.HasSuffix(string(data), "}\n"), "config should be indented JSON with a trailing newline, got %q", string(data))

			var cfg map[string]any
			if err := json.Unmarshal(data, &cfg); err != nil {
				t.Fatalf("written config is not valid JSON: %v", err)
			}
			theme, ok := cfg["theme"].(map[string]any)
			if !ok {
				t.Fatalf("written config has no theme object: %#v", cfg["theme"])
			}
			if !tc.noColorScheme {
				assert.Equal(t, scheme, theme["colorScheme"])
			}

			if tc.check != nil {
				tc.check(t, cfg, theme)
			}
		})
	}
}

func TestSyncQtengineConfigAtUsesExplicitConfigDir(t *testing.T) {
	tempDir := t.TempDir()
	xdgConfigDir := filepath.Join(tempDir, "xdg-config")
	explicitConfigDir := filepath.Join(tempDir, "explicit-config")
	dataHome := filepath.Join(tempDir, "data")
	t.Setenv("XDG_CONFIG_HOME", xdgConfigDir)
	t.Setenv("XDG_DATA_HOME", dataHome)

	scheme := filepath.Join(dataHome, "color-schemes", "DankMatugen.colors")
	if err := os.MkdirAll(filepath.Dir(scheme), 0o755); err != nil {
		t.Fatalf("failed to create color-schemes dir: %v", err)
	}
	if err := os.WriteFile(scheme, []byte("[Colors:Window]\n"), 0o644); err != nil {
		t.Fatalf("failed to write color scheme: %v", err)
	}

	if err := SyncQtengineConfigAt(explicitConfigDir, "Papirus-Dark"); err != nil {
		t.Fatalf("sync with explicit config dir failed: %v", err)
	}

	explicitPath := filepath.Join(explicitConfigDir, "qtengine", "config.json")
	data, err := os.ReadFile(explicitPath)
	if err != nil {
		t.Fatalf("failed to read config from explicit directory: %v", err)
	}
	var cfg map[string]any
	if err := json.Unmarshal(data, &cfg); err != nil {
		t.Fatalf("written config is not valid JSON: %v", err)
	}
	theme, ok := cfg["theme"].(map[string]any)
	if !ok {
		t.Fatalf("written config has no theme object: %#v", cfg["theme"])
	}
	assert.Equal(t, scheme, theme["colorScheme"])
	assert.Equal(t, "Papirus-Dark", theme["iconTheme"])

	_, err = os.Stat(filepath.Join(xdgConfigDir, "qtengine", "config.json"))
	assert.ErrorIs(t, err, os.ErrNotExist, "explicit config dir must take precedence over XDG_CONFIG_HOME")
}

// The appended entry is the only thing driving the settings row's indicator.
func TestCheckTemplatesIncludesQtengine(t *testing.T) {
	tests := []struct {
		name          string
		platformTheme string
		wantDetected  bool
	}{
		{name: "detected when qtengine is the platform theme", platformTheme: "qtengine", wantDetected: true},
		{name: "not detected under another platform theme", platformTheme: "gtk3", wantDetected: false},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Setenv("QT_QPA_PLATFORMTHEME", tc.platformTheme)
			t.Setenv("QT_QPA_PLATFORMTHEME_QT6", "")

			// nil uses the default checker; the qtengine entry never consults it.
			var found *TemplateCheck
			for _, check := range CheckTemplates(nil) {
				if check.ID == "qtengine" {
					found = &check
					break
				}
			}

			if found == nil {
				t.Fatal("CheckTemplates must report qtengine; the settings row indicator depends on it")
			}
			assert.Equal(t, tc.wantDetected, found.Detected)
		})
	}
}

func TestSyncQtengineConfigBumpsMtime(t *testing.T) {
	tempDir := t.TempDir()
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(tempDir, "config"))
	t.Setenv("XDG_DATA_HOME", filepath.Join(tempDir, "data"))

	if err := SyncQtengineConfig("Papirus-Dark"); err != nil {
		t.Fatalf("first sync failed: %v", err)
	}

	path := QtengineConfigPath()
	before, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("failed to read written config: %v", err)
	}

	past := time.Now().Add(-time.Hour)
	if err := os.Chtimes(path, past, past); err != nil {
		t.Fatalf("failed to backdate config: %v", err)
	}

	if err := SyncQtengineConfig("Papirus-Dark"); err != nil {
		t.Fatalf("second sync failed: %v", err)
	}

	info, err := os.Stat(path)
	if err != nil {
		t.Fatalf("failed to stat config: %v", err)
	}
	assert.True(t, info.ModTime().After(past), "an unchanged write must still bump mtime; that is what repaints running apps")

	after, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("failed to re-read config: %v", err)
	}
	assert.Equal(t, string(before), string(after))
}

func TestResolveSmartMode(t *testing.T) {
	tests := []struct {
		name        string
		mode        ColorMode
		matugenType string
		kind        string
		stockColors string
		isV42       bool
		wantErr     string
		wantMode    ColorMode
	}{
		{
			name:     "concrete mode passes through untouched",
			mode:     ColorModeLight,
			kind:     "image",
			isV42:    true,
			wantMode: ColorModeLight,
		},
		{
			name:    "smart mode errors on old matugen",
			mode:    ColorModeSmart,
			kind:    "image",
			isV42:   false,
			wantErr: "smart mode requires matugen 4.2+",
		},
		{
			name:        "scheme-smart errors on old matugen",
			mode:        ColorModeDark,
			matugenType: "scheme-smart",
			kind:        "image",
			isV42:       false,
			wantErr:     "scheme-smart requires matugen 4.2+",
		},
		{
			name:     "smart falls back to dark for non-image kind",
			mode:     ColorModeSmart,
			kind:     "hex",
			isV42:    true,
			wantMode: ColorModeDark,
		},
		{
			name:        "smart falls back to dark for stock colors",
			mode:        ColorModeSmart,
			kind:        "image",
			stockColors: `{"primary":{}}`,
			isV42:       true,
			wantMode:    ColorModeDark,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			opts := &Options{
				Mode:        tc.mode,
				MatugenType: tc.matugenType,
				Kind:        tc.kind,
				StockColors: tc.stockColors,
			}
			if opts.MatugenType == "" {
				opts.MatugenType = "scheme-tonal-spot"
			}

			_, err := resolveSmartMode(opts, matugenFlags{isV42: tc.isV42})
			if tc.wantErr != "" {
				assert.ErrorContains(t, err, tc.wantErr)
				return
			}
			assert.NoError(t, err)
			assert.Equal(t, tc.wantMode, opts.Mode)
		})
	}
}

func writeUserMatugenConfig(t *testing.T, configDir, content string) {
	t.Helper()
	dir := filepath.Join(configDir, "matugen")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatalf("failed to create matugen config dir: %v", err)
	}
	if err := os.WriteFile(filepath.Join(dir, "config.toml"), []byte(content), 0o644); err != nil {
		t.Fatalf("failed to write user config: %v", err)
	}
}

func TestWriteDryRunConfigAlwaysDeclaresConfigAndTemplates(t *testing.T) {
	tests := []struct {
		name             string
		userConfig       string
		runUserTemplates bool
		wantContains     []string
		wantNotContains  []string
	}{
		{
			name:             "comment only user config",
			userConfig:       "# nothing here\n",
			runUserTemplates: true,
			wantNotContains:  []string{"# nothing here"},
		},
		{
			name:             "user config section is carried over",
			userConfig:       "[config]\nfallback_color = \"#ff0000\"\n\n[templates.mine]\ninput_path = 'in'\noutput_path = 'out'\n",
			runUserTemplates: true,
			wantContains:     []string{"fallback_color = \"#ff0000\""},
			wantNotContains:  []string{"[templates.mine]"},
		},
		{
			name:            "user templates disabled",
			userConfig:      "[config]\nfallback_color = \"#ff0000\"\n",
			wantNotContains: []string{"fallback_color"},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			configDir := filepath.Join(t.TempDir(), "config")
			writeUserMatugenConfig(t, configDir, tc.userConfig)

			opts := &Options{ConfigDir: configDir, RunUserTemplates: tc.runUserTemplates}
			cfgPath, err := writeDryRunConfig(opts)
			if err != nil {
				t.Fatalf("writeDryRunConfig failed: %v", err)
			}
			defer os.Remove(cfgPath)

			data, err := os.ReadFile(cfgPath)
			if err != nil {
				t.Fatalf("failed to read dry-run config: %v", err)
			}

			content := string(data)
			assert.Contains(t, content, "[config]")
			assert.Contains(t, content, "[templates]")
			for _, want := range tc.wantContains {
				assert.Contains(t, content, want)
			}
			for _, unwanted := range tc.wantNotContains {
				assert.NotContains(t, content, unwanted)
			}
		})
	}
}

func TestApplyTerminalTemplate(t *testing.T) {
	opts := func(v int, dark bool) *Options { return &Options{TerminalOpacity: v, TerminalsAlwaysDark: dark} }
	tests := []struct {
		name, tmpl, in, want string
		opts                 *Options
	}{
		{"kitty", "kitty.conf", "a\n", "a\nbackground_opacity 0.85\ndynamic_background_opacity yes\n", opts(85, false)},
		{"foot", "foot.ini", "a\n", "a\nalpha=0.85\n", opts(85, false)},
		{"ghostty", "ghostty.conf", "a\n", "a\nbackground-opacity = 0.85\n", opts(85, false)},
		{"alacritty", "alacritty.toml", "a\n", "a\n[window]\nopacity = 0.85\n", opts(85, false)},
		{"no trailing newline", "foot.ini", "a", "a\nalpha=0.5\n", opts(50, false)},
		{"100", "kitty.conf", "a\n", "a\n", opts(100, false)},
		{"0", "kitty.conf", "a\n", "a\n", opts(0, false)},
		{"negative", "kitty.conf", "a\n", "a\n", opts(-5, false)},
		{"tabs", "kitty-tabs.conf", "a\n", "a\n", opts(85, false)},
		{"wezterm", "wezterm.toml", "a\n", "a\n", opts(85, false)},
		{"dark and opacity", "kitty.conf", "x.default.y\n", "x.dark.y\nbackground_opacity 0.85\ndynamic_background_opacity yes\n", opts(85, true)},
		{"opacity only keeps default", "kitty.conf", "x.default.y\n", "x.default.y\nbackground_opacity 0.85\ndynamic_background_opacity yes\n", opts(85, false)},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.want, applyTerminalTemplate(tt.tmpl, tt.in, tt.opts))
		})
	}
}

func TestAppendTerminalConfigOpacity(t *testing.T) {
	tempDir := t.TempDir()
	shellDir := filepath.Join(tempDir, "shell")
	cfgDir := filepath.Join(shellDir, "matugen", "configs")
	tmplDir := filepath.Join(shellDir, "matugen", "templates")
	for _, d := range []string{cfgDir, tmplDir} {
		if err := os.MkdirAll(d, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	toml := "[templates.dmskitty]\ninput_path = 'SHELL_DIR/matugen/templates/kitty.conf'\noutput_path = 'out/kitty'\n\n" +
		"[templates.dmskittytabs]\ninput_path = 'SHELL_DIR/matugen/templates/kitty-tabs.conf'\noutput_path = 'out/tabs'\n"
	for name, c := range map[string]string{
		filepath.Join(cfgDir, "kitty.toml"):       toml,
		filepath.Join(tmplDir, "kitty.conf"):      "color0 {{x}}\n",
		filepath.Join(tmplDir, "kitty-tabs.conf"): "tab {{x}}\n",
	} {
		if err := os.WriteFile(name, []byte(c), 0o644); err != nil {
			t.Fatal(err)
		}
	}

	run := func(opacity int) (string, string) {
		runTmp := t.TempDir()
		checker := mocks_utils.NewMockAppChecker(t)
		checker.EXPECT().AnyCommandExists("kitty").Return(true)
		out := filepath.Join(runTmp, "out.toml")
		f, err := os.Create(out)
		if err != nil {
			t.Fatal(err)
		}
		opts := &Options{ShellDir: shellDir, AppChecker: checker, TerminalOpacity: opacity}
		appendTerminalConfig(opts, f, runTmp, []string{"kitty"}, nil, "kitty.toml")
		f.Close()
		b, _ := os.ReadFile(out)
		return string(b), runTmp
	}

	got, runTmp := run(85)
	kittyCopy := filepath.Join(runTmp, "kitty.conf")
	tabsCopy := filepath.Join(runTmp, "kitty-tabs.conf")
	assert.Contains(t, got, "input_path = '"+kittyCopy+"'")
	assert.Contains(t, got, "input_path = '"+tabsCopy+"'")
	b, err := os.ReadFile(kittyCopy)
	assert.NoError(t, err)
	assert.True(t, strings.HasSuffix(string(b), "background_opacity 0.85\ndynamic_background_opacity yes\n"))
	b, err = os.ReadFile(tabsCopy)
	assert.NoError(t, err)
	assert.Equal(t, "tab {{x}}\n", string(b))

	got, runTmp = run(0)
	assert.Equal(t, substituteVars(toml, shellDir)+"\n", got)
	_, err = os.Stat(filepath.Join(runTmp, "kitty.conf"))
	assert.True(t, os.IsNotExist(err))
}

func TestGenerateDank16VariantsProfile(t *testing.T) {
	gen := func(profile string) map[string]any {
		out := generateDank16Variants("#8ad0ee", "#1c5070", "#0f1417", "#f5fafd", "#1b2023", "#e9eef2", ColorModeDark, profile)
		var m map[string]any
		if err := json.Unmarshal([]byte(out), &m); err != nil {
			t.Fatal(err)
		}
		return m
	}
	def, high := gen(""), gen("high")
	assert.NotEqual(t, def["color1"], high["color1"])
	assert.Equal(t, def["color0"], high["color0"])
}

func TestTerminalPaletteOnlyReachesTerminalTemplates(t *testing.T) {
	shellDir := filepath.Join("..", "..", "..", "quickshell")
	inputPath := regexp.MustCompile(`input_path = 'SHELL_DIR/([^']+)'`)
	checked := 0
	for _, def := range templateRegistry {
		if def.ConfigFile == "" {
			continue
		}
		config, err := os.ReadFile(filepath.Join(shellDir, "matugen", "configs", def.ConfigFile))
		if !assert.NoError(t, err) {
			continue
		}
		for _, m := range inputPath.FindAllStringSubmatch(string(config), -1) {
			data, err := os.ReadFile(filepath.Join(shellDir, m[1]))
			if !assert.NoError(t, err) {
				continue
			}
			content := string(data)
			if def.Kind == TemplateKindTerminal {
				assert.NotContains(t, content, "{{dank16.", "%s: terminal templates read dank16term", m[1])
			} else {
				assert.NotContains(t, content, "dank16term", "%s: only terminal templates follow the terminal palette", m[1])
			}
			checked++
		}
	}
	assert.Greater(t, checked, 10)
}
