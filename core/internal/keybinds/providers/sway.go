package providers

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/duxlabs-dev/dux-shell/core/internal/keybinds"
)

type SwayProvider struct {
	configPath string
	isScroll   bool
}

func NewSwayProvider(configPath string) *SwayProvider {
	isScroll := false
	_, scrollEnvSet := os.LookupEnv("SCROLLSOCK")

	if configPath == "" {
		configDir, err := os.UserConfigDir()
		if err != nil {
			configDir = ""
		}
		if scrollEnvSet {
			if configDir != "" {
				configPath = filepath.Join(configDir, "scroll")
			}
			isScroll = true
		} else {
			if configDir != "" {
				configPath = filepath.Join(configDir, "sway")
			}
		}
	} else {
		isScroll = strings.Contains(configPath, "scroll")
	}

	return &SwayProvider{
		configPath: configPath,
		isScroll:   isScroll,
	}
}

func (s *SwayProvider) Name() string {
	if s == nil {
		if os.Getenv("SCROLLSOCK") != "" {
			return "scroll"
		}
		return "sway"
	}

	if s.isScroll {
		return "scroll"
	}
	return "sway"
}

func (s *SwayProvider) GetCheatSheet() (*keybinds.CheatSheet, error) {
	parser := NewSwayParser()
	if err := parser.ReadContent(s.configPath); err != nil {
		return nil, fmt.Errorf("failed to parse sway config: %w", err)
	}

	categorizedBinds := make(map[string][]keybinds.Keybind)
	s.convertSection(parser.ParseKeys(), "", categorizedBinds)

	cheatSheetTitle := "Sway Keybinds"
	if s != nil && s.isScroll {
		cheatSheetTitle = "Scroll Keybinds"
	}

	sheet := &keybinds.CheatSheet{
		Title:    cheatSheetTitle,
		Provider: s.Name(),
		Binds:    categorizedBinds,
	}
	sheet.SetMod(keybinds.ConfiguredModKey("", parser.ModVariable()))
	return sheet, nil
}

func (s *SwayProvider) ModKey() keybinds.ModKey {
	parser := NewSwayParser()
	if err := parser.ReadContent(s.configPath); err != nil {
		return keybinds.DefaultModKey()
	}
	return keybinds.ConfiguredModKey("", parser.ModVariable())
}

func (s *SwayProvider) convertSection(section *SwaySection, subcategory string, categorizedBinds map[string][]keybinds.Keybind) {
	currentSubcat := subcategory
	if section.Name != "" {
		currentSubcat = section.Name
	}

	for _, kb := range section.Keybinds {
		category := s.categorizeByCommand(kb.Command)
		bind := s.convertKeybind(&kb, currentSubcat)
		categorizedBinds[category] = append(categorizedBinds[category], bind)
	}

	for _, child := range section.Children {
		s.convertSection(&child, currentSubcat, categorizedBinds)
	}
}

func (s *SwayProvider) categorizeByCommand(command string) string {
	command = strings.ToLower(command)

	switch {
	case strings.Contains(command, "scratchpad"):
		return "Scratchpad"
	case strings.Contains(command, "workspace") && strings.Contains(command, "output"):
		return "Monitor"
	case strings.Contains(command, "workspace"):
		return "Workspace"
	case strings.Contains(command, "output"):
		return "Monitor"
	case strings.Contains(command, "layout"):
		return "Layout"
	case command == "kill" ||
		command == "fullscreen" || strings.Contains(command, "fullscreen") ||
		command == "floating toggle" || strings.Contains(command, "floating") ||
		strings.Contains(command, "focus") ||
		strings.Contains(command, "move") ||
		strings.Contains(command, "resize") ||
		strings.Contains(command, "split"):
		return "Window"
	case strings.HasPrefix(command, "exec"):
		return "Execute"
	case command == "exit" || command == "reload":
		return "System"
	default:
		return "Other"
	}
}

func (s *SwayProvider) convertKeybind(kb *SwayKeyBinding, subcategory string) keybinds.Keybind {
	key := s.formatKey(kb)
	desc := kb.Comment

	if desc == "" {
		desc = kb.Command
	}

	return keybinds.Keybind{
		Key:         key,
		Description: desc,
		Action:      kb.Command,
		Subcategory: subcategory,
	}
}

func (s *SwayProvider) formatKey(kb *SwayKeyBinding) string {
	parts := make([]string, 0, len(kb.Mods)+1)
	for _, mod := range kb.Mods {
		parts = append(parts, keybinds.CanonicalModifier(mod))
	}
	parts = append(parts, kb.Key)
	return strings.Join(parts, "+")
}
