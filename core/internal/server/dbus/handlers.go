package dbus

import (
	"context"
	"fmt"

	"github.com/duxlabs-dev/dux-go/ipc"
	"github.com/duxlabs-dev/dux-go/ipc/params"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/models"
)

type objectParams struct {
	bus   string
	dest  string
	path  string
	iface string
}

func extractObjectParams(p map[string]any, requirePath bool) (objectParams, error) {
	bus, err := params.String(p, "bus")
	if err != nil {
		return objectParams{}, err
	}
	dest, err := params.String(p, "dest")
	if err != nil {
		return objectParams{}, err
	}

	var path string
	if requirePath {
		path, err = params.String(p, "path")
		if err != nil {
			return objectParams{}, err
		}
	} else {
		path = params.StringOpt(p, "path", "/")
	}

	iface, err := params.String(p, "interface")
	if err != nil {
		return objectParams{}, err
	}

	return objectParams{bus: bus, dest: dest, path: path, iface: iface}, nil
}

func HandleRequest(ctx context.Context, conn *ipc.ConnWriter, req ipc.Request, m *Manager, clientID string) {
	switch req.Method {
	case "dbus.call":
		handleCall(conn, req, m)
	case "dbus.getProperty":
		handleGetProperty(conn, req, m)
	case "dbus.setProperty":
		handleSetProperty(conn, req, m)
	case "dbus.getAllProperties":
		handleGetAllProperties(conn, req, m)
	case "dbus.introspect":
		handleIntrospect(conn, req, m)
	case "dbus.listNames":
		handleListNames(conn, req, m)
	case "dbus.subscribe":
		handleSubscribe(ctx, conn, req, m, clientID)
	case "dbus.unsubscribe":
		handleUnsubscribe(conn, req, m)
	default:
		conn.RespondError(req.ID, fmt.Sprintf("unknown method: %s", req.Method))
	}
}

func handleCall(conn *ipc.ConnWriter, req ipc.Request, m *Manager) {
	op, err := extractObjectParams(req.Params, true)
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	method, err := params.String(req.Params, "method")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	var args []any
	if argsRaw, ok := params.Any(req.Params, "args"); ok {
		if argsSlice, ok := argsRaw.([]any); ok {
			args = argsSlice
		}
	}

	result, err := m.Call(op.bus, op.dest, op.path, op.iface, method, args)
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	conn.Respond(req.ID, result)
}

func handleGetProperty(conn *ipc.ConnWriter, req ipc.Request, m *Manager) {
	op, err := extractObjectParams(req.Params, true)
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	property, err := params.String(req.Params, "property")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	result, err := m.GetProperty(op.bus, op.dest, op.path, op.iface, property)
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	conn.Respond(req.ID, result)
}

func handleSetProperty(conn *ipc.ConnWriter, req ipc.Request, m *Manager) {
	op, err := extractObjectParams(req.Params, true)
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	property, err := params.String(req.Params, "property")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	value, ok := params.Any(req.Params, "value")
	if !ok {
		conn.RespondError(req.ID, "missing 'value' parameter")
		return
	}

	if err := m.SetProperty(op.bus, op.dest, op.path, op.iface, property, value); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	conn.Respond(req.ID, models.SuccessResult{Success: true})
}

func handleGetAllProperties(conn *ipc.ConnWriter, req ipc.Request, m *Manager) {
	op, err := extractObjectParams(req.Params, true)
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	result, err := m.GetAllProperties(op.bus, op.dest, op.path, op.iface)
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	conn.Respond(req.ID, result)
}

func handleIntrospect(conn *ipc.ConnWriter, req ipc.Request, m *Manager) {
	bus, err := params.String(req.Params, "bus")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	dest, err := params.String(req.Params, "dest")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	path := params.StringOpt(req.Params, "path", "/")

	result, err := m.Introspect(bus, dest, path)
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	conn.Respond(req.ID, result)
}

func handleListNames(conn *ipc.ConnWriter, req ipc.Request, m *Manager) {
	bus, err := params.String(req.Params, "bus")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	result, err := m.ListNames(bus)
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	conn.Respond(req.ID, result)
}

func handleSubscribe(ctx context.Context, conn *ipc.ConnWriter, req ipc.Request, m *Manager, clientID string) {
	if id := params.StringOpt(req.Params, "clientId", ""); id != "" {
		clientID = id
	}

	bus, err := params.String(req.Params, "bus")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	sender := params.StringOpt(req.Params, "sender", "")
	path := params.StringOpt(req.Params, "path", "")
	iface := params.StringOpt(req.Params, "interface", "")
	member := params.StringOpt(req.Params, "member", "")

	result, err := m.Subscribe(conn, clientID, bus, sender, path, iface, member)
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	m.ReleaseOnClose(ctx, conn)
	conn.Respond(req.ID, result)
}

func handleUnsubscribe(conn *ipc.ConnWriter, req ipc.Request, m *Manager) {
	subID, err := params.String(req.Params, "subscriptionId")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	if err := m.Unsubscribe(subID); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	conn.Respond(req.ID, models.SuccessResult{Success: true})
}
