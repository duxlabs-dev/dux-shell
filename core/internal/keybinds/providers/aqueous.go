package providers

import (
	"context"
	"errors"
	"fmt"
	"slices"
	"strings"

	"github.com/duxlabs-dev/dux-shell/core/internal/keybinds"
)

type AqueousProvider struct{}

func NewAqueousProvider() *AqueousProvider { return &AqueousProvider{} }
func (*AqueousProvider) Name() string      { return "aqueous" }

func aqueousObjects(snapshot aqueousConfig, key string) []aqueousConfig {
	values, _ := snapshot[key].([]any)
	result := make([]aqueousConfig, 0, len(values))
	for _, value := range values {
		if object, ok := value.(map[string]any); ok {
			result = append(result, aqueousConfig(object))
		}
	}
	return result
}

func AqueousCheatSheet(snapshot aqueousConfig) (*keybinds.CheatSheet, error) {
	if err := requireAqueousCapabilities(snapshot, "keybinds"); err != nil {
		return nil, err
	}
	sheet := &keybinds.CheatSheet{Title: "Aqueous", Provider: "aqueous", Generation: snapshot.String("generation"), DMSBindsIncluded: true, Binds: map[string][]keybinds.Keybind{"Compositor": {}, "Custom": {}}}
	sheet.SetMod(keybinds.DefaultModKey())
	for _, field := range aqueousObjects(snapshot, "fields") {
		if field.String("category") != "keybinds" || field.String("type") != "string_list" {
			continue
		}
		values, _ := field["value"].([]any)
		if len(values) == 0 {
			values = []any{""}
		}
		for _, value := range values {
			key, ok := value.(string)
			if !ok {
				return nil, errors.New("invalid keybinding list")
			}
			sheet.Binds["Compositor"] = append(sheet.Binds["Compositor"], keybinds.Keybind{Key: key, Action: field.String("id"), Description: field.String("label"), Source: "dms"})
		}
	}
	for _, binding := range aqueousObjects(snapshot, "custom_keybinds") {
		sheet.Binds["Custom"] = append(sheet.Binds["Custom"], keybinds.Keybind{Key: binding.String("chord"), Action: "spawn " + binding.String("command"), Description: binding.String("command"), Source: "dms"})
	}
	seen := map[string]keybinds.Keybind{}
	for _, category := range []string{"Compositor", "Custom"} {
		for i, bind := range sheet.Binds[category] {
			if bind.Key == "" {
				continue
			}
			if previous, exists := seen[bind.Key]; exists {
				sheet.Binds[category][i].Conflict = &previous
			}
			seen[bind.Key] = bind
		}
	}
	return sheet, nil
}

func (*AqueousProvider) ModKey() keybinds.ModKey {
	return keybinds.DefaultModKey()
}

func (*AqueousProvider) GetCheatSheet() (*keybinds.CheatSheet, error) {
	snapshot, err := aqueousHelper(context.Background(), "snapshot", nil)
	if err != nil {
		return nil, err
	}
	return AqueousCheatSheet(snapshot)
}

type AqueousBindEdit struct {
	Generation  string
	OriginalKey string
	Key         string
	Action      string
	Remove      bool
}

func AqueousBindRequest(snapshot aqueousConfig, edit AqueousBindEdit) (aqueousConfig, error) {
	if edit.Generation == "" || edit.Generation != snapshot.String("generation") {
		return nil, &AqueousError{Code: "external_change", Message: "reload and reconcile the retained keybind draft"}
	}
	if err := requireAqueousCapabilities(snapshot, "keybinds"); err != nil {
		return nil, err
	}
	if edit.Key == "" {
		return nil, errors.New("missing key")
	}
	original := edit.OriginalKey
	if original == "" {
		original = edit.Key
	}
	originalCount := 0
	for _, field := range aqueousObjects(snapshot, "fields") {
		if field.String("category") != "keybinds" || field.String("type") != "string_list" {
			continue
		}
		values, _ := field["value"].([]any)
		for _, value := range values {
			if value == original {
				originalCount++
			}
		}
	}
	for _, binding := range aqueousObjects(snapshot, "custom_keybinds") {
		if binding.String("chord") == original {
			originalCount++
		}
	}
	if originalCount > 1 {
		return nil, &AqueousError{Code: "ambiguous_target", Message: "multiple bindings use the original shortcut"}
	}
	if originalCount == 0 && (edit.Remove || edit.OriginalKey != "") {
		return nil, &AqueousError{Code: "target_removed", Message: "the original shortcut no longer exists"}
	}
	changes := []any{}
	customChanges := []any{}
	foundAction := false
	for _, field := range aqueousObjects(snapshot, "fields") {
		if field.String("category") != "keybinds" || field.String("type") != "string_list" {
			continue
		}
		old, _ := field["value"].([]any)
		values := make([]any, 0, len(old)+1)
		for _, value := range old {
			if value == original {
				continue
			}
			if !edit.Remove && value == edit.Key && field.String("id") != edit.Action {
				return nil, fmt.Errorf("key conflict: %s", edit.Key)
			}
			values = append(values, value)
		}
		if field.String("id") == edit.Action && !edit.Remove {
			foundAction = true
			if !slices.Contains(values, any(edit.Key)) {
				values = append(values, edit.Key)
			}
		}
		if !slices.Equal(old, values) {
			changes = append(changes, map[string]any{"id": field.String("id"), "value": values})
		}
	}
	for _, binding := range aqueousObjects(snapshot, "custom_keybinds") {
		if binding.String("chord") == original {
			customChanges = append(customChanges, map[string]any{"op": "delete", "id": binding.String("id")})
			continue
		}
		if !edit.Remove && binding.String("chord") == edit.Key {
			return nil, fmt.Errorf("key conflict: %s", edit.Key)
		}
	}
	if !edit.Remove && !foundAction {
		command, ok := strings.CutPrefix(edit.Action, "spawn ")
		if !ok || strings.TrimSpace(command) == "" {
			return nil, errors.New("unknown Aqueous action; custom commands use spawn")
		}
		customChanges = append(customChanges, map[string]any{"op": "add", "chord": edit.Key, "command": command})
	}
	return aqueousConfig{"expected_generation": edit.Generation, "changes": changes, "custom_keybind_changes": customChanges, "create_user_override": true}, nil
}

func (*AqueousProvider) Edit(ctx context.Context, edit AqueousBindEdit) (aqueousConfig, error) {
	snapshot, err := aqueousHelper(ctx, "snapshot", nil)
	if err != nil {
		return nil, err
	}
	request, err := AqueousBindRequest(snapshot, edit)
	if err != nil {
		return nil, err
	}
	return aqueousHelper(ctx, "apply", request)
}
