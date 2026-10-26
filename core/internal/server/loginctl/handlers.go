package loginctl

import (
	"fmt"

	"github.com/duxlabs-dev/dux-go/ipc"
	"github.com/duxlabs-dev/dux-go/ipc/params"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/models"
)

func HandleRequest(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	switch req.Method {
	case "loginctl.getState":
		handleGetState(conn, req, manager)
	case "loginctl.lock":
		handleLock(conn, req, manager)
	case "loginctl.unlock":
		handleUnlock(conn, req, manager)
	case "loginctl.activate":
		handleActivate(conn, req, manager)
	case "loginctl.setIdleHint":
		handleSetIdleHint(conn, req, manager)
	case "loginctl.setLockedHint":
		handleSetLockedHint(conn, req, manager)
	case "loginctl.setLockBeforeSuspend":
		handleSetLockBeforeSuspend(conn, req, manager)
	case "loginctl.setSleepInhibitorEnabled":
		handleSetSleepInhibitorEnabled(conn, req, manager)
	case "loginctl.setKeepAwake":
		handleSetKeepAwake(conn, req, manager)
	case "loginctl.lockerReady":
		handleLockerReady(conn, req, manager)
	case "loginctl.terminate":
		handleTerminate(conn, req, manager)
	case "loginctl.subscribe":
		handleSubscribe(conn, req, manager)
	default:
		conn.RespondError(req.ID, fmt.Sprintf("unknown method: %s", req.Method))
	}
}

func handleGetState(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	conn.Respond(req.ID, manager.GetState())
}

func handleLock(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	if err := manager.Lock(); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "locked"})
}

func handleUnlock(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	if err := manager.Unlock(); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "unlocked"})
}

func handleActivate(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	if err := manager.Activate(); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "activated"})
}

func handleSetIdleHint(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	idle, err := params.Bool(req.Params, "idle")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	if err := manager.SetIdleHint(idle); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "idle hint set"})
}

func handleSetLockedHint(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	locked, err := params.Bool(req.Params, "locked")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	if err := manager.SetLockedHint(locked); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "locked hint set"})
}

func handleSetLockBeforeSuspend(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	enabled, err := params.Bool(req.Params, "enabled")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	manager.SetLockBeforeSuspend(enabled)
	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "lock before suspend set"})
}

func handleSetSleepInhibitorEnabled(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	enabled, err := params.Bool(req.Params, "enabled")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	manager.SetSleepInhibitorEnabled(enabled)
	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "sleep inhibitor setting updated"})
}

func handleSetKeepAwake(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	enabled, err := params.Bool(req.Params, "enabled")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	if err := manager.SetKeepAwake(enabled); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "keep awake set"})
}

func handleLockerReady(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	manager.markLockerReady()
	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "ok"})
}

func handleTerminate(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	if err := manager.Terminate(); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "terminated"})
}

func handleSubscribe(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	clientID := fmt.Sprintf("client-%p", conn)
	stateChan := manager.Subscribe(clientID)
	defer manager.Unsubscribe(clientID)

	initialState := manager.GetState()
	event := SessionEvent{
		Type: EventStateChanged,
		Data: initialState,
	}
	if err := conn.WriteResponse(ipc.Response[SessionEvent]{
		ID:     req.ID,
		Result: &event,
	}); err != nil {
		return
	}

	for state := range stateChan {
		event := SessionEvent{
			Type: EventStateChanged,
			Data: state,
		}
		if err := conn.WriteResponse(ipc.Response[SessionEvent]{
			Result: &event,
		}); err != nil {
			return
		}
	}
}
