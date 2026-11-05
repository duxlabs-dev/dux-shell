package fcitx5

import (
	"errors"
	"fmt"
	"slices"
	"strings"

	"github.com/duxlabs-dev/dux-go/dbusutil"
	"github.com/duxlabs-dev/dux-go/ipc"
	"github.com/duxlabs-dev/dux-go/ipc/params"
	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/models"
	"github.com/godbus/dbus/v5"
)

const (
	busName   = "org.fcitx.Fcitx5"
	objPath   = "/controller"
	ifacePref = "org.fcitx.Fcitx.Controller1."
	uriPrefix = "fcitx://config/"
)

type groupItem struct {
	Name   string `json:"name"`
	Layout string `json:"layout"`
}

type inputMethod struct {
	UniqueName   string `json:"uniqueName"`
	Name         string `json:"name"`
	NativeName   string `json:"nativeName"`
	Icon         string `json:"icon"`
	Label        string `json:"label"`
	LanguageCode string `json:"languageCode"`
	Configurable bool   `json:"configurable"`
}

type addon struct {
	UniqueName   string `json:"uniqueName"`
	Name         string `json:"name"`
	Comment      string `json:"comment"`
	Category     int32  `json:"category"`
	Configurable bool   `json:"configurable"`
	Enabled      bool   `json:"enabled"`
}

type layoutVariant struct {
	Name        string   `json:"name"`
	Description string   `json:"description"`
	Languages   []string `json:"languages"`
}

type layout struct {
	Name        string          `json:"name"`
	Description string          `json:"description"`
	Languages   []string        `json:"languages"`
	Variants    []layoutVariant `json:"variants"`
}

func call(method string, args ...any) (*dbus.Call, error) {
	conn, err := dbus.SessionBus()
	if err != nil {
		return nil, fmt.Errorf("session bus unavailable: %w", err)
	}

	c := conn.Object(busName, objPath).Call(ifacePref+method, dbus.FlagNoAutoStart, args...)
	if c.Err != nil {
		return nil, fmt.Errorf("fcitx5 %s: %w", method, c.Err)
	}
	return c, nil
}

func HandleRequest(conn *ipc.ConnWriter, req ipc.Request) {
	result, err := dispatch(req)
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	conn.Respond(req.ID, result)
}

func dispatch(req ipc.Request) (any, error) {
	switch req.Method {
	case "fcitx5.currentIM":
		return currentIM()
	case "fcitx5.getGroups":
		return getGroups()
	case "fcitx5.getGroup":
		return withName(req, getGroup)
	case "fcitx5.setGroup":
		return setGroup(req)
	case "fcitx5.addGroup":
		return withName(req, func(name string) (any, error) { return ok(call("AddInputMethodGroup", name)) })
	case "fcitx5.renameGroup":
		return renameGroup(req)
	case "fcitx5.removeGroup":
		return withName(req, func(name string) (any, error) { return ok(call("RemoveInputMethodGroup", name)) })
	case "fcitx5.availableIMs":
		return availableIMs()
	case "fcitx5.availableLayouts":
		return availableLayouts()
	case "fcitx5.getAddons":
		return getAddons()
	case "fcitx5.setAddonEnabled":
		return setAddonEnabled(req)
	case "fcitx5.getConfig":
		return getConfig(req)
	case "fcitx5.setConfig":
		return setConfig(req)
	default:
		return nil, fmt.Errorf("unknown method: %s", req.Method)
	}
}

func ok(_ *dbus.Call, err error) (any, error) {
	if err != nil {
		return nil, err
	}
	return models.SuccessResult{Success: true}, nil
}

func withName(req ipc.Request, fn func(name string) (any, error)) (any, error) {
	name, err := params.StringNonEmpty(req.Params, "name")
	if err != nil {
		return nil, err
	}
	return fn(name)
}

type rawGroupItem struct{ Name, Layout string }

func groupNames() ([]string, error) {
	c, err := call("InputMethodGroups")
	if err != nil {
		return nil, err
	}
	var names []string
	if err := c.Store(&names); err != nil {
		return nil, err
	}
	if names == nil {
		names = []string{}
	}
	return names, nil
}

func currentGroup() (string, error) {
	c, err := call("CurrentInputMethodGroup")
	if err != nil {
		return "", err
	}
	var cur string
	err = c.Store(&cur)
	return cur, err
}

func groupInfo(name string) (string, []rawGroupItem, error) {
	c, err := call("InputMethodGroupInfo", name)
	if err != nil {
		return "", nil, err
	}
	var defaultLayout string
	var items []rawGroupItem
	err = c.Store(&defaultLayout, &items)
	return defaultLayout, items, err
}

func currentIM() (any, error) {
	c, err := call("CurrentInputMethod")
	if err != nil {
		return nil, err
	}
	var name string
	if err := c.Store(&name); err != nil {
		return nil, err
	}
	return map[string]any{"name": name}, nil
}

func getGroups() (any, error) {
	names, err := groupNames()
	if err != nil {
		return nil, err
	}
	cur, err := currentGroup()
	if err != nil {
		return nil, err
	}
	return map[string]any{"groups": names, "current": cur}, nil
}

func getGroup(name string) (any, error) {
	defaultLayout, raw, err := groupInfo(name)
	if err != nil {
		return nil, err
	}
	items := make([]groupItem, 0, len(raw))
	for _, r := range raw {
		items = append(items, groupItem(r))
	}
	return map[string]any{"name": name, "defaultLayout": defaultLayout, "items": items}, nil
}

func setGroup(req ipc.Request) (any, error) {
	name, err := params.StringNonEmpty(req.Params, "name")
	if err != nil {
		return nil, err
	}
	defaultLayout := params.StringOpt(req.Params, "defaultLayout", "")
	list, err := params.Get[[]any](req.Params, "items")
	if err != nil {
		return nil, err
	}
	items := make([]rawGroupItem, 0, len(list))
	for _, e := range list {
		m, isMap := e.(map[string]any)
		if !isMap {
			return nil, errors.New("items must be objects")
		}
		imName, err := params.StringNonEmpty(m, "name")
		if err != nil {
			return nil, err
		}
		items = append(items, rawGroupItem{imName, params.StringOpt(m, "layout", "")})
	}
	return ok(call("SetInputMethodGroupInfo", name, defaultLayout, items))
}

// fcitx5 has no rename call: copy the group under the new name, move the active selection, drop the old one.
func renameGroup(req ipc.Request) (any, error) {
	name, err := params.StringNonEmpty(req.Params, "name")
	if err != nil {
		return nil, err
	}
	newName, err := params.StringNonEmpty(req.Params, "newName")
	if err != nil {
		return nil, err
	}
	newName = strings.TrimSpace(newName)
	if newName == "" || newName == name {
		return nil, errors.New("pick a different name")
	}
	names, err := groupNames()
	if err != nil {
		return nil, err
	}
	if slices.Contains(names, newName) {
		return nil, fmt.Errorf("a group named %q already exists", newName)
	}
	defaultLayout, items, err := groupInfo(name)
	if err != nil {
		return nil, err
	}
	cur, err := currentGroup()
	if err != nil {
		return nil, err
	}
	if _, err := call("AddInputMethodGroup", newName); err != nil {
		return nil, err
	}
	if _, err := call("SetInputMethodGroupInfo", newName, defaultLayout, items); err != nil {
		return nil, rollbackRename(name, newName, err)
	}
	if cur == name {
		if _, err := call("SwitchInputMethodGroup", newName); err != nil {
			return nil, rollbackRename(name, newName, err)
		}
	}
	return ok(call("RemoveInputMethodGroup", name))
}

func rollbackRename(name, newName string, cause error) error {
	log.Warnf("Fcitx5: rename of %q aborted, removing copy %q: %v", name, newName, cause)
	if _, err := call("RemoveInputMethodGroup", newName); err != nil {
		log.Warnf("Fcitx5: could not remove copy %q: %v", newName, err)
	}
	return cause
}

func availableIMs() (any, error) {
	c, err := call("AvailableInputMethods")
	if err != nil {
		return nil, err
	}
	var raw []struct {
		UniqueName, Name, NativeName, Icon, Label, LanguageCode string
		Configurable                                            bool
	}
	if err := c.Store(&raw); err != nil {
		return nil, err
	}
	out := make([]inputMethod, 0, len(raw))
	for _, r := range raw {
		out = append(out, inputMethod(r))
	}
	return map[string]any{"inputMethods": out}, nil
}

func availableLayouts() (any, error) {
	c, err := call("AvailableKeyboardLayouts")
	if err != nil {
		return nil, err
	}
	var raw []struct {
		Name, Description string
		Languages         []string
		Variants          []struct {
			Name, Description string
			Languages         []string
		}
	}
	if err := c.Store(&raw); err != nil {
		return nil, err
	}
	out := make([]layout, 0, len(raw))
	for _, r := range raw {
		l := layout{Name: r.Name, Description: r.Description, Languages: r.Languages, Variants: make([]layoutVariant, 0, len(r.Variants))}
		for _, v := range r.Variants {
			l.Variants = append(l.Variants, layoutVariant(v))
		}
		out = append(out, l)
	}
	return map[string]any{"layouts": out}, nil
}

func configURI(req ipc.Request) (string, error) {
	uri, err := params.StringNonEmpty(req.Params, "uri")
	if err != nil {
		return "", err
	}
	if !strings.HasPrefix(uri, uriPrefix) {
		return "", fmt.Errorf("uri must start with %s", uriPrefix)
	}
	return uri, nil
}

func fetchConfig(uri string) (map[string]any, Schema, error) {
	c, err := call("GetConfig", uri)
	if err != nil {
		return nil, Schema{}, err
	}
	var value dbus.Variant
	var raw []rawStruct
	if err := c.Store(&value, &raw); err != nil {
		return nil, Schema{}, err
	}
	schema := buildSchema(raw)
	typed, _ := toTyped(dbusutil.Normalize(value), schema.Root, structIndex(schema.Structs)).(map[string]any)
	return typed, schema, nil
}

func getConfig(req ipc.Request) (any, error) {
	uri, err := configURI(req)
	if err != nil {
		return nil, err
	}
	value, schema, err := fetchConfig(uri)
	if err != nil {
		return nil, err
	}
	return map[string]any{"value": value, "schema": schema}, nil
}

// send the full tree, fcitx5 addons do not merge partial configs
func setConfig(req ipc.Request) (any, error) {
	uri, err := configURI(req)
	if err != nil {
		return nil, err
	}
	value, isMap := params.AnyMap(req.Params, "value")
	if !isMap {
		return nil, errors.New("value must be an object")
	}
	live, schema, err := fetchConfig(uri)
	if err != nil {
		return nil, err
	}
	structs := structIndex(schema.Structs)
	payload := fromTyped(keepHidden(value, live, schema.Root, structs), schema.Root, structs)
	log.Infof("Fcitx5: applying config %s", uri)
	return ok(call("SetConfig", uri, payload))
}

func getAddons() (any, error) {
	c, err := call("GetAddonsV2")
	if err != nil {
		return nil, err
	}
	var raw []struct {
		UniqueName, Name, Comment string
		Category                  int32
		Configurable, Enabled     bool
		OnDemand                  bool
		Dependencies, Optional    []string
	}
	if err := c.Store(&raw); err != nil {
		return nil, err
	}
	out := make([]addon, 0, len(raw))
	for _, r := range raw {
		out = append(out, addon{r.UniqueName, r.Name, r.Comment, r.Category, r.Configurable, r.Enabled})
	}
	return map[string]any{"addons": out}, nil
}

func setAddonEnabled(req ipc.Request) (any, error) {
	name, err := params.StringNonEmpty(req.Params, "name")
	if err != nil {
		return nil, err
	}
	enabled, err := params.Bool(req.Params, "enabled")
	if err != nil {
		return nil, err
	}
	state := []struct {
		Name    string
		Enabled bool
	}{{name, enabled}}
	log.Infof("Fcitx5: addon %s enabled=%t", name, enabled)
	return ok(call("SetAddonsState", state))
}
