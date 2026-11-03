package wayland

import (
	"fmt"
	"time"

	"github.com/duxlabs-dev/dux-go/ipc"
	"github.com/duxlabs-dev/dux-go/ipc/params"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/models"
)

func HandleRequest(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	if manager == nil {
		conn.RespondError(req.ID, "wayland manager not initialized")
		return
	}

	switch req.Method {
	case "wayland.gamma.getState":
		handleGetState(conn, req, manager)
	case "wayland.gamma.setTemperature":
		handleSetTemperature(conn, req, manager)
	case "wayland.gamma.setLocation":
		handleSetLocation(conn, req, manager)
	case "wayland.gamma.setManualTimes":
		handleSetManualTimes(conn, req, manager)
	case "wayland.gamma.setUseIPLocation":
		handleSetUseIPLocation(conn, req, manager)
	case "wayland.gamma.setGamma":
		handleSetGamma(conn, req, manager)
	case "wayland.gamma.setEnabled":
		handleSetEnabled(conn, req, manager)
	case "wayland.gamma.subscribe":
		handleSubscribe(conn, req, manager)
	case "wayland.icc.getStatus":
		handleICCGetStatus(conn, req, manager)
	case "wayland.icc.apply":
		handleICCApply(conn, req, manager)
	case "wayland.icc.remove":
		handleICCRemove(conn, req, manager)
	case "wayland.icc.listOutputs":
		handleICCListOutputs(conn, req, manager)
	case "wayland.icc.setTemp":
		handleICCSetTemp(conn, req, manager)
	case "wayland.icc.getTemps":
		handleICCGetTemps(conn, req, manager)
	default:
		conn.RespondError(req.ID, fmt.Sprintf("unknown method: %s", req.Method))
	}
}

func handleGetState(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	conn.Respond(req.ID, manager.GetState())
}

func handleSetTemperature(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	var lowTemp, highTemp int

	if temp, ok := req.Get[float64]("temp"); ok {
		lowTemp = int(temp)
		highTemp = int(temp)
	} else {
		low, err := params.Float(req.Params, "low")
		if err != nil {
			conn.RespondError(req.ID, "missing temperature parameters (provide 'temp' or both 'low' and 'high')")
			return
		}
		high, err := params.Float(req.Params, "high")
		if err != nil {
			conn.RespondError(req.ID, "missing temperature parameters (provide 'temp' or both 'low' and 'high')")
			return
		}
		lowTemp = int(low)
		highTemp = int(high)
	}

	if err := manager.SetTemperature(lowTemp, highTemp); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "temperature set"})
}

func handleSetLocation(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	lat, err := params.Float(req.Params, "latitude")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	lon, err := params.Float(req.Params, "longitude")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	if err := manager.SetLocation(lat, lon); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "location set"})
}

func handleSetManualTimes(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	sunriseStr, sunriseOK := req.Get[string]("sunrise")
	sunsetStr, sunsetOK := req.Get[string]("sunset")

	if !sunriseOK || !sunsetOK || sunriseStr == "" || sunsetStr == "" {
		manager.ClearManualTimes()
		conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "manual times cleared"})
		return
	}

	sunrise, err := time.Parse("15:04", sunriseStr)
	if err != nil {
		conn.RespondError(req.ID, "invalid sunrise format (use HH:MM)")
		return
	}

	sunset, err := time.Parse("15:04", sunsetStr)
	if err != nil {
		conn.RespondError(req.ID, "invalid sunset format (use HH:MM)")
		return
	}

	var duration *time.Duration
	if minutes, ok := req.Get[float64]("durationMinutes"); ok {
		d := time.Duration(minutes) * time.Minute
		duration = &d
	}

	if err := manager.SetManualTimes(sunrise, sunset, duration); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "manual times set"})
}

func handleSetUseIPLocation(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	use, err := params.Bool(req.Params, "use")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	manager.SetUseIPLocation(use)
	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "IP location preference set"})
}

func handleSetGamma(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	gamma, err := params.Float(req.Params, "gamma")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	_, contrast := manager.Adjustments()
	if v, ok := req.Get[float64]("contrast"); ok {
		contrast = v
	}

	if err := manager.SetAdjustments(gamma, contrast); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "gamma set"})
}

func handleSetEnabled(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	enabled, err := params.Bool(req.Params, "enabled")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	manager.SetEnabled(enabled)
	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "enabled state set"})
}

func handleSubscribe(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	clientID := fmt.Sprintf("client-%p", conn)
	stateChan := manager.Subscribe(clientID)
	defer manager.Unsubscribe(clientID)

	initialState := manager.GetState()
	if err := conn.WriteResponse(ipc.Response[State]{
		ID:     req.ID,
		Result: &initialState,
	}); err != nil {
		return
	}

	for state := range stateChan {
		if err := conn.WriteResponse(ipc.Response[State]{
			Result: &state,
		}); err != nil {
			return
		}
	}
}

func handleICCGetStatus(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	status := manager.GetICCStatus()
	outputs := manager.ListOutputs()
	result := map[string]any{
		"outputs":  outputs,
		"profiles": status,
	}
	conn.Respond(req.ID, result)
}

func handleICCApply(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	output, err := params.String(req.Params, "output")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	path, err := params.String(req.Params, "path")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	if err := manager.ApplyICC(output, path); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "ICC profile applied"})
}

func handleICCRemove(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	output, err := params.String(req.Params, "output")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	if err := manager.RemoveICC(output); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "ICC profile removed"})
}

func handleICCListOutputs(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	outputs := manager.ListOutputs()
	conn.Respond(req.ID, outputs)
}

func handleICCSetTemp(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	output, err := params.String(req.Params, "output")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	temp, err := params.Int(req.Params, "temp")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	if err := manager.SetOutputTemp(output, temp); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "Output temperature set"})
}

func handleICCGetTemps(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	temps := manager.GetOutputTemps()
	conn.Respond(req.ID, temps)
}
