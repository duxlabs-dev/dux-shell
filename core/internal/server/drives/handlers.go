package drives

import (
	"fmt"

	"github.com/duxlabs-dev/dux-go/ipc"
)

func HandleRequest(conn *ipc.ConnWriter, req ipc.Request) {
	switch req.Method {
	case "drives.list":
		res, err := List()
		if err != nil {
			conn.RespondError(req.ID, err.Error())
			return
		}
		conn.Respond(req.ID, res)
	default:
		conn.RespondError(req.ID, fmt.Sprintf("unknown method: %s", req.Method))
	}
}
