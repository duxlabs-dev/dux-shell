package headless

import (
	"strings"
	"testing"

	"github.com/duxlabs-dev/dux-shell/core/internal/deps"
	"github.com/duxlabs-dev/dux-shell/core/internal/distros"
)

func TestParseWindowManager(t *testing.T) {
	tests := []struct {
		name    string
		input   string
		want    deps.WindowManager
		wantErr bool
	}{
		{"niri mixed case", "Niri", deps.WindowManagerNiri, false},
		{"hyprland lowercase", "hyprland", deps.WindowManagerHyprland, false},
		{"invalid", "sway", 0, true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			r := NewRunner(Config{Compositor: tt.input})
			got, err := r.parseWindowManager()
			if (err != nil) != tt.wantErr {
				t.Errorf("parseWindowManager() error = %v, wantErr %v", err, tt.wantErr)
				return
			}
			if !tt.wantErr && got != tt.want {
				t.Errorf("parseWindowManager() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestParseTerminal(t *testing.T) {
	tests := []struct {
		name    string
		input   string
		want    deps.Terminal
		wantErr bool
	}{
		{"ghostty lowercase", "ghostty", deps.TerminalGhostty, false},
		{"kitty lowercase", "kitty", deps.TerminalKitty, false},
		{"alacritty uppercase", "ALACRITTY", deps.TerminalAlacritty, false},
		{"invalid", "wezterm", 0, true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			r := NewRunner(Config{Terminal: tt.input})
			got, err := r.parseTerminal()
			if (err != nil) != tt.wantErr {
				t.Errorf("parseTerminal() error = %v, wantErr %v", err, tt.wantErr)
				return
			}
			if !tt.wantErr && got != tt.want {
				t.Errorf("parseTerminal() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestLog(t *testing.T) {
	r := NewRunner(Config{})

	// log should not block even if channel is full
	for range 1100 {
		r.log("message")
	}
	// If we reach here without hanging, the non-blocking send works
}

func TestValidConfigNamesCompleteness(t *testing.T) {
	// orderedConfigNames and validConfigNames must stay in sync.
	if len(orderedConfigNames) != len(validConfigNames) {
		t.Fatalf("orderedConfigNames has %d entries but validConfigNames has %d",
			len(orderedConfigNames), len(validConfigNames))
	}

	// Every entry in orderedConfigNames must exist in validConfigNames.
	for _, name := range orderedConfigNames {
		if _, ok := validConfigNames[name]; !ok {
			t.Errorf("orderedConfigNames contains %q which is missing from validConfigNames", name)
		}
	}

	// validConfigNames must have no extra keys not in orderedConfigNames.
	ordered := make(map[string]bool, len(orderedConfigNames))
	for _, name := range orderedConfigNames {
		ordered[name] = true
	}
	for key := range validConfigNames {
		if !ordered[key] {
			t.Errorf("validConfigNames contains %q which is missing from orderedConfigNames", key)
		}
	}
}

func TestBuildReplaceConfigs(t *testing.T) {
	allDeployerKeys := []string{"Niri", "Hyprland", "Mango", "Ghostty", "Kitty", "Alacritty"}

	tests := []struct {
		name           string
		replaceConfigs []string
		replaceAll     bool
		wantNil        bool     // expect nil (replace all)
		wantEnabled    []string // deployer keys that should be true
		wantErr        bool
	}{
		{
			name:        "neither flag set",
			wantNil:     false,
			wantEnabled: nil, // all should be false
		},
		{
			name:       "replace-configs-all",
			replaceAll: true,
			wantNil:    true,
		},
		{
			name:           "specific configs",
			replaceConfigs: []string{"niri", "mango", "ghostty"},
			wantNil:        false,
			wantEnabled:    []string{"Niri", "Mango", "Ghostty"},
		},
		{
			name:           "both flags set",
			replaceConfigs: []string{"niri"},
			replaceAll:     true,
			wantErr:        true,
		},
		{
			name:           "invalid config name",
			replaceConfigs: []string{"foo"},
			wantErr:        true,
		},
		{
			name:           "case insensitive",
			replaceConfigs: []string{"NIRI", "Ghostty"},
			wantNil:        false,
			wantEnabled:    []string{"Niri", "Ghostty"},
		},
		{
			name:           "whitespace entry",
			replaceConfigs: []string{"  ", "niri"},
			wantNil:        false,
			wantEnabled:    []string{"Niri"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			r := NewRunner(Config{
				ReplaceConfigs:    tt.replaceConfigs,
				ReplaceConfigsAll: tt.replaceAll,
			})
			got, err := r.buildReplaceConfigs()
			if (err != nil) != tt.wantErr {
				t.Fatalf("buildReplaceConfigs() error = %v, wantErr %v", err, tt.wantErr)
			}
			if tt.wantErr {
				return
			}
			if tt.wantNil {
				if got != nil {
					t.Fatalf("buildReplaceConfigs() = %v, want nil", got)
				}
				return
			}
			if got == nil {
				t.Fatal("buildReplaceConfigs() = nil, want non-nil map")
			}

			// All known deployer keys must be present
			for _, key := range allDeployerKeys {
				if _, exists := got[key]; !exists {
					t.Errorf("missing deployer key %q in result map", key)
				}
			}

			// Build enabled set for easy lookup
			enabledSet := make(map[string]bool)
			for _, k := range tt.wantEnabled {
				enabledSet[k] = true
			}

			for _, key := range allDeployerKeys {
				want := enabledSet[key]
				if got[key] != want {
					t.Errorf("replaceConfigs[%q] = %v, want %v", key, got[key], want)
				}
			}
		})
	}
}

func TestBuildDisabledItems(t *testing.T) {
	dependencies := []deps.Dependency{
		{Name: "niri", Status: deps.StatusInstalled, Required: true},
		{Name: "ghostty", Status: deps.StatusMissing, Required: true},
		{Name: "dms (Dux Shell)", Status: deps.StatusInstalled, Required: true},
		{Name: "dux-greeter", Status: deps.StatusMissing},
		{Name: "dux-search", Status: deps.StatusMissing},
		{Name: "dux-calendar", Status: deps.StatusMissing},
		{Name: "dux-files", Status: deps.StatusMissing},
		{Name: "waybar", Status: deps.StatusMissing, Required: true},
	}

	tests := []struct {
		name         string
		includeDeps  []string
		excludeDeps  []string
		duxSearch    bool
		duxCalendar  bool
		duxFiles     bool
		duxGreeter   bool
		allFeatures  bool
		deps         []deps.Dependency // nil means use the shared fixture
		wantErr      bool
		errContains  string   // substring expected in error message
		wantDisabled []string // dep names that should be in disabledItems
		wantEnabled  []string // dep names that should NOT be in disabledItems (extra check)
	}{
		{
			name:         "no flags set, optional deps disabled by default",
			wantDisabled: []string{"dux-greeter", "dux-search", "dux-calendar"},
			wantEnabled:  []string{"niri", "ghostty", "waybar"},
		},
		{
			name:         "include dux-greeter enables it",
			includeDeps:  []string{"dux-greeter"},
			wantEnabled:  []string{"dux-greeter"},
			wantDisabled: []string{"dux-search", "dux-calendar"},
		},
		{
			name:         "include and exclude accept the dank-era names",
			includeDeps:  []string{"danksearch", "dms-greeter"},
			excludeDeps:  []string{"dms-greeter"},
			wantEnabled:  []string{"dux-search"},
			wantDisabled: []string{"dux-greeter", "dux-calendar"},
		},
		{
			name:         "exclude a regular dep",
			excludeDeps:  []string{"waybar"},
			wantDisabled: []string{"dux-greeter", "dux-search", "dux-calendar", "waybar"},
		},
		{
			name:        "include unknown dep returns error",
			includeDeps: []string{"nonexistent"},
			wantErr:     true,
			errContains: "--include-deps",
		},
		{
			name:        "exclude unknown dep returns error",
			excludeDeps: []string{"nonexistent"},
			wantErr:     true,
			errContains: "--exclude-deps",
		},
		{
			name:        "exclude DMS itself is forbidden",
			excludeDeps: []string{"dms (Dux Shell)"},
			wantErr:     true,
			errContains: "cannot exclude required package",
		},
		{
			name:         "include and exclude same dep",
			includeDeps:  []string{"dux-greeter"},
			excludeDeps:  []string{"dux-greeter"},
			wantDisabled: []string{"dux-greeter"},
		},
		{
			name:         "whitespace entries are skipped",
			includeDeps:  []string{"  ", "dux-greeter"},
			wantEnabled:  []string{"dux-greeter"},
			wantDisabled: []string{"dux-search", "dux-calendar"},
		},
		{
			name: "no optional deps present, nothing disabled by default",
			deps: []deps.Dependency{
				{Name: "niri", Status: deps.StatusInstalled, Required: true},
			},
			wantEnabled: []string{"niri"},
		},
		{
			name:         "dux-search flag enables it",
			duxSearch:    true,
			wantEnabled:  []string{"dux-search"},
			wantDisabled: []string{"dux-greeter", "dux-calendar"},
		},
		{
			name:         "dux-calendar flag enables it",
			duxCalendar:  true,
			wantEnabled:  []string{"dux-calendar"},
			wantDisabled: []string{"dux-greeter", "dux-search"},
		},
		{
			name:        "dux-search flag when unavailable errors",
			duxSearch:   true,
			deps:        []deps.Dependency{{Name: "niri", Status: deps.StatusInstalled, Required: true}},
			wantErr:     true,
			errContains: "--dux-search",
		},
		{
			name:        "dux-calendar flag when unavailable errors",
			duxCalendar: true,
			deps:        []deps.Dependency{{Name: "niri", Status: deps.StatusInstalled, Required: true}},
			wantErr:     true,
			errContains: "--dux-calendar",
		},
		{
			name:         "dux-files flag enables it",
			duxFiles:     true,
			wantEnabled:  []string{"dux-files"},
			wantDisabled: []string{"dux-greeter", "dux-search", "dux-calendar"},
		},
		{
			name:        "dux-files flag when unavailable errors",
			duxFiles:    true,
			deps:        []deps.Dependency{{Name: "niri", Status: deps.StatusInstalled, Required: true}},
			wantErr:     true,
			errContains: "--dux-files",
		},
		{
			name:         "dux-greeter flag enables it",
			duxGreeter:   true,
			wantEnabled:  []string{"dux-greeter"},
			wantDisabled: []string{"dux-search", "dux-calendar"},
		},
		{
			name:        "dux-greeter flag when unavailable errors",
			duxGreeter:  true,
			deps:        []deps.Dependency{{Name: "niri", Status: deps.StatusInstalled, Required: true}},
			wantErr:     true,
			errContains: "--dux-greeter",
		},
		{
			name:        "all-features enables every optional dep",
			allFeatures: true,
			wantEnabled: []string{"dux-greeter", "dux-search", "dux-calendar", "niri", "ghostty", "waybar"},
		},
		{
			name:         "all-features with exclude still disables the excluded dep",
			allFeatures:  true,
			excludeDeps:  []string{"dux-calendar"},
			wantEnabled:  []string{"dux-greeter", "dux-search"},
			wantDisabled: []string{"dux-calendar"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			r := NewRunner(Config{
				IncludeDeps: tt.includeDeps,
				ExcludeDeps: tt.excludeDeps,
				DuxSearch:   tt.duxSearch,
				DuxCalendar: tt.duxCalendar,
				DuxFiles:    tt.duxFiles,
				DuxGreeter:  tt.duxGreeter,
				AllFeatures: tt.allFeatures,
			})
			d := tt.deps
			if d == nil {
				d = dependencies
			}
			got, err := r.buildDisabledItems(d)
			if (err != nil) != tt.wantErr {
				t.Fatalf("buildDisabledItems() error = %v, wantErr %v", err, tt.wantErr)
			}
			if tt.wantErr {
				if tt.errContains != "" && !strings.Contains(err.Error(), tt.errContains) {
					t.Errorf("error %q does not contain %q", err.Error(), tt.errContains)
				}
				return
			}
			if got == nil {
				t.Fatal("buildDisabledItems() returned nil map, want non-nil")
			}

			// Check expected disabled items
			for _, name := range tt.wantDisabled {
				if !got[name] {
					t.Errorf("expected %q to be disabled, but it is not", name)
				}
			}

			// Check expected enabled items (should not be in the map or be false)
			for _, name := range tt.wantEnabled {
				if got[name] {
					t.Errorf("expected %q to NOT be disabled, but it is", name)
				}
			}

			// If wantDisabled is empty, the map should have length 0
			if len(tt.wantDisabled) == 0 && len(got) != 0 {
				t.Errorf("expected empty disabledItems map, got %v", got)
			}
		})
	}
}

func TestApplyGitVariants(t *testing.T) {
	freshDeps := func() []deps.Dependency {
		return []deps.Dependency{
			{Name: "niri", Status: deps.StatusInstalled, Variant: deps.VariantStable, CanToggle: true},
			{Name: "quickshell", Status: deps.StatusMissing, Variant: deps.VariantStable, CanToggle: true},
			{Name: "hyprland", Status: deps.StatusInstalled, Variant: deps.VariantGit, CanToggle: true},
			{Name: "dms (Dux Shell)", Status: deps.StatusMissing, Variant: deps.VariantStable, CanToggle: true},
			{Name: "ghostty", Status: deps.StatusInstalled, Variant: deps.VariantStable, CanToggle: false},
		}
	}

	tests := []struct {
		name          string
		gitAll        bool
		gitDeps       []string
		noGitVariant  []string // deps whose git and stable packages resolve identically
		wantErr       bool
		errContains   string
		wantGit       []string
		wantStable    []string
		wantReinstall []string
	}{
		{
			name:       "no git flags leaves variants untouched",
			wantGit:    []string{"hyprland"},
			wantStable: []string{"niri", "quickshell", "dms (Dux Shell)", "ghostty"},
		},
		{
			name:          "git-deps flips only the named deps",
			gitDeps:       []string{"niri", "quickshell"},
			wantGit:       []string{"niri", "quickshell", "hyprland"},
			wantStable:    []string{"dms (Dux Shell)", "ghostty"},
			wantReinstall: []string{"niri"},
		},
		{
			name:          "git-deps matches names case-insensitively and accepts the dms alias",
			gitDeps:       []string{"NIRI", "dms"},
			wantGit:       []string{"niri", "dms (Dux Shell)", "hyprland"},
			wantStable:    []string{"quickshell", "ghostty"},
			wantReinstall: []string{"niri"},
		},
		{
			name:       "empty and whitespace entries are skipped",
			gitDeps:    []string{"", "  "},
			wantGit:    []string{"hyprland"},
			wantStable: []string{"niri", "quickshell", "dms (Dux Shell)", "ghostty"},
		},
		{
			name:        "unknown dep errors",
			gitDeps:     []string{"nonexistent"},
			wantErr:     true,
			errContains: "--git-deps",
		},
		{
			name:        "dep without git variant errors",
			gitDeps:     []string{"ghostty"},
			wantErr:     true,
			errContains: "does not have a git variant",
		},
		{
			name:          "git flips every toggleable dep",
			gitAll:        true,
			wantGit:       []string{"niri", "quickshell", "hyprland", "dms (Dux Shell)"},
			wantStable:    []string{"ghostty"},
			wantReinstall: []string{"niri"},
		},
		{
			name:         "git-deps errors when the distro has no distinct git package",
			gitDeps:      []string{"niri"},
			noGitVariant: []string{"niri"},
			wantErr:      true,
			errContains:  "does not have a git variant",
		},
		{
			name:          "git skips deps without a distinct git package",
			gitAll:        true,
			noGitVariant:  []string{"niri"},
			wantGit:       []string{"quickshell", "hyprland", "dms (Dux Shell)"},
			wantStable:    []string{"niri", "ghostty"},
			wantReinstall: nil,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			r := NewRunner(Config{GitAll: tt.gitAll, GitDeps: tt.gitDeps})
			d := freshDeps()

			hasGitVariant := func(name string) bool {
				for _, n := range tt.noGitVariant {
					if n == name {
						return false
					}
				}
				return true
			}

			reinstall, err := r.applyGitVariants(d, hasGitVariant)
			if (err != nil) != tt.wantErr {
				t.Fatalf("applyGitVariants() error = %v, wantErr %v", err, tt.wantErr)
			}
			if tt.wantErr {
				if tt.errContains != "" && !strings.Contains(err.Error(), tt.errContains) {
					t.Errorf("error %q does not contain %q", err.Error(), tt.errContains)
				}
				return
			}

			variants := make(map[string]deps.PackageVariant)
			for _, dep := range d {
				variants[dep.Name] = dep.Variant
			}
			for _, name := range tt.wantGit {
				if variants[name] != deps.VariantGit {
					t.Errorf("expected %q to be VariantGit", name)
				}
			}
			for _, name := range tt.wantStable {
				if variants[name] != deps.VariantStable {
					t.Errorf("expected %q to stay VariantStable", name)
				}
			}

			if len(reinstall) != len(tt.wantReinstall) {
				t.Errorf("reinstall = %v, want %v", reinstall, tt.wantReinstall)
			}
			for _, name := range tt.wantReinstall {
				if !reinstall[name] {
					t.Errorf("expected %q to be marked for reinstall", name)
				}
			}
		})
	}
}

func TestApplyPrivescTool(t *testing.T) {
	if err := NewRunner(Config{}).applyPrivescTool(); err != nil {
		t.Errorf("empty PrivescTool should be a no-op, got error: %v", err)
	}

	err := NewRunner(Config{PrivescTool: "pkexec"}).applyPrivescTool()
	if err == nil {
		t.Fatal("expected error for unsupported privesc tool, got nil")
	}
	if !strings.Contains(err.Error(), "--privesc") {
		t.Errorf("error %q does not mention --privesc", err.Error())
	}
}

func TestGitDepsDuxFilesPerDistro(t *testing.T) {
	cases := []struct {
		distro  string
		wantPkg string // empty: no git build on this distro
	}{
		{"arch", "dux-files-git"},
		{"fedora", "dux-files-git"},
		{"void", ""},
	}
	for _, tc := range cases {
		t.Run(tc.distro, func(t *testing.T) {
			distro, err := distros.NewDistribution(tc.distro, nil)
			if err != nil {
				t.Fatal(err)
			}
			d := []deps.Dependency{{Name: "dux-files", Status: deps.StatusMissing, CanToggle: true}}
			_, err = NewRunner(Config{GitDeps: []string{"dux-files"}}).applyGitVariants(d, gitVariantChecker(distro, deps.WindowManagerNiri, d))
			if tc.wantPkg == "" {
				if err == nil {
					t.Fatal("expected --git-deps dux-files to be rejected")
				}
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			got := distro.GetPackageMappingWithVariants(deps.WindowManagerNiri, map[string]deps.PackageVariant{"dux-files": d[0].Variant})["dux-files"].Name
			if got != tc.wantPkg {
				t.Errorf("installs %q, want %q", got, tc.wantPkg)
			}
		})
	}
}
