package tailscale

import (
	"fmt"

	"github.com/duxlabs-dev/dux-go/ipc"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/models"
)

// HandleRequest routes an IPC request to the appropriate handler.
func HandleRequest(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	switch req.Method {
	case "tailscale.getStatus":
		handleGetStatus(conn, req, manager)
	case "tailscale.refresh":
		handleRefresh(conn, req, manager)
	case "tailscale.connect":
		handleConnect(conn, req, manager)
	case "tailscale.disconnect":
		handleDisconnect(conn, req, manager)
	case "tailscale.setExitNode":
		handleSetExitNode(conn, req, manager)
	case "tailscale.setAllowLanAccess":
		handleSetAllowLanAccess(conn, req, manager)
	default:
		conn.RespondError(req.ID, fmt.Sprintf("unknown method: %s", req.Method))
	}
}

func handleGetStatus(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	state := manager.GetState()
	conn.Respond(req.ID, state)
}

func handleRefresh(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	manager.RefreshState()
	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "refreshed"})
}

func handleConnect(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	if err := manager.Connect(); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "connected"})
}

func handleDisconnect(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	if err := manager.Disconnect(); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "disconnected"})
}

func handleSetExitNode(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	id := req.GetOr("id", "")
	if err := manager.SetExitNode(id); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "exit node updated"})
}

func handleSetAllowLanAccess(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	enabled := req.GetOr("enabled", false)
	if err := manager.SetAllowLANAccess(enabled); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "lan access updated"})
}
