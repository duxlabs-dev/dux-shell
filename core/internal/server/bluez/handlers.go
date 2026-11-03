package bluez

import (
	"encoding/json"
	"fmt"
	"math"

	"github.com/duxlabs-dev/dux-go/ipc"
	"github.com/duxlabs-dev/dux-go/ipc/params"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/models"
)

type PoweredResult struct {
	Success bool `json:"success"`
	Powered bool `json:"powered"`
}

type BluetoothEvent struct {
	Type string         `json:"type"`
	Data BluetoothState `json:"data"`
}

func HandleRequest(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	switch req.Method {
	case "bluetooth.getState":
		handleGetState(conn, req, manager)
	case "bluetooth.startDiscovery":
		handleStartDiscovery(conn, req, manager)
	case "bluetooth.stopDiscovery":
		handleStopDiscovery(conn, req, manager)
	case "bluetooth.setPowered":
		handleSetPowered(conn, req, manager)
	case "bluetooth.togglePowered":
		handleTogglePowered(conn, req, manager)
	case "bluetooth.pair":
		handlePairDevice(conn, req, manager)
	case "bluetooth.connect":
		handleConnectDevice(conn, req, manager)
	case "bluetooth.disconnect":
		handleDisconnectDevice(conn, req, manager)
	case "bluetooth.remove":
		handleRemoveDevice(conn, req, manager)
	case "bluetooth.trust":
		handleTrustDevice(conn, req, manager)
	case "bluetooth.untrust":
		handleUntrustDevice(conn, req, manager)
	case "bluetooth.subscribe":
		handleSubscribe(conn, req, manager)
	case "bluetooth.mpris.publish":
		handleMPRISPublish(conn, req, manager)
	case "bluetooth.pairing.submit":
		handlePairingSubmit(conn, req, manager)
	case "bluetooth.pairing.cancel":
		handlePairingCancel(conn, req, manager)
	default:
		conn.RespondError(req.ID, fmt.Sprintf("unknown method: %s", req.Method))
	}
}

func handleGetState(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	conn.Respond(req.ID, manager.GetState())
}

func handleMPRISPublish(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	lease, err := params.String(req.Params, "lease")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	snapshot, err := playerSnapshotFromParams(req.Params)
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	if err := manager.PublishMPRIS(lease, snapshot); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "MPRIS state published"})
}

func playerSnapshotFromParams(values map[string]any) (PlayerSnapshot, error) {
	var snapshot PlayerSnapshot
	var err error
	if snapshot.Enabled, err = params.Bool(values, "enabled"); err != nil {
		return PlayerSnapshot{}, err
	}
	if snapshot.Identity, err = params.String(values, "identity"); err != nil {
		return PlayerSnapshot{}, err
	}
	if snapshot.PlaybackStatus, err = params.String(values, "playbackStatus"); err != nil {
		return PlayerSnapshot{}, err
	}
	if snapshot.Title, err = params.String(values, "title"); err != nil {
		return PlayerSnapshot{}, err
	}
	if snapshot.Artist, err = params.String(values, "artist"); err != nil {
		return PlayerSnapshot{}, err
	}
	if snapshot.Album, err = params.String(values, "album"); err != nil {
		return PlayerSnapshot{}, err
	}
	if snapshot.Length, err = int64Param(values, "length"); err != nil {
		return PlayerSnapshot{}, err
	}
	if snapshot.Position, err = int64Param(values, "position"); err != nil {
		return PlayerSnapshot{}, err
	}
	if snapshot.CanControl, err = params.Bool(values, "canControl"); err != nil {
		return PlayerSnapshot{}, err
	}
	if snapshot.CanPlay, err = params.Bool(values, "canPlay"); err != nil {
		return PlayerSnapshot{}, err
	}
	if snapshot.CanPause, err = params.Bool(values, "canPause"); err != nil {
		return PlayerSnapshot{}, err
	}
	if snapshot.CanGoNext, err = params.Bool(values, "canGoNext"); err != nil {
		return PlayerSnapshot{}, err
	}
	if snapshot.CanGoPrevious, err = params.Bool(values, "canGoPrevious"); err != nil {
		return PlayerSnapshot{}, err
	}
	if err := validatePlayerSnapshot(snapshot); err != nil {
		return PlayerSnapshot{}, err
	}
	return snapshot, nil
}

func int64Param(values map[string]any, key string) (int64, error) {
	value, ok := values[key]
	if !ok {
		return 0, fmt.Errorf("missing or invalid '%s' parameter", key)
	}
	var number float64
	switch typed := value.(type) {
	case float64:
		number = typed
	case json.Number:
		parsed, err := typed.Int64()
		if err != nil {
			return 0, fmt.Errorf("missing or invalid '%s' parameter", key)
		}
		return parsed, nil
	case int64:
		return typed, nil
	case int:
		return int64(typed), nil
	default:
		return 0, fmt.Errorf("missing or invalid '%s' parameter", key)
	}
	if math.IsNaN(number) || math.IsInf(number, 0) || math.Trunc(number) != number || number < math.MinInt64 || number >= 9223372036854775808 {
		return 0, fmt.Errorf("missing or invalid '%s' parameter", key)
	}
	return int64(number), nil
}

func handleStartDiscovery(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	if err := manager.StartDiscovery(params.StringOpt(req.Params, "adapter", "")); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "discovery started"})
}

func handleStopDiscovery(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	if err := manager.StopDiscovery(params.StringOpt(req.Params, "adapter", "")); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "discovery stopped"})
}

func handleSetPowered(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	powered, err := params.Bool(req.Params, "powered")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	if err := manager.SetPowered(params.StringOpt(req.Params, "adapter", ""), powered); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "powered state updated"})
}

func handleTogglePowered(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	powered, err := manager.TogglePowered(params.StringOpt(req.Params, "adapter", ""))
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	conn.Respond(req.ID, PoweredResult{Success: true, Powered: powered})
}

func handlePairDevice(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	devicePath, err := params.String(req.Params, "device")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	if err := manager.PairDevice(devicePath); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "pairing initiated"})
}

func handleConnectDevice(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	devicePath, err := params.String(req.Params, "device")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	if err := manager.ConnectDevice(devicePath); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "connecting"})
}

func handleDisconnectDevice(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	devicePath, err := params.String(req.Params, "device")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	if err := manager.DisconnectDevice(devicePath); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "disconnected"})
}

func handleRemoveDevice(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	devicePath, err := params.String(req.Params, "device")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	if err := manager.RemoveDevice(devicePath); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "device removed"})
}

func handleTrustDevice(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	devicePath, err := params.String(req.Params, "device")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	if err := manager.TrustDevice(devicePath, true); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "device trusted"})
}

func handleUntrustDevice(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	devicePath, err := params.String(req.Params, "device")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	if err := manager.TrustDevice(devicePath, false); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "device untrusted"})
}

func handlePairingSubmit(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	token, err := params.String(req.Params, "token")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	secrets := params.StringMapOpt(req.Params, "secrets")
	accept := params.BoolOpt(req.Params, "accept", false)

	if err := manager.SubmitPairing(token, secrets, accept); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "pairing response submitted"})
}

func handlePairingCancel(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	token, err := params.String(req.Params, "token")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	if err := manager.CancelPairing(token); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "pairing cancelled"})
}

func handleSubscribe(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	clientID := fmt.Sprintf("client-%p", conn)
	stateChan := manager.Subscribe(clientID)
	defer manager.Unsubscribe(clientID)

	initialState := manager.GetState()
	event := BluetoothEvent{
		Type: "state_changed",
		Data: initialState,
	}

	if err := conn.WriteResponse(ipc.Response[BluetoothEvent]{
		ID:     req.ID,
		Result: &event,
	}); err != nil {
		return
	}

	for state := range stateChan {
		event := BluetoothEvent{
			Type: "state_changed",
			Data: state,
		}
		if err := conn.WriteResponse(ipc.Response[BluetoothEvent]{
			Result: &event,
		}); err != nil {
			return
		}
	}
}
