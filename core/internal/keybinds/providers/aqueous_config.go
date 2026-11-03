package providers

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"slices"

	"github.com/duxlabs-dev/dux-shell/core/internal/utils"
)

func helperResult(ctx context.Context, verb string, input []byte) (aqueousConfig, error) {
	var result aqueousConfig
	args := []string{verb, "--shell", "dms"}
	if input != nil {
		args = append(args, "--request", "-")
	}
	err := utils.RunJSON(ctx, "aqueous-config", args, input, &result)
	if err != nil || !result.Bool("ok") {
		if result.String("code") != "" {
			return result, &AqueousError{Code: result.String("code"), Message: result.String("message")}
		}
		if err != nil {
			if verb == "apply" {
				return result, &AqueousError{Code: "uncertain", Message: err.Error()}
			}
			return result, err
		}
		return result, errors.New("aqueous-config rejected the request")
	}
	return result, nil
}

type AqueousError struct {
	Code    string
	Message string
}

func (e *AqueousError) Error() string { return e.Code + ": " + e.Message }

func requireAqueousCapabilities(result aqueousConfig, required ...string) error {
	if result.Number("protocol") != 1 {
		return errors.New("unsupported aqueous-config protocol")
	}
	values, ok := result["capabilities"].([]any)
	if !ok {
		return errors.New("unsupported aqueous-config: capability discovery required")
	}
	for _, capability := range required {
		if !slices.Contains(values, any(capability)) {
			return fmt.Errorf("unsupported aqueous-config capability: %s", capability)
		}
	}
	return nil
}

func aqueousHelper(ctx context.Context, verb string, request aqueousConfig) (aqueousConfig, error) {
	if verb == "snapshot" {
		result, err := helperResult(ctx, verb, nil)
		if err != nil {
			return result, err
		}
		if err := requireAqueousCapabilities(result, "schema_fields", "shell_dms"); err != nil {
			return result, err
		}
		if result.String("generation") == "" {
			return result, errors.New("missing configuration generation")
		}
		return result, nil
	}
	if verb != "validate" && verb != "apply" {
		return nil, errors.New("unsupported helper operation")
	}
	if request.String("expected_generation") == "" {
		return nil, errors.New("missing expected_generation; reload configuration")
	}
	version, err := helperResult(ctx, "version", nil)
	if err != nil {
		return nil, err
	}
	required := []string{"keybinds", "validate", "stdin_requests", "generation_check", "atomic_file_replace", "shell_dms"}
	if err := requireAqueousCapabilities(version, required...); err != nil {
		return nil, err
	}
	request["protocol"] = 1
	if _, exists := request["backup_dir"]; !exists {
		configDir, err := os.UserConfigDir()
		if err != nil {
			return nil, err
		}
		request["backup_dir"] = filepath.Join(configDir, "dms", "aqueous-backups")
	}
	input, err := json.Marshal(request)
	if err != nil {
		return nil, err
	}
	validated, err := helperResult(ctx, "validate", input)
	if err != nil || verb == "validate" {
		return validated, err
	}
	return helperResult(ctx, "apply", input)
}

type aqueousConfig map[string]any

func (e aqueousConfig) String(key string) string { value, _ := e[key].(string); return value }
func (e aqueousConfig) Bool(key string) bool     { value, _ := e[key].(bool); return value }
func (e aqueousConfig) Number(key string) float64 {
	value, _ := e[key].(json.Number)
	number, _ := value.Float64()
	return number
}
