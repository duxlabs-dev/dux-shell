package providers

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"testing"

	"github.com/duxlabs-dev/dux-shell/core/internal/utils"
)

func aqueousFixture(t *testing.T) aqueousConfig {
	t.Helper()
	var snapshot aqueousConfig
	err := utils.DecodeJSON([]byte(`{"ok":true,"protocol":1,"generation":"abc","capabilities":["keybinds"],"fields":[{"id":"spawn_terminal","category":"keybinds","type":"string_list","label":"Terminal","value":["Super+Return","Super+T"]},{"id":"close","category":"keybinds","type":"string_list","label":"Close","value":[]}],"custom_keybinds":[{"id":"custom:12","chord":"Super+R","command":"printf 'hello; $world'"}]}`), &snapshot)
	if err != nil {
		t.Fatal(err)
	}
	return snapshot
}

func TestAqueousCheatsheetIncludesUnboundAndCustom(t *testing.T) {
	sheet, err := AqueousCheatSheet(aqueousFixture(t))
	if err != nil {
		t.Fatal(err)
	}
	if sheet.Generation != "abc" || len(sheet.Binds["Compositor"]) != 3 {
		t.Fatal("lost generation or multiple bindings")
	}
	if sheet.Binds["Compositor"][2].Key != "" || sheet.Binds["Compositor"][2].Action != "close" {
		t.Fatal("unbound action lost")
	}
	if sheet.Binds["Custom"][0].Action != "spawn printf 'hello; $world'" {
		t.Fatal("custom command modified")
	}
}

func TestAqueousBindingReplacementIsOneRequest(t *testing.T) {
	snapshot := aqueousFixture(t)
	request, err := AqueousBindRequest(snapshot, AqueousBindEdit{Generation: "abc", OriginalKey: "Super+Return", Key: "Super+Enter", Action: "spawn_terminal"})
	if err != nil {
		t.Fatal(err)
	}
	data, _ := json.Marshal(request["changes"])
	if string(data) != `[{"id":"spawn_terminal","value":["Super+T","Super+Enter"]}]` {
		t.Fatalf("wrong atomic replacement: %s", data)
	}
	if request["expected_generation"] != "abc" {
		t.Fatal("generation replaced")
	}
	if !reflect.DeepEqual(snapshot, aqueousFixture(t)) {
		t.Fatal("draft mutated snapshot")
	}
}

func TestAqueousBindingConflictAndRemove(t *testing.T) {
	for _, edit := range []AqueousBindEdit{
		{Generation: "abc", OriginalKey: "Super+Return", Key: "Super+R", Action: "close"},
		{Generation: "abc", Key: "Super+Q", Action: "invented_action"},
	} {
		if _, err := AqueousBindRequest(aqueousFixture(t), edit); err == nil {
			t.Fatal("invalid edit accepted")
		}
	}
	request, err := AqueousBindRequest(aqueousFixture(t), AqueousBindEdit{Generation: "abc", Key: "Super+R", Remove: true})
	if err != nil {
		t.Fatal(err)
	}
	data, _ := json.Marshal(request["custom_keybind_changes"])
	if string(data) != `[{"id":"custom:12","op":"delete"}]` {
		t.Fatalf("wrong removal: %s", data)
	}
}

func TestAqueousGenerationConflictCode(t *testing.T) {
	for _, generation := range []string{"", "stale"} {
		_, err := AqueousBindRequest(aqueousFixture(t), AqueousBindEdit{Generation: generation, Key: "Super+R", Remove: true})
		var conflict *AqueousError
		if !errors.As(err, &conflict) || conflict.Code != "external_change" {
			t.Fatalf("expected structured generation conflict, got %v", err)
		}
	}
}

func TestAqueousBindingRequiresUniqueOriginal(t *testing.T) {
	for _, edit := range []AqueousBindEdit{
		{Generation: "abc", Key: "Super+Missing", Remove: true},
		{Generation: "abc", OriginalKey: "Super+Missing", Key: "Super+X", Action: "spawn_terminal"},
	} {
		_, err := AqueousBindRequest(aqueousFixture(t), edit)
		var conflict *AqueousError
		if !errors.As(err, &conflict) || conflict.Code != "target_removed" {
			t.Fatalf("expected missing original, got %v", err)
		}
	}
	snapshot := aqueousFixture(t)
	snapshot["custom_keybinds"] = append(snapshot["custom_keybinds"].([]any), map[string]any{"id": "duplicate", "chord": "Super+T", "command": "echo duplicate"})
	_, err := AqueousBindRequest(snapshot, AqueousBindEdit{Generation: "abc", Key: "Super+T", Remove: true})
	var conflict *AqueousError
	if !errors.As(err, &conflict) || conflict.Code != "ambiguous_target" {
		t.Fatalf("expected ambiguous original, got %v", err)
	}
}

func TestAqueousHelperFailureCodes(t *testing.T) {
	for _, tc := range []struct {
		name   string
		script string
		code   string
	}{
		{"conflict", `printf '%s' '{"ok":false,"code":"external_change","message":"changed"}'; exit 1`, "external_change"},
		{"missing_ack", "exit 0", "uncertain"},
		{"failed_process", "exit 1", "uncertain"},
		{"malformed_ack", "printf '{'", "uncertain"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			dir := t.TempDir()
			if err := os.WriteFile(filepath.Join(dir, "aqueous-config"), []byte("#!/bin/sh\n"+tc.script+"\n"), 0o755); err != nil {
				t.Fatal(err)
			}
			t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
			_, err := helperResult(context.Background(), "apply", nil)
			var failure *AqueousError
			if !errors.As(err, &failure) || failure.Code != tc.code {
				t.Fatalf("expected %s, got %v", tc.code, err)
			}
		})
	}
}
