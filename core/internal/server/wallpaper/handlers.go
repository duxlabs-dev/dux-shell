package wallpaper

import (
	"encoding/json"
	"fmt"

	"github.com/duxlabs-dev/dux-go/ipc"
	"github.com/duxlabs-dev/dux-go/ipc/params"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/models"
)

func HandleRequest(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	if manager == nil {
		conn.RespondError(req.ID, "wallpaper manager not initialized")
		return
	}

	switch req.Method {
	case "wallpaper.getState":
		handleGetState(conn, req, manager)
	case "wallpaper.setConfig":
		handleSetConfig(conn, req, manager)
	case "wallpaper.trigger":
		handleTrigger(conn, req, manager)
	case "wallpaper.subscribe":
		handleSubscribe(conn, req, manager)
	default:
		conn.RespondError(req.ID, fmt.Sprintf("unknown method: %s", req.Method))
	}
}

func handleGetState(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	conn.Respond(req.ID, manager.GetState())
}

func handleSetConfig(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	raw, ok := params.Any(req.Params, "config")
	if !ok {
		conn.RespondError(req.ID, "missing or invalid 'config' parameter")
		return
	}

	data, err := json.Marshal(raw)
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	var config Config
	if err := json.Unmarshal(data, &config); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	manager.SetConfig(config)
	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "wallpaper schedule set"})
}

func handleTrigger(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	manager.ResetSchedule(params.StringOpt(req.Params, "target", ""))
	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "wallpaper schedule reset"})
}

func handleSubscribe(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	clientID := fmt.Sprintf("client-%p", conn)
	stateChan := manager.Subscribe(clientID)
	defer manager.Unsubscribe(clientID)

	initialState := manager.GetState()
	if err := conn.WriteResponse(ipc.Response[State]{
		ID:     req.ID,
		Result: &initialState,
	}); err != nil {
		return
	}

	for state := range stateChan {
		if err := conn.WriteResponse(ipc.Response[State]{
			Result: &state,
		}); err != nil {
			return
		}
	}
}
