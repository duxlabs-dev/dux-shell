package evdev

import (
	"github.com/duxlabs-dev/dux-go/ipc"
)

func HandleRequest(conn *ipc.ConnWriter, req ipc.Request, m *Manager) {
	switch req.Method {
	case "evdev.getState":
		handleGetState(conn, req, m)
	default:
		conn.RespondError(req.ID, "unknown method: "+req.Method)
	}
}

func handleGetState(conn *ipc.ConnWriter, req ipc.Request, m *Manager) {
	conn.Respond(req.ID, m.GetState())
}
