package globalshortcuts

import "errors"

var (
	ErrDenied          = errors.New("global shortcuts request denied")
	ErrUnknownApp      = errors.New("app has no global shortcuts")
	ErrUnknownShortcut = errors.New("app has no such global shortcut")
	ErrUnknownPrompt   = errors.New("unknown or expired prompt")
	ErrNoGrabSupport   = errors.New("compositor cannot grab accelerators")
)

type Shortcut struct {
	ID          string `json:"id"`
	Description string `json:"description,omitempty"`
	// Keybind editor key syntax, e.g. Super+Shift+a.
	Triggers  []string `json:"triggers"`
	Preferred []string `json:"preferred,omitempty"`
}

type App struct {
	ID        string     `json:"id"`
	Shortcuts []Shortcut `json:"shortcuts"`
}

type PromptKind string

const (
	PromptBind      PromptKind = "bind"
	PromptConfigure PromptKind = "configure"
)

type Prompt struct {
	Token     string     `json:"token"`
	Kind      PromptKind `json:"kind"`
	AppID     string     `json:"appId"`
	Shortcuts []Shortcut `json:"shortcuts"`
}

type State struct {
	Apps    []App    `json:"apps"`
	Prompts []Prompt `json:"prompts"`
}

type TriggerEdit struct {
	ID       string   `json:"id"`
	Triggers []string `json:"triggers"`
}
