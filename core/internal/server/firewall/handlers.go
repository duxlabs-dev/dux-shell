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
		respondAction(conn, req, manager.AddRule(params.StringOpt(req.Params, "zone", ""), ruleSpec(req.Params)))
	case "firewall.updateRule":
		id, err := params.StringNonEmpty(req.Params, "id")
		if err != nil {
			conn.RespondError(req.ID, err.Error())
			return
		}
		respondAction(conn, req, manager.UpdateRule(params.StringOpt(req.Params, "zone", ""), id, ruleSpec(req.Params)))
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
	case "firewall.addZone":
		name, err := params.StringNonEmpty(req.Params, "name")
		if err != nil {
			conn.RespondError(req.ID, err.Error())
			return
		}
		respondAction(conn, req, manager.AddZone(name))
	case "firewall.renameZone":
		name, err := params.StringNonEmpty(req.Params, "name")
		if err != nil {
			conn.RespondError(req.ID, err.Error())
			return
		}
		newName, err := params.StringNonEmpty(req.Params, "newName")
		if err != nil {
			conn.RespondError(req.ID, err.Error())
			return
		}
		respondAction(conn, req, manager.RenameZone(name, newName))
	case "firewall.removeZone":
		name, err := params.StringNonEmpty(req.Params, "name")
		if err != nil {
			conn.RespondError(req.ID, err.Error())
			return
		}
		respondAction(conn, req, manager.RemoveZone(name))
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

func ruleSpec(p map[string]any) RuleSpec {
	return RuleSpec{
		Kind:   params.StringOpt(p, "kind", ""),
		Action: params.StringOpt(p, "action", ""),
		Target: params.StringOpt(p, "target", ""),
		Proto:  params.StringOpt(p, "proto", ""),
		Source: params.StringOpt(p, "source", ""),
		Name:   params.StringOpt(p, "name", ""),
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
