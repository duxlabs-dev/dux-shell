package models

import "github.com/duxlabs-dev/dux-go/ipc"

type Subscriber[S any] interface {
	Subscribe(id string) chan S
	Unsubscribe(id string, ch chan S)
	GetState() S
}

// StreamSubscription subscribes to mgr, sends the initial state with req.ID,
// and streams subsequent updates until the channel closes or a write fails.
func StreamSubscription[S any](conn *ipc.ConnWriter, req ipc.Request, mgr Subscriber[S], clientID string, includeID bool) {
	StreamMappedSubscription(conn, req, mgr, clientID, includeID, func(s S) S { return s })
}

// StreamMappedSubscription is like StreamSubscription, transforming each state
// snapshot with mapFn before writing it to the connection.
func StreamMappedSubscription[S, E any](conn *ipc.ConnWriter, req ipc.Request, mgr Subscriber[S], clientID string, includeID bool, mapFn func(S) E) {
	ch := mgr.Subscribe(clientID)
	defer mgr.Unsubscribe(clientID, ch)

	initial := mapFn(mgr.GetState())
	if err := conn.WriteResponse(ipc.Response[E]{
		ID:     req.ID,
		Result: &initial,
	}); err != nil {
		return
	}

	var streamID int
	if includeID {
		streamID = req.ID
	}
	for state := range ch {
		event := mapFn(state)
		if err := conn.WriteResponse(ipc.Response[E]{
			ID:     streamID,
			Result: &event,
		}); err != nil {
			return
		}
	}
}
