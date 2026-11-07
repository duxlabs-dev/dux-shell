package firewall

import (
	"errors"
	"fmt"

	"github.com/duxlabs-dev/dux-go/ipc"
	"github.com/duxlabs-dev/dux-go/ipc/params"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/models"
)

func HandleRequest(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	switch req.Method {
	case "firewall.getState":
		conn.Respond(req.ID, manager.GetState())
	case "firewall.unlock":
		respondAction(conn, req, manager.Unlock())
	case "firewall.addRule":
		spec := RuleSpec{
			Kind:   params.StringOpt(req.Params, "kind", ""),
			Action: params.StringOpt(req.Params, "action", ""),
			Target: params.StringOpt(req.Params, "target", ""),
			Proto:  params.StringOpt(req.Params, "proto", ""),
			Source: params.StringOpt(req.Params, "source", ""),
		}
		respondAction(conn, req, manager.AddRule(params.StringOpt(req.Params, "zone", ""), spec))
	case "firewall.removeRule":
		id, err := params.StringNonEmpty(req.Params, "id")
		if err != nil {
			conn.RespondError(req.ID, err.Error())
			return
		}
		respondAction(conn, req, manager.RemoveRule(params.StringOpt(req.Params, "zone", ""), id))
	case "firewall.setDefaults":
		respondAction(conn, req, manager.SetDefaults(DefaultsChange{
			Zone:     params.StringOpt(req.Params, "zone", ""),
			Incoming: params.StringOpt(req.Params, "incoming", ""),
			Outgoing: params.StringOpt(req.Params, "outgoing", ""),
		}))
	case "firewall.setInterfaceZone":
		iface, err := params.StringNonEmpty(req.Params, "interface")
		if err != nil {
			conn.RespondError(req.ID, err.Error())
			return
		}
		zone, err := params.StringNonEmpty(req.Params, "zone")
		if err != nil {
			conn.RespondError(req.ID, err.Error())
			return
		}
		respondAction(conn, req, manager.SetInterfaceZone(iface, zone))
	case "firewall.listServices":
		services, err := manager.ListServices()
		if err != nil {
			conn.RespondError(req.ID, err.Error())
			return
		}
		conn.Respond(req.ID, services)
	default:
		conn.RespondError(req.ID, fmt.Sprintf("unknown method: %s", req.Method))
	}
}

func respondAction(conn *ipc.ConnWriter, req ipc.Request, err error) {
	if errors.Is(err, ErrAuthDismissed) {
		conn.Respond(req.ID, models.SuccessResult{Success: false, Message: "dismissed"})
		return
	}
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "ok"})
}
