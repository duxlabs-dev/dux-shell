package apppicker

import (
	"github.com/duxlabs-dev/dux-go/desktop"
	"github.com/duxlabs-dev/dux-go/ipc"
	"github.com/duxlabs-dev/dux-shell/core/internal/log"
)

func HandleRequest(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	switch req.Method {
	case "apppicker.open", "browser.open":
		handleOpen(conn, req, manager)
	default:
		conn.RespondError(req.ID, "unknown method")
	}
}

func handleOpen(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	log.Infof("AppPicker: Received %s request with params: %+v", req.Method, req.Params)

	target, ok := req.Get[string]("target")
	if !ok {
		target, ok = req.Get[string]("url")
		if !ok {
			log.Warnf("AppPicker: Invalid target parameter in request")
			conn.RespondError(req.ID, "invalid target parameter")
			return
		}
	}

	event := OpenEvent{
		Target:      target,
		RequestType: req.GetOr("requestType", "url"),
		MimeType:    desktop.StripMimeParams(req.GetOr("mimeType", "")),
	}

	if categories, ok := req.Get[[]any]("categories"); ok {
		event.Categories = make([]string, 0, len(categories))
		for _, cat := range categories {
			if catStr, ok := cat.(string); ok {
				event.Categories = append(event.Categories, catStr)
			}
		}
	}

	log.Infof("AppPicker: Broadcasting event: %+v", event)
	manager.RequestOpen(event)
	conn.Respond(req.ID, "ok")
	log.Infof("AppPicker: Request handled successfully")
}
