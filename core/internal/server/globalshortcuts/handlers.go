package globalshortcuts

import (
	"encoding/json"
	"fmt"

	"github.com/duxlabs-dev/dux-go/ipc"
	"github.com/duxlabs-dev/dux-go/ipc/params"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/models"
)

func HandleRequest(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	switch req.Method {
	case "globalshortcuts.getState":
		conn.Respond(req.ID, manager.GetState())
	case "globalshortcuts.submit":
		handleSubmit(conn, req, manager)
	case "globalshortcuts.cancel":
		handleCancel(conn, req, manager)
	case "globalshortcuts.setTriggers":
		handleSetTriggers(conn, req, manager)
	case "globalshortcuts.remove":
		handleRemove(conn, req, manager)
	default:
		conn.RespondError(req.ID, fmt.Sprintf("unknown method: %s", req.Method))
	}
}

func handleSubmit(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	token, err := params.StringNonEmpty(req.Params, "token")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	edits, err := triggerEdits(req)
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	if err := manager.Submit(token, edits); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "global shortcuts saved"})
}

func handleCancel(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	token, err := params.StringNonEmpty(req.Params, "token")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	if err := manager.Cancel(token); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "global shortcuts request denied"})
}

func handleSetTriggers(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	appID, err := params.StringNonEmpty(req.Params, "appId")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	shortcutID, err := params.StringNonEmpty(req.Params, "id")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	if err := manager.SetTriggers(appID, shortcutID, params.StringSlice(req.Params, "triggers")); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "global shortcut saved"})
}

func handleRemove(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	appID, err := params.StringNonEmpty(req.Params, "appId")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	if err := manager.Remove(appID); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "global shortcuts removed"})
}

func triggerEdits(req ipc.Request) ([]TriggerEdit, error) {
	raw, ok := params.Any(req.Params, "shortcuts")
	if !ok {
		return nil, fmt.Errorf("missing shortcuts parameter")
	}
	encoded, err := json.Marshal(raw)
	if err != nil {
		return nil, err
	}
	var edits []TriggerEdit
	if err := json.Unmarshal(encoded, &edits); err != nil {
		return nil, fmt.Errorf("invalid shortcuts parameter: %w", err)
	}
	return edits, nil
}
