package browser

import (
	"github.com/duxlabs-dev/dux-go/ipc"
)

func HandleRequest(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	switch req.Method {
	case "browser.open":
		url, ok := req.Get[string]("url")
		if !ok {
			conn.RespondError(req.ID, "invalid url parameter")
			return
		}
		manager.RequestOpen(url)
		conn.Respond(req.ID, "ok")
	default:
		conn.RespondError(req.ID, "unknown method")
	}
}
