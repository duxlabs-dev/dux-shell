package distros

import (
	"github.com/duxlabs-dev/dux-shell/core/internal/deps"
)

// PikaOS carries the whole DMS stack in its own apt repo, so no OBS repos or backports.
func init() {
	Register("pika", "#FFDE34", FamilyDebian, func(config DistroConfig, logChan chan<- string) Distribution {
		return NewDebianDistribution(config, logChan)
	})
}

func (d *DebianDistribution) isPika() bool {
	return d.config.ID == "pika"
}

func (d *DebianDistribution) pikaPackageMapping(wm deps.WindowManager, variants map[string]deps.PackageVariant) map[string]PackageMapping {
	system := func(name string) PackageMapping {
		return PackageMapping{Name: name, Repository: RepoTypeSystem}
	}
	packages := map[string]PackageMapping{
		"git":                    system("git"),
		"kitty":                  system("kitty"),
		"alacritty":              system("alacritty"),
		"ghostty":                system("ghostty"),
		"xdg-desktop-portal-gtk": system("xdg-desktop-portal-gtk"),
		"accountsservice":        system("accountsservice"),
		"dms (Dux Shell)":        variantMapping("dms", variants["dms (Dux Shell)"], RepoTypeSystem, ""),
		"dux-qt-base":            system("libdux-qt-base0"),
		"dux-greeter":            variantMapping("dms-greeter", variants["dux-greeter"], RepoTypeSystem, ""),
		"matugen":                system("matugen"),
		"dux-search":             system("danksearch"),
		"dux-calendar":           variantMapping("dankcalendar", variants["dux-calendar"], RepoTypeSystem, ""),
		"dux-files":              variantMapping("dux-files", variants["dux-files"], RepoTypeSystem, ""),
	}

	switch wm {
	case deps.WindowManagerHyprland:
		packages["hyprland"] = system("hyprland")
		packages["hyprctl"] = system("hyprland")
		packages["jq"] = system("jq")
		// Debian's hyprland-guiutils breaks the hyprland-qtutils PikaOS's hyprland depends on.
		packages["hyprland-guiutils"] = system("hyprland-qtutils")
	case deps.WindowManagerNiri:
		packages["niri"] = variantMapping("niri", variants["niri"], RepoTypeSystem, "")
		packages["xwayland-satellite"] = variantMapping("xwayland-satellite", variants["niri"], RepoTypeSystem, "")
	}

	return packages
}
