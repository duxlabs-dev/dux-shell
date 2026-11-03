package location

import (
	"fmt"

	"github.com/duxlabs-dev/dux-go/ipc"
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
	clientID := fmt.Sprintf("client-%p", conn)
	stateChan := manager.Subscribe(clientID)
	defer manager.Unsubscribe(clientID)

	initialState := manager.GetState()
	event := LocationEvent{
		Type: "state_changed",
		Data: initialState,
	}

	if err := conn.WriteResponse(ipc.Response[LocationEvent]{
		ID:     req.ID,
		Result: &event,
	}); err != nil {
		return
	}

	for state := range stateChan {
		event := LocationEvent{
			Type: "state_changed",
			Data: state,
		}
		if err := conn.WriteResponse(ipc.Response[LocationEvent]{
			Result: &event,
		}); err != nil {
			return
		}
	}
}
