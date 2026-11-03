package clipboard

import (
	"encoding/json"
	"errors"
	"fmt"
	"math"

	"github.com/duxlabs-dev/dux-go/ipc"
	"github.com/duxlabs-dev/dux-go/ipc/params"
	clipboardstore "github.com/duxlabs-dev/dux-shell/core/internal/clipboard"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/models"
)

func HandleRequest(conn *ipc.ConnWriter, req ipc.Request, m *Manager) {
	switch req.Method {
	case "clipboard.getState":
		handleGetState(conn, req, m)
	case "clipboard.getHistory":
		handleGetHistory(conn, req, m)
	case "clipboard.getEntry":
		handleGetEntry(conn, req, m)
	case "clipboard.deleteEntry":
		handleDeleteEntry(conn, req, m)
	case "clipboard.deleteEntries":
		handleDeleteEntries(conn, req, m)
	case "clipboard.clearHistory":
		handleClearHistory(conn, req, m)
	case "clipboard.copy":
		handleCopy(conn, req, m)
	case "clipboard.copyEntry":
		handleCopyEntry(conn, req, m)
	case "clipboard.paste":
		handlePaste(conn, req, m)
	case "clipboard.sendPaste":
		handleSendPaste(conn, req)
	case "clipboard.pasteSupported":
		conn.Respond(req.ID, map[string]bool{"supported": m.pasteSupported})
	case "clipboard.subscribe":
		handleSubscribe(conn, req, m)
	case "clipboard.search":
		handleSearch(conn, req, m)
	case "clipboard.store":
		handleStore(conn, req, m)
	case "clipboard.pinEntry":
		handlePinEntry(conn, req, m)
	case "clipboard.unpinEntry":
		handleUnpinEntry(conn, req, m)
	case "clipboard.editEntry":
		handleEditEntry(conn, req, m)
	case "clipboard.getPinnedEntries":
		handleGetPinnedEntries(conn, req, m)
	case "clipboard.getPinnedCount":
		handleGetPinnedCount(conn, req, m)
	case "clipboard.copyFile":
		handleCopyFile(conn, req, m)
	default:
		conn.RespondError(req.ID, "unknown method: "+req.Method)
	}
}

func handleGetState(conn *ipc.ConnWriter, req ipc.Request, m *Manager) {
	conn.Respond(req.ID, m.GetState())
}

func handleGetHistory(conn *ipc.ConnWriter, req ipc.Request, m *Manager) {
	history := m.GetHistory()
	for i := range history {
		history[i].Data = nil
	}
	conn.Respond(req.ID, history)
}

func handleGetEntry(conn *ipc.ConnWriter, req ipc.Request, m *Manager) {
	id, err := params.Int(req.Params, "id")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	entry, err := m.GetEntry(uint64(id))
	if err != nil {
		if errors.Is(err, errEntryNotFound) {
			conn.Respond[any](req.ID, nil)
			return
		}
		conn.RespondError(req.ID, err.Error())
		return
	}

	conn.Respond(req.ID, entry)
}

func handleDeleteEntry(conn *ipc.ConnWriter, req ipc.Request, m *Manager) {
	id, err := params.Int(req.Params, "id")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	if err := m.DeleteEntry(uint64(id)); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "entry deleted"})
}

func handleDeleteEntries(conn *ipc.ConnWriter, req ipc.Request, m *Manager) {
	raw, ok := params.Any(req.Params, "ids")
	if !ok {
		conn.RespondError(req.ID, "missing 'ids' parameter")
		return
	}

	list, ok := raw.([]any)
	if !ok {
		conn.RespondError(req.ID, "'ids' must be an array")
		return
	}

	ids := make([]uint64, 0, len(list))
	for _, item := range list {
		id, err := toEntryID(item)
		if err != nil {
			conn.RespondError(req.ID, err.Error())
			return
		}
		ids = append(ids, id)
	}

	deleted, err := m.DeleteEntries(ids)
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	conn.Respond(req.ID, map[string]int{"deleted": deleted})
}

// toEntryID accepts the shapes a clipboard entry id can arrive in: JSON decodes
// numbers as float64, while Go callers and tests pass the integer types
// directly.
func toEntryID(value any) (uint64, error) {
	switch v := value.(type) {
	case float64:
		if v < 0 || v != math.Trunc(v) {
			return 0, fmt.Errorf("invalid entry id: %v", v)
		}
		return uint64(v), nil
	case json.Number:
		id, err := v.Int64()
		if err != nil || id < 0 {
			return 0, fmt.Errorf("invalid entry id: %v", v)
		}
		return uint64(id), nil
	case int:
		if v < 0 {
			return 0, fmt.Errorf("invalid entry id: %v", v)
		}
		return uint64(v), nil
	case int64:
		if v < 0 {
			return 0, fmt.Errorf("invalid entry id: %v", v)
		}
		return uint64(v), nil
	case uint64:
		return v, nil
	default:
		return 0, fmt.Errorf("invalid entry id: %v", value)
	}
}

func handleClearHistory(conn *ipc.ConnWriter, req ipc.Request, m *Manager) {
	m.ClearHistory()
	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "history cleared"})
}

func handleCopy(conn *ipc.ConnWriter, req ipc.Request, m *Manager) {
	text, err := params.String(req.Params, "text")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	if err := m.CopyText(text); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "copied to clipboard"})
}

func handleCopyEntry(conn *ipc.ConnWriter, req ipc.Request, m *Manager) {
	id, err := params.Int(req.Params, "id")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	entry, err := m.GetEntry(uint64(id))
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	textOnly := params.BoolOpt(req.Params, "textOnly", false) && entry.AltMimeType != ""

	if entry.AltMimeType == "" {
		filePath := m.EntryToFile(entry)
		if filePath != "" {
			if err := m.CopyFile(filePath); err != nil {
				conn.RespondError(req.ID, err.Error())
				return
			}
			conn.Respond(req.ID, map[string]any{
				"success":  true,
				"filePath": filePath,
			})
			return
		}
	}

	var setErr error
	switch {
	case textOnly:
		setErr = m.SetClipboard(entry.AltData, entry.AltMimeType)
	default:
		setErr = m.SetClipboardEntry(entry)
	}
	if setErr != nil {
		conn.RespondError(req.ID, setErr.Error())
		return
	}

	if entry.Pinned {
		if err := m.CreateHistoryEntryFromPinned(entry); err != nil {
			conn.RespondError(req.ID, err.Error())
			return
		}
	} else {
		if err := m.TouchEntry(uint64(id)); err != nil {
			conn.RespondError(req.ID, err.Error())
			return
		}
	}

	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "copied to clipboard"})
}

func handlePaste(conn *ipc.ConnWriter, req ipc.Request, m *Manager) {
	text, err := m.PasteText()
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	conn.Respond(req.ID, map[string]string{"text": text})
}

func handleSendPaste(conn *ipc.ConnWriter, req ipc.Request) {
	shift, _ := req.Get[bool]("shift")

	if err := clipboardstore.SendPasteKeystroke(shift); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "paste sent"})
}

func handleSubscribe(conn *ipc.ConnWriter, req ipc.Request, m *Manager) {
	clientID := fmt.Sprintf("clipboard-%d", req.ID)

	ch := m.Subscribe(clientID)
	defer m.Unsubscribe(clientID)

	initialState := m.GetState()
	if err := conn.WriteResponse(ipc.Response[State]{
		ID:     req.ID,
		Result: &initialState,
	}); err != nil {
		return
	}

	for state := range ch {
		if err := conn.WriteResponse(ipc.Response[State]{
			ID:     req.ID,
			Result: &state,
		}); err != nil {
			return
		}
	}
}

func handleSearch(conn *ipc.ConnWriter, req ipc.Request, m *Manager) {
	p := SearchParams{
		Query:    params.StringOpt(req.Params, "query", ""),
		MimeType: params.StringOpt(req.Params, "mimeType", ""),
		Limit:    params.IntOpt(req.Params, "limit", 50),
		Offset:   params.IntOpt(req.Params, "offset", 0),
	}

	if img, ok := req.Get[bool]("isImage"); ok {
		p.IsImage = &img
	}
	if b, ok := req.Get[float64]("before"); ok {
		v := int64(b)
		p.Before = &v
	}
	if a, ok := req.Get[float64]("after"); ok {
		v := int64(a)
		p.After = &v
	}

	conn.Respond(req.ID, m.Search(p))
}

func handleStore(conn *ipc.ConnWriter, req ipc.Request, m *Manager) {
	data, err := params.String(req.Params, "data")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	mimeType := params.StringOpt(req.Params, "mimeType", "text/plain;charset=utf-8")

	if err := m.StoreData([]byte(data), mimeType); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "stored"})
}

func handlePinEntry(conn *ipc.ConnWriter, req ipc.Request, m *Manager) {
	id, err := params.Int(req.Params, "id")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	if err := m.PinEntry(uint64(id)); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "entry pinned"})
}

func handleUnpinEntry(conn *ipc.ConnWriter, req ipc.Request, m *Manager) {
	id, err := params.Int(req.Params, "id")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	if err := m.UnpinEntry(uint64(id)); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "entry unpinned"})
}

func handleGetPinnedEntries(conn *ipc.ConnWriter, req ipc.Request, m *Manager) {
	pinned := m.GetPinnedEntries()
	conn.Respond(req.ID, pinned)
}

func handleGetPinnedCount(conn *ipc.ConnWriter, req ipc.Request, m *Manager) {
	count := m.GetPinnedCount()
	conn.Respond(req.ID, map[string]int{"count": count})
}

func handleCopyFile(conn *ipc.ConnWriter, req ipc.Request, m *Manager) {
	filePath, err := params.String(req.Params, "filePath")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	if err := m.CopyFile(filePath); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "copied"})
}

func handleEditEntry(conn *ipc.ConnWriter, req ipc.Request, m *Manager) {
	id, err := params.Int(req.Params, "id")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	text, err := params.String(req.Params, "text")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	if err := m.EditEntry(uint64(id), text); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "entry updated"})
}
