package providers

import (
	"os"
	"path/filepath"
	"strings"

	"github.com/duxlabs-dev/dux-shell/core/internal/utils"
	"gopkg.in/yaml.v3"
)

type MiracleConfig struct {
	Terminal               string                  `yaml:"terminal"`
	ActionKey              string                  `yaml:"action_key"`
	DefaultActionOverrides []MiracleActionOverride `yaml:"default_action_overrides"`
	CustomActions          []MiracleCustomAction   `yaml:"custom_actions"`
}

type MiracleActionOverride struct {
	Name      string   `yaml:"name"`
	Action    string   `yaml:"action"`
	Modifiers []string `yaml:"modifiers"`
	Key       string   `yaml:"key"`
}

type MiracleCustomAction struct {
	Command   string   `yaml:"command"`
	Action    string   `yaml:"action"`
	Modifiers []string `yaml:"modifiers"`
	Key       string   `yaml:"key"`
}

type MiracleKeyBinding struct {
	Mods    []string
	Key     string
	Action  string
	Comment string
}

var miracleDefaultBinds = []MiracleKeyBinding{
	{Mods: []string{"Super"}, Key: "Return", Action: "terminal", Comment: "Open terminal"},
	{Mods: []string{"Super"}, Key: "v", Action: "request_vertical", Comment: "Layout windows vertically"},
	{Mods: []string{"Super"}, Key: "h", Action: "request_horizontal", Comment: "Layout windows horizontally"},
	{Mods: []string{"Super"}, Key: "Up", Action: "select_up", Comment: "Select window above"},
	{Mods: []string{"Super"}, Key: "Down", Action: "select_down", Comment: "Select window below"},
	{Mods: []string{"Super"}, Key: "Left", Action: "select_left", Comment: "Select window left"},
	{Mods: []string{"Super"}, Key: "Right", Action: "select_right", Comment: "Select window right"},
	{Mods: []string{"Super", "Shift"}, Key: "Up", Action: "move_up", Comment: "Move window up"},
	{Mods: []string{"Super", "Shift"}, Key: "Down", Action: "move_down", Comment: "Move window down"},
	{Mods: []string{"Super", "Shift"}, Key: "Left", Action: "move_left", Comment: "Move window left"},
	{Mods: []string{"Super", "Shift"}, Key: "Right", Action: "move_right", Comment: "Move window right"},
	{Mods: []string{"Super"}, Key: "r", Action: "toggle_resize", Comment: "Toggle resize mode"},
	{Mods: []string{"Super"}, Key: "f", Action: "fullscreen", Comment: "Toggle fullscreen"},
	{Mods: []string{"Super", "Shift"}, Key: "q", Action: "quit_active_window", Comment: "Close window"},
	{Mods: []string{"Super", "Shift"}, Key: "e", Action: "quit_compositor", Comment: "Exit compositor"},
	{Mods: []string{"Super"}, Key: "Space", Action: "toggle_floating", Comment: "Toggle floating"},
	{Mods: []string{"Super", "Shift"}, Key: "p", Action: "toggle_pinned_to_workspace", Comment: "Toggle pinned to workspace"},
	{Mods: []string{"Super"}, Key: "w", Action: "toggle_tabbing", Comment: "Toggle tabbing layout"},
	{Mods: []string{"Super"}, Key: "s", Action: "toggle_stacking", Comment: "Toggle stacking layout"},
	{Mods: []string{"Super"}, Key: "1", Action: "select_workspace_0", Comment: "Workspace 1"},
	{Mods: []string{"Super"}, Key: "2", Action: "select_workspace_1", Comment: "Workspace 2"},
	{Mods: []string{"Super"}, Key: "3", Action: "select_workspace_2", Comment: "Workspace 3"},
	{Mods: []string{"Super"}, Key: "4", Action: "select_workspace_3", Comment: "Workspace 4"},
	{Mods: []string{"Super"}, Key: "5", Action: "select_workspace_4", Comment: "Workspace 5"},
	{Mods: []string{"Super"}, Key: "6", Action: "select_workspace_5", Comment: "Workspace 6"},
	{Mods: []string{"Super"}, Key: "7", Action: "select_workspace_6", Comment: "Workspace 7"},
	{Mods: []string{"Super"}, Key: "8", Action: "select_workspace_7", Comment: "Workspace 8"},
	{Mods: []string{"Super"}, Key: "9", Action: "select_workspace_8", Comment: "Workspace 9"},
	{Mods: []string{"Super"}, Key: "0", Action: "select_workspace_9", Comment: "Workspace 10"},
	{Mods: []string{"Super", "Shift"}, Key: "1", Action: "move_to_workspace_0", Comment: "Move to workspace 1"},
	{Mods: []string{"Super", "Shift"}, Key: "2", Action: "move_to_workspace_1", Comment: "Move to workspace 2"},
	{Mods: []string{"Super", "Shift"}, Key: "3", Action: "move_to_workspace_2", Comment: "Move to workspace 3"},
	{Mods: []string{"Super", "Shift"}, Key: "4", Action: "move_to_workspace_3", Comment: "Move to workspace 4"},
	{Mods: []string{"Super", "Shift"}, Key: "5", Action: "move_to_workspace_4", Comment: "Move to workspace 5"},
	{Mods: []string{"Super", "Shift"}, Key: "6", Action: "move_to_workspace_5", Comment: "Move to workspace 6"},
	{Mods: []string{"Super", "Shift"}, Key: "7", Action: "move_to_workspace_6", Comment: "Move to workspace 7"},
	{Mods: []string{"Super", "Shift"}, Key: "8", Action: "move_to_workspace_7", Comment: "Move to workspace 8"},
	{Mods: []string{"Super", "Shift"}, Key: "9", Action: "move_to_workspace_8", Comment: "Move to workspace 9"},
	{Mods: []string{"Super", "Shift"}, Key: "0", Action: "move_to_workspace_9", Comment: "Move to workspace 10"},
}

func ParseMiracleConfig(configPath string) (*MiracleConfig, error) {
	expanded, err := utils.ExpandPath(configPath)
	if err != nil {
		return nil, err
	}

	info, err := os.Stat(expanded)
	if err != nil {
		return nil, err
	}

	var configFile string
	if info.IsDir() {
		configFile = filepath.Join(expanded, "config.yaml")
	} else {
		configFile = expanded
	}

	data, err := os.ReadFile(configFile)
	if err != nil {
		return nil, err
	}

	var config MiracleConfig
	if err := yaml.Unmarshal(data, &config); err != nil {
		return nil, err
	}

	return &config, nil
}

func resolveMiracleModifier(mod, actionKey string) string {
	switch mod {
	case "primary":
		return resolveActionKey(actionKey)
	case "alt", "alt_left", "alt_right":
		return "Alt"
	case "shift", "shift_left", "shift_right":
		return "Shift"
	case "ctrl", "ctrl_left", "ctrl_right":
		return "Ctrl"
	case "meta", "meta_left", "meta_right":
		return "Super"
	default:
		return mod
	}
}

func resolveActionKey(actionKey string) string {
	switch actionKey {
	case "meta":
		return "Super"
	case "alt":
		return "Alt"
	case "ctrl":
		return "Ctrl"
	default:
		return "Super"
	}
}

func miracleKeyCodeToName(keyCode string) string {
	name := strings.TrimPrefix(keyCode, "KEY_")
	name = strings.ToLower(name)

	switch name {
	case "enter":
		return "Return"
	case "space":
		return "Space"
	case "up":
		return "Up"
	case "down":
		return "Down"
	case "left":
		return "Left"
	case "right":
		return "Right"
	case "tab":
		return "Tab"
	case "escape", "esc":
		return "Escape"
	case "delete":
		return "Delete"
	case "backspace":
		return "BackSpace"
	case "home":
		return "Home"
	case "end":
		return "End"
	case "pageup":
		return "Page_Up"
	case "pagedown":
		return "Page_Down"
	case "print":
		return "Print"
	case "pause":
		return "Pause"
	case "volumeup":
		return "XF86AudioRaiseVolume"
	case "volumedown":
		return "XF86AudioLowerVolume"
	case "mute":
		return "XF86AudioMute"
	case "micmute":
		return "XF86AudioMicMute"
	case "brightnessup":
		return "XF86MonBrightnessUp"
	case "brightnessdown":
		return "XF86MonBrightnessDown"
	case "kbdillumup":
		return "XF86KbdBrightnessUp"
	case "kbdillumdown":
		return "XF86KbdBrightnessDown"
	case "comma":
		return "comma"
	case "minus":
		return "minus"
	case "equal":
		return "equal"
	}

	if len(name) == 1 {
		return name
	}

	return name
}

func MiracleConfigToBindings(config *MiracleConfig) []MiracleKeyBinding {
	overridden := make(map[string]bool)
	var bindings []MiracleKeyBinding

	for _, override := range config.DefaultActionOverrides {
		mods := make([]string, 0, len(override.Modifiers))
		for _, mod := range override.Modifiers {
			mods = append(mods, resolveMiracleModifier(mod, config.ActionKey))
		}

		bindings = append(bindings, MiracleKeyBinding{
			Mods:    mods,
			Key:     miracleKeyCodeToName(override.Key),
			Action:  override.Name,
			Comment: miracleActionDescription(override.Name),
		})
		overridden[override.Name] = true
	}

	for _, def := range miracleDefaultBinds {
		if overridden[def.Action] {
			continue
		}
		bindings = append(bindings, def)
	}

	for _, custom := range config.CustomActions {
		mods := make([]string, 0, len(custom.Modifiers))
		for _, mod := range custom.Modifiers {
			mods = append(mods, resolveMiracleModifier(mod, config.ActionKey))
		}

		bindings = append(bindings, MiracleKeyBinding{
			Mods:    mods,
			Key:     miracleKeyCodeToName(custom.Key),
			Action:  custom.Command,
			Comment: custom.Command,
		})
	}

	return bindings
}

func miracleActionDescription(action string) string {
	switch action {
	case "terminal":
		return "Open terminal"
	case "request_vertical":
		return "Layout windows vertically"
	case "request_horizontal":
		return "Layout windows horizontally"
	case "select_up":
		return "Select window above"
	case "select_down":
		return "Select window below"
	case "select_left":
		return "Select window left"
	case "select_right":
		return "Select window right"
	case "move_up":
		return "Move window up"
	case "move_down":
		return "Move window down"
	case "move_left":
		return "Move window left"
	case "move_right":
		return "Move window right"
	case "toggle_resize":
		return "Toggle resize mode"
	case "fullscreen":
		return "Toggle fullscreen"
	case "quit_active_window":
		return "Close window"
	case "quit_compositor":
		return "Exit compositor"
	case "toggle_floating":
		return "Toggle floating"
	case "toggle_pinned_to_workspace":
		return "Toggle pinned to workspace"
	case "toggle_tabbing":
		return "Toggle tabbing layout"
	case "toggle_stacking":
		return "Toggle stacking layout"
	case "magnifier_on":
		return "Enable magnifier"
	case "magnifier_off":
		return "Disable magnifier"
	case "magnifier_increase_size":
		return "Increase magnifier area"
	case "magnifier_decrease_size":
		return "Decrease magnifier area"
	case "magnifier_increase_scale":
		return "Increase magnifier scale"
	case "magnifier_decrease_scale":
		return "Decrease magnifier scale"
	}

	if num, ok := strings.CutPrefix(action, "select_workspace_"); ok {
		return "Workspace " + num
	}
	if num, ok := strings.CutPrefix(action, "move_to_workspace_"); ok {
		return "Move to workspace " + num
	}

	return action
}
