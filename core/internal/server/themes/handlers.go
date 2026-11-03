package themes

import (
	"fmt"

	"github.com/duxlabs-dev/dux-go/ipc"
)

func HandleRequest(conn *ipc.ConnWriter, req ipc.Request) {
	switch req.Method {
	case "themes.list":
		HandleList(conn, req)
	case "themes.listInstalled":
		HandleListInstalled(conn, req)
	case "themes.install":
		HandleInstall(conn, req)
	case "themes.uninstall":
		HandleUninstall(conn, req)
	case "themes.update":
		HandleUpdate(conn, req)
	case "themes.search":
		HandleSearch(conn, req)
	default:
		conn.RespondError(req.ID, fmt.Sprintf("unknown method: %s", req.Method))
	}
}
