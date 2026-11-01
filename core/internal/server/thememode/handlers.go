package thememode

import (
	"fmt"

	"github.com/duxlabs-dev/dux-go/ipc"
	"github.com/duxlabs-dev/dux-go/ipc/params"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/models"
)

func HandleRequest(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	if manager == nil {
		conn.RespondError(req.ID, "theme mode manager not initialized")
		return
	}

	switch req.Method {
	case "theme.auto.getState":
		handleGetState(conn, req, manager)
	case "theme.auto.setEnabled":
		handleSetEnabled(conn, req, manager)
	case "theme.auto.setMode":
		handleSetMode(conn, req, manager)
	case "theme.auto.setSchedule":
		handleSetSchedule(conn, req, manager)
	case "theme.auto.setLocation":
		handleSetLocation(conn, req, manager)
	case "theme.auto.setUseIPLocation":
		handleSetUseIPLocation(conn, req, manager)
	case "theme.auto.trigger":
		handleTrigger(conn, req, manager)
	case "theme.auto.subscribe":
		handleSubscribe(conn, req, manager)
	default:
		conn.RespondError(req.ID, fmt.Sprintf("unknown method: %s", req.Method))
	}
}

func handleGetState(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	conn.Respond(req.ID, manager.GetState())
}

func handleSetEnabled(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	enabled, err := params.Bool(req.Params, "enabled")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	manager.SetEnabled(enabled)
	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "theme auto enabled set"})
}

func handleSetMode(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	mode, err := params.String(req.Params, "mode")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	if mode != "time" && mode != "location" {
		conn.RespondError(req.ID, "invalid mode")
		return
	}

	manager.SetMode(mode)
	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "theme auto mode set"})
}

func handleSetSchedule(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	startHour, err := params.Int(req.Params, "startHour")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	startMinute, err := params.Int(req.Params, "startMinute")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	endHour, err := params.Int(req.Params, "endHour")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	endMinute, err := params.Int(req.Params, "endMinute")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	if err := manager.ValidateSchedule(startHour, startMinute, endHour, endMinute); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	manager.SetSchedule(startHour, startMinute, endHour, endMinute)
	conn.Respond(req.ID, manager.GetState())
}

func handleSetLocation(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	lat, err := params.Float(req.Params, "latitude")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	lon, err := params.Float(req.Params, "longitude")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	manager.SetLocation(lat, lon)
	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "theme auto location set"})
}

func handleSetUseIPLocation(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	use, err := params.Bool(req.Params, "use")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	manager.SetUseIPLocation(use)
	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "theme auto IP location set"})
}

func handleTrigger(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	manager.TriggerUpdate()
	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "theme auto update triggered"})
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
