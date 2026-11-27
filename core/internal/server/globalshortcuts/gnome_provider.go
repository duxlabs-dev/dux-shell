package globalshortcuts

import (
	"context"
	"fmt"
	"slices"

	"github.com/duxlabs-dev/dux-go/dbusutil"
	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/godbus/dbus/v5"
	"github.com/godbus/dbus/v5/introspect"
)

const (
	gnomeProviderName = "org.gnome.Settings.GlobalShortcutsProvider"
	gnomeProviderPath = dbus.ObjectPath("/org/gnome/Settings/GlobalShortcutsProvider")
	gnomePortalName   = "org.freedesktop.impl.portal.desktop.gnome"
	gnomeRebindPath   = dbus.ObjectPath("/org/gnome/globalshortcuts")
	gnomeRebindMethod = "org.gnome.GlobalShortcutsRebind.RebindShortcuts"
	gnomeShellName    = "org.gnome.Shell"
	gnomeShellPath    = dbus.ObjectPath("/org/gnome/Shell")
	gnomeGrabMethod   = "GrabAccelerators"

	dbusAccessDenied = "org.freedesktop.DBus.Error.AccessDenied"
	dbusInvalidArgs  = "org.freedesktop.DBus.Error.InvalidArgs"
)

type gnomeShortcut struct {
	ID      string
	Options map[string]dbus.Variant
}

// Stands in for the gnome-control-center service xdg-desktop-portal-gnome asks for triggers.
type GnomeProvider struct {
	conn *dbus.Conn
}

type gnomeProviderHandler struct {
	manager *Manager
}

func StartGnomeProvider(manager *Manager) (*GnomeProvider, error) {
	conn, err := dbus.SessionBus()
	if err != nil {
		return nil, fmt.Errorf("connect to session bus: %w", err)
	}

	if !CompositorGrabsAccelerators(conn) {
		return nil, ErrNoGrabSupport
	}

	// Queued, not refused: gnome-control-center's provider is bus activated and exits when idle.
	reply, err := conn.RequestName(gnomeProviderName, 0)
	if err != nil {
		return nil, fmt.Errorf("request %s: %w", gnomeProviderName, err)
	}
	if reply == dbus.RequestNameReplyInQueue {
		log.Infof("%s is owned by another process, taking over when it exits", gnomeProviderName)
	}

	provider := &GnomeProvider{conn: conn}
	if err := conn.Export(&gnomeProviderHandler{manager: manager}, gnomeProviderPath, gnomeProviderName); err != nil {
		provider.Close()
		return nil, fmt.Errorf("export %s: %w", gnomeProviderName, err)
	}
	node := &introspect.Node{
		Name:       string(gnomeProviderPath),
		Interfaces: []introspect.Interface{introspect.IntrospectData, gnomeProviderIntrospection()},
	}
	if err := conn.Export(introspect.NewIntrospectable(node), gnomeProviderPath, "org.freedesktop.DBus.Introspectable"); err != nil {
		log.Warnf("Failed to export introspection for %s: %v", gnomeProviderName, err)
	}

	manager.SetRebinder(provider.rebind)
	return provider, nil
}

// niri 26.04 owns org.gnome.Shell without the accelerator methods the portal backend calls.
func CompositorGrabsAccelerators(conn *dbus.Conn) bool {
	node, err := introspect.Call(conn.Object(gnomeShellName, gnomeShellPath))
	if err != nil {
		return false
	}
	for _, iface := range node.Interfaces {
		if iface.Name != gnomeShellName {
			continue
		}
		return slices.ContainsFunc(iface.Methods, func(method introspect.Method) bool { return method.Name == gnomeGrabMethod })
	}
	return false
}

func (p *GnomeProvider) Close() {
	if _, err := p.conn.ReleaseName(gnomeProviderName); err != nil {
		log.Debugf("Failed to release %s: %v", gnomeProviderName, err)
	}
}

func (p *GnomeProvider) rebind(app App) {
	call := p.conn.Object(gnomePortalName, gnomeRebindPath).Call(gnomeRebindMethod, dbus.FlagNoAutoStart, app.ID, gnomeShortcuts(app.Shortcuts))
	if call.Err != nil {
		log.Debugf("Global shortcuts rebind for %s skipped: %v", app.ID, call.Err)
	}
}

func (h *gnomeProviderHandler) BindShortcuts(appID, _ string, requested []gnomeShortcut) ([]gnomeShortcut, *dbus.Error) {
	if appID == "" {
		return nil, dbus.NewError(dbusInvalidArgs, []any{"app id required"})
	}
	shortcuts, err := h.manager.Bind(context.Background(), appID, requestedShortcuts(requested))
	if err != nil {
		return nil, dbus.NewError(dbusAccessDenied, []any{err.Error()})
	}
	return gnomeShortcuts(shortcuts), nil
}

func (h *gnomeProviderHandler) ConfigureShortcuts(appID, _ string) ([]gnomeShortcut, *dbus.Error) {
	if appID == "" {
		return nil, dbus.NewError(dbusInvalidArgs, []any{"app id required"})
	}
	shortcuts, err := h.manager.Configure(context.Background(), appID)
	if err != nil {
		return nil, dbus.NewError(dbusAccessDenied, []any{err.Error()})
	}
	return gnomeShortcuts(shortcuts), nil
}

func requestedShortcuts(requested []gnomeShortcut) []Shortcut {
	shortcuts := make([]Shortcut, 0, len(requested))
	for _, request := range requested {
		if request.ID == "" {
			continue
		}
		shortcuts = append(shortcuts, Shortcut{
			ID:          request.ID,
			Description: dbusutil.GetOr(request.Options, "description", ""),
			Triggers:    preferredTriggers(request.Options),
		})
	}
	return shortcuts
}

func preferredTriggers(options map[string]dbus.Variant) []string {
	accelerators, isList := dbusutil.Get[[]string](options, "preferred_trigger")
	if !isList {
		accelerators = []string{dbusutil.GetOr(options, "preferred_trigger", "")}
	}

	triggers := make([]string, 0, len(accelerators))
	for _, accelerator := range accelerators {
		trigger := triggerFromGnomeAccelerator(accelerator)
		if trigger == "" {
			continue
		}
		triggers = append(triggers, trigger)
	}
	return triggers
}

func gnomeShortcuts(shortcuts []Shortcut) []gnomeShortcut {
	result := make([]gnomeShortcut, 0, len(shortcuts))
	for _, shortcut := range shortcuts {
		options := map[string]dbus.Variant{
			"shortcuts": dbus.MakeVariant(gnomeAccelerators(shortcut)),
		}
		if shortcut.Description != "" {
			options["description"] = dbus.MakeVariant(shortcut.Description)
		}
		result = append(result, gnomeShortcut{ID: shortcut.ID, Options: options})
	}
	return result
}

func gnomeAccelerators(shortcut Shortcut) []string {
	accelerators := make([]string, 0, len(shortcut.Triggers))
	for _, trigger := range shortcut.Triggers {
		accelerator, expressible := gnomeAccelerator(trigger)
		if !expressible {
			log.Warnf("Global shortcut %s: trigger %q has no GNOME accelerator form", shortcut.ID, trigger)
			continue
		}
		accelerators = append(accelerators, accelerator)
	}
	return accelerators
}

func gnomeProviderIntrospection() introspect.Interface {
	return introspect.Interface{
		Name: gnomeProviderName,
		Methods: []introspect.Method{
			{
				Name: "BindShortcuts",
				Args: []introspect.Arg{
					{Name: "app_id", Type: "s", Direction: "in"},
					{Name: "parent_window", Type: "s", Direction: "in"},
					{Name: "shortcuts", Type: "a(sa{sv})", Direction: "in"},
					{Name: "results", Type: "a(sa{sv})", Direction: "out"},
				},
			},
			{
				Name: "ConfigureShortcuts",
				Args: []introspect.Arg{
					{Name: "app_id", Type: "s", Direction: "in"},
					{Name: "parent_window", Type: "s", Direction: "in"},
					{Name: "results", Type: "a(sa{sv})", Direction: "out"},
				},
			},
		},
	}
}
