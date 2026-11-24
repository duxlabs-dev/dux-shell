package rfkill

import (
	"github.com/duxlabs-dev/dux-go/ipc"
	"github.com/duxlabs-dev/dux-go/ipc/params"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/models"
)

func HandleRequest(conn *ipc.ConnWriter, req ipc.Request, m *Manager) {
	switch req.Method {
	case "rfkill.getState":
		handleGetState(conn, req, m)
	case "rfkill.setAirplaneMode":
		handleSetAirplaneMode(conn, req, m)
	default:
		conn.RespondError(req.ID, "unknown method: "+req.Method)
	}
}

func handleGetState(conn *ipc.ConnWriter, req ipc.Request, m *Manager) {
	conn.Respond(req.ID, m.GetState())
}

func handleSetAirplaneMode(conn *ipc.ConnWriter, req ipc.Request, m *Manager) {
	enabled, err := params.Bool(req.Params, "enabled")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	if err := m.SetAirplaneMode(enabled); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	conn.Respond(req.ID, models.SuccessResult{Success: true})
}
