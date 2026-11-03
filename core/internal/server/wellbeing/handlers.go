package wellbeing

import (
	"fmt"

	"github.com/duxlabs-dev/dux-go/ipc"
	"github.com/duxlabs-dev/dux-go/ipc/params"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/models"
)

func HandleRequest(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	switch req.Method {
	case "wellbeing.getState":
		conn.Respond(req.ID, manager.GetState())
	case "wellbeing.setState":
		handleSetState(conn, req, manager)
	case "wellbeing.setLimits":
		handleSetLimits(conn, req, manager)
	case "wellbeing.summary":
		days := min(max(params.IntOpt(req.Params, "days", 7), 1), retentionDays)
		conn.Respond(req.ID, map[string]any{"days": manager.Summary(days)})
	case "wellbeing.clear":
		manager.Clear()
		conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "wellbeing history cleared"})
	default:
		conn.RespondError(req.ID, fmt.Sprintf("unknown method: %s", req.Method))
	}
}

func handleSetState(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	active, err := params.Bool(req.Params, "active")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	manager.SetState(params.StringOpt(req.Params, "appId", ""), active, int64(params.FloatOpt(req.Params, "seq", 0)))
	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "wellbeing state set"})
}

func handleSetLimits(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	limits := Limits{Daily: int64(params.FloatOpt(req.Params, "daily", 0)), Apps: map[string]int64{}}
	if apps, ok := params.AnyMap(req.Params, "apps"); ok {
		for appID, raw := range apps {
			seconds, ok := raw.(float64)
			if !ok || seconds <= 0 || appID == "" {
				continue
			}
			limits.Apps[appID] = int64(seconds)
		}
	}
	manager.SetLimits(limits)
	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "wellbeing limits set"})
}
