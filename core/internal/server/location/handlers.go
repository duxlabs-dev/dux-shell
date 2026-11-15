package location

import (
	"fmt"

	"github.com/duxlabs-dev/dux-go/ipc"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/models"
)

type LocationEvent struct {
	Type string `json:"type"`
	Data State  `json:"data"`
}

func HandleRequest(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	switch req.Method {
	case "location.getState":
		handleGetState(conn, req, manager)
	case "location.subscribe":
		handleSubscribe(conn, req, manager)

	default:
		conn.RespondError(req.ID, fmt.Sprintf("unknown method: %s", req.Method))
	}
}

func handleGetState(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	conn.Respond(req.ID, manager.GetState())
}

func handleSubscribe(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	models.StreamMappedSubscription(conn, req, manager, fmt.Sprintf("client-%p", conn), false, func(s State) LocationEvent {
		return LocationEvent{Type: "state_changed", Data: s}
	})
}
