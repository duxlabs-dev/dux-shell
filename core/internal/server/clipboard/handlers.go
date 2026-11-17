package clipboard

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"mime"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/duxlabs-dev/dux-go/ipc"
	"github.com/duxlabs-dev/dux-go/ipc/params"
	clipboardstore "github.com/duxlabs-dev/dux-shell/core/internal/clipboard"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/models"
)

const maxSearchLimit = 5000

// copyCommitDeadline bounds when a copy request may still take the
// selection. It must stay below the CLI's serverCopyReplyTimeout, so a CLI
// that gave up and served the copy itself is never overwritten afterwards.
const copyCommitDeadline = 8 * time.Second

func copyContext() (context.Context, context.CancelFunc) {
	return context.WithTimeout(context.Background(), copyCommitDeadline)
}

func HandleRequest(conn *ipc.ConnWriter, req ipc.Request, m *Manager) {
	switch req.Method {
	case "clipboard.getState":
		handleGetState(conn, req, m)
	case "clipboard.getHistory":
		handleGetHistory(conn, req, m)
	case "clipboard.getEntry":
		handleGetEntry(conn, req, m)
	case "clipboard.exportEntryFile":
		handleExportEntryFile(conn, req, m)
	case "clipboard.getEntries":
		handleGetEntries(conn, req, m)
	case "clipboard.import":
		handleImport(conn, req, m)
	case "clipboard.deleteEntry":
		handleDeleteEntry(conn, req, m)
	case "clipboard.deleteEntries":
		handleDeleteEntries(conn, req, m)
	case "clipboard.deleteMatching":
		handleDeleteMatching(conn, req, m)
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
	case "clipboard.copyFileContents":
		handleCopyFileContents(conn, req, m)
	default:
		conn.RespondError(req.ID, "unknown method: "+req.Method)
	}
}

func handleGetState(conn *ipc.ConnWriter, req ipc.Request, m *Manager) {
	conn.Respond(req.ID, m.GetState())
}

func handleGetHistory(conn *ipc.ConnWriter, req ipc.Request, m *Manager) {
	conn.Respond(req.ID, m.GetHistory())
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

const dragTempDirName = "dms-clipboard-drag"
const dragTempFileTTL = 10 * time.Minute

func extensionForMime(mimeType string) string {
	base := strings.ToLower(strings.TrimSpace(strings.SplitN(mimeType, ";", 2)[0]))
	switch base {
	case "image/png":
		return ".png"
	case "image/jpeg", "image/jpg":
		return ".jpg"
	case "image/webp":
		return ".webp"
	case "image/gif":
		return ".gif"
	case "image/svg+xml":
		return ".svg"
	case "image/bmp":
		return ".bmp"
	case "text/plain":
		return ".txt"
	}
	if exts, err := mime.ExtensionsByType(base); err == nil && len(exts) > 0 {
		return exts[0]
	}
	return ".bin"
}

func cleanupExpiredDragFiles(dir string) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return
	}
	cutoff := time.Now().Add(-dragTempFileTTL)
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		info, err := entry.Info()
		if err != nil {
			continue
		}
		if info.ModTime().Before(cutoff) {
			_ = os.Remove(filepath.Join(dir, entry.Name()))
		}
	}
}

func removeDragFilesForEntry(dir string, id uint64) {
	prefix := fmt.Sprintf("dms-clip-%d-", id)
	entries, err := os.ReadDir(dir)
	if err != nil {
		return
	}
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasPrefix(entry.Name(), prefix) {
			continue
		}
		_ = os.Remove(filepath.Join(dir, entry.Name()))
	}
}

func clearDragTempDir(dir string) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return
	}
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		_ = os.Remove(filepath.Join(dir, entry.Name()))
	}
}

func dragTempDir() string {
	if cacheDir, err := os.UserCacheDir(); err == nil && cacheDir != "" {
		return filepath.Join(cacheDir, "dms", dragTempDirName)
	}
	return filepath.Join(os.TempDir(), dragTempDirName)
}

func parseURIListFiles(data []byte) ([]string, []string) {
	var uris []string
	var paths []string
	for line := range strings.SplitSeq(string(data), "\n") {
		trimmed := strings.TrimSpace(line)
		if trimmed == "" || strings.HasPrefix(trimmed, "#") {
			continue
		}
		if !strings.HasPrefix(trimmed, "file://") {
			continue
		}
		parsed, err := url.Parse(trimmed)
		if err != nil || parsed.Path == "" {
			continue
		}
		if _, err := os.Stat(parsed.Path); err != nil {
			continue
		}
		uris = append(uris, (&url.URL{Scheme: "file", Path: parsed.Path}).String())
		paths = append(paths, parsed.Path)
	}
	return uris, paths
}

func handleExportEntryFile(conn *ipc.ConnWriter, req ipc.Request, m *Manager) {
	id, err := params.Int(req.Params, "id")
	if err != nil || id <= 0 {
		conn.RespondError(req.ID, "invalid entry id")
		return
	}

	entry, err := m.GetEntry(uint64(id))
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	if strings.EqualFold(strings.TrimSpace(strings.SplitN(entry.MimeType, ";", 2)[0]), "text/uri-list") {
		if uris, paths := parseURIListFiles(entry.Data); len(paths) > 0 {
			conn.Respond(req.ID, map[string]any{
				"filePath":  paths[0],
				"fileUrl":   uris[0],
				"uriList":   strings.Join(uris, "\r\n") + "\r\n",
				"mimeType":  entry.MimeType,
				"isTemp":    false,
				"portalKey": m.exportPortalFiles(paths),
			})
			return
		}
	}

	dir := dragTempDir()
	if err := os.MkdirAll(dir, 0o700); err != nil {
		conn.RespondError(req.ID, fmt.Sprintf("create drag temp dir: %v", err))
		return
	}
	cleanupExpiredDragFiles(dir)

	ext := extensionForMime(entry.MimeType)
	tmpFile, err := os.CreateTemp(dir, fmt.Sprintf("dms-clip-%d-*%s", entry.ID, ext))
	if err != nil {
		conn.RespondError(req.ID, fmt.Sprintf("create drag temp file: %v", err))
		return
	}
	tmpPath := tmpFile.Name()
	if _, err := tmpFile.Write(entry.Data); err != nil {
		_ = tmpFile.Close()
		_ = os.Remove(tmpPath)
		conn.RespondError(req.ID, fmt.Sprintf("write drag temp file: %v", err))
		return
	}
	if err := tmpFile.Close(); err != nil {
		_ = os.Remove(tmpPath)
		conn.RespondError(req.ID, fmt.Sprintf("close drag temp file: %v", err))
		return
	}

	fileURL := (&url.URL{Scheme: "file", Path: tmpPath}).String()
	conn.Respond(req.ID, map[string]any{
		"filePath":  tmpPath,
		"fileUrl":   fileURL,
		"uriList":   fileURL + "\r\n",
		"mimeType":  entry.MimeType,
		"isTemp":    true,
		"portalKey": m.exportPortalFile(tmpPath),
	})
}

func handleGetEntries(conn *ipc.ConnWriter, req ipc.Request, m *Manager) {
	var ids []uint64
	if err := decodeParam(req, "ids", &ids); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	entries, err := m.GetEntries(ids)
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	conn.Respond(req.ID, entries)
}

func handleImport(conn *ipc.ConnWriter, req ipc.Request, m *Manager) {
	var entries []ImportEntry
	if err := decodeParam(req, "entries", &entries); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	imported, err := m.Import(entries)
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	conn.Respond(req.ID, map[string]int{"imported": imported})
}

func decodeParam(req ipc.Request, name string, out any) error {
	raw, ok := params.Any(req.Params, name)
	if !ok {
		return fmt.Errorf("missing '%s' parameter", name)
	}

	encoded, err := json.Marshal(raw)
	if err != nil {
		return err
	}

	if err := json.Unmarshal(encoded, out); err != nil {
		return fmt.Errorf("invalid '%s' parameter: %w", name, err)
	}
	return nil
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

func handleDeleteMatching(conn *ipc.ConnWriter, req ipc.Request, m *Manager) {
	deleted, err := m.DeleteMatching(searchParams(req))
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	conn.Respond(req.ID, map[string]int{"deleted": deleted})
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

	ctx, cancel := copyContext()
	defer cancel()
	if err := m.CopyText(ctx, text); err != nil {
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

	ctx, cancel := copyContext()
	defer cancel()
	textOnly := params.BoolOpt(req.Params, "textOnly", false) && entry.AltMimeType != ""

	if entry.AltMimeType == "" {
		filePath := m.EntryToFile(entry)
		if filePath != "" {
			if err := m.CopyFile(ctx, filePath); err != nil {
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
		setErr = m.SetClipboard(ctx, entry.AltData, entry.AltMimeType)
	default:
		setErr = m.SetClipboardEntry(ctx, entry)
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
	models.StreamSubscription(conn, req, m, fmt.Sprintf("clipboard-%d", req.ID), true)
}

func handleSearch(conn *ipc.ConnWriter, req ipc.Request, m *Manager) {
	conn.Respond(req.ID, m.Search(searchParams(req)))
}

func searchParams(req ipc.Request) SearchParams {
	p := SearchParams{
		Query:    params.StringOpt(req.Params, "query", ""),
		MimeType: params.StringOpt(req.Params, "mimeType", ""),
		Type:     params.StringOpt(req.Params, "type", ""),
		Limit:    params.IntOpt(req.Params, "limit", 50),
		Offset:   params.IntOpt(req.Params, "offset", 0),
	}
	if p.Limit <= 0 {
		p.Limit = 50
	}
	p.Limit = min(p.Limit, maxSearchLimit)

	if img, ok := req.Get[bool]("isImage"); ok {
		p.IsImage = &img
	}
	if pinned, ok := req.Get[bool]("pinned"); ok {
		p.Pinned = &pinned
	}
	if b, ok := req.Get[float64]("before"); ok {
		v := int64(b)
		p.Before = &v
	}
	if a, ok := req.Get[float64]("after"); ok {
		v := int64(a)
		p.After = &v
	}

	return p
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

	ctx, cancel := copyContext()
	defer cancel()
	if err := m.CopyFile(ctx, filePath); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "copied"})
}

func handleCopyFileContents(conn *ipc.ConnWriter, req ipc.Request, m *Manager) {
	filePath, err := params.String(req.Params, "filePath")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	mimeType, err := params.String(req.Params, "mimeType")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	ctx, cancel := copyContext()
	defer cancel()
	if err := m.CopyFileContents(ctx, filePath, mimeType); err != nil {
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

	ctx, cancel := copyContext()
	defer cancel()
	if err := m.EditEntry(ctx, uint64(id), text); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "entry updated"})
}
