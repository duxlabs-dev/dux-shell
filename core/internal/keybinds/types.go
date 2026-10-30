package keybinds

import (
	"strings"

	"github.com/duxlabs-dev/dux-shell/core/internal/configfrag"
)

type Keybind struct {
	Key             string   `json:"key"`
	Description     string   `json:"desc"`
	Action          string   `json:"action,omitempty"`
	LuaAction       string   `json:"luaAction,omitempty"` // Hyprland: hl.dsp expression for `hyprctl dispatch`
	Subcategory     string   `json:"subcat,omitempty"`
	Source          string   `json:"source,omitempty"`
	HideOnOverlay   bool     `json:"hideOnOverlay,omitempty"`
	CooldownMs      int      `json:"cooldownMs,omitempty"`
	Flags           string   `json:"flags,omitempty"` // Hyprland hl.bind options as letters (e=repeating, l=locked, r=release, o=long_press, ...)
	AllowWhenLocked bool     `json:"allowWhenLocked,omitempty"`
	AllowInhibiting *bool    `json:"allowInhibiting,omitempty"` // nil=default(true), false=explicitly disabled
	Repeat          *bool    `json:"repeat,omitempty"`          // nil=default(true), false=explicitly disabled
	Conflict        *Keybind `json:"conflict,omitempty"`
	HasDefault      bool     `json:"hasDefault,omitempty"` // override has a DMS default to revert to
}

type DMSBindsStatus struct {
	Exists          bool   `json:"exists"`
	Included        bool   `json:"included"`
	IncludePosition int    `json:"includePosition"`
	TotalIncludes   int    `json:"totalIncludes"`
	BindsAfterDMS   int    `json:"bindsAfterDms"`
	Effective       bool   `json:"effective"`
	OverriddenBy    int    `json:"overriddenBy"`
	StatusMessage   string `json:"statusMessage"`
}

const (
	ModSourceConfig  = "config"
	ModSourceRuntime = "runtime"
	ModSourceDefault = "default"
)

// Symbol is the token bind keys use for the main modifier ("Mod" on niri),
// empty when the provider expands it before keys reach the sheet.
type ModKey struct {
	Symbol   string `json:"symbol,omitempty"`
	Resolved string `json:"resolved"`
	Source   string `json:"source"`
}

func DefaultModKey() ModKey {
	return ModKey{Resolved: "Super", Source: ModSourceDefault}
}

func ConfiguredModKey(symbol, value string) ModKey {
	if strings.TrimSpace(value) == "" {
		mod := DefaultModKey()
		mod.Symbol = symbol
		return mod
	}
	return ModKey{Symbol: symbol, Resolved: CanonicalModifier(value), Source: ModSourceConfig}
}

func CanonicalModifier(modifier string) string {
	modifier = strings.TrimSpace(modifier)
	switch strings.ToLower(modifier) {
	case "super", "mod4", "win", "meta", "logo", "mainmod":
		return "Super"
	case "alt", "mod1":
		return "Alt"
	case "ctrl", "control":
		return "Ctrl"
	case "shift":
		return "Shift"
	case "mod3":
		return "Mod3"
	case "mod5":
		return "Mod5"
	}
	return modifier
}

type CheatSheet struct {
	Generation       string               `json:"generation,omitempty"`
	Title            string               `json:"title"`
	Provider         string               `json:"provider"`
	ModKey           string               `json:"modKey,omitempty"`
	Mod              ModKey               `json:"mod"`
	Binds            map[string][]Keybind `json:"binds"`
	DMSBindsIncluded bool                 `json:"dmsBindsIncluded"`
	DMSStatus        *DMSBindsStatus      `json:"dmsStatus,omitempty"`
}

// ModKey stays populated with Mod.Resolved so shells older than the mod field keep working.
func (s *CheatSheet) SetMod(mod ModKey) {
	s.Mod = mod
	s.ModKey = mod.Resolved
}

type Provider interface {
	Name() string
	GetCheatSheet() (*CheatSheet, error)
	ModKey() ModKey
}

type WritableProvider interface {
	Provider
	SetBind(key, action, description string, options map[string]any) error
	// RemoveBind removes the bind. Hyprland writes a negative override to
	// dms/binds-user.lua; single-file providers delete the line.
	RemoveBind(key string) error
	// ResetBind reverts a user override to its DMS default. On single-file
	// providers this aliases to RemoveBind.
	ResetBind(key string) error
	GetOverridePath() string
}

func DMSBindsStatusFrom(s configfrag.Status) *DMSBindsStatus {
	return &DMSBindsStatus{
		Exists:          s.Exists,
		Included:        s.Included,
		IncludePosition: s.IncludePosition,
		TotalIncludes:   s.TotalIncludes,
		BindsAfterDMS:   s.EntriesAfterDMS,
		Effective:       s.Effective,
		OverriddenBy:    s.OverriddenBy,
		StatusMessage:   s.StatusMessage,
	}
}
