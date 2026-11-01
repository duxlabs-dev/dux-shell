package mime

import (
	"fmt"

	"github.com/duxlabs-dev/dux-go/desktop"
	"github.com/duxlabs-dev/dux-go/ipc"
	"github.com/duxlabs-dev/dux-go/ipc/params"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/models"
)

type defaultResult struct {
	MimeType  string `json:"mimeType"`
	DesktopID string `json:"desktopId"`
}

type appsResult struct {
	MimeType   string   `json:"mimeType"`
	DesktopIDs []string `json:"desktopIds"`
}

type handlerApp struct {
	ID   string `json:"id"`
	Name string `json:"name"`
	Icon string `json:"icon,omitempty"`
}

type handlersResult struct {
	MimeType string       `json:"mimeType"`
	Apps     []handlerApp `json:"apps"`
}

type queryResult struct {
	Defaults map[string]string `json:"defaults"`
}

func HandleRequest(conn *ipc.ConnWriter, req ipc.Request) {
	switch req.Method {
	case "mime.getDefault":
		handleGetDefault(conn, req)
	case "mime.setDefault":
		handleSetDefault(conn, req)
	case "mime.setDefaults":
		handleSetDefaults(conn, req)
	case "mime.appsForMime":
		handleAppsForMime(conn, req)
	case "mime.handlersForMime":
		handleHandlersForMime(conn, req)
	case "mime.queryDefaults":
		handleQueryDefaults(conn, req)
	case "mime.invalidate":
		desktop.InvalidateCache()
		conn.Respond(req.ID, models.SuccessResult{Success: true})
	default:
		conn.RespondError(req.ID, fmt.Sprintf("unknown method: %s", req.Method))
	}
}

func handleGetDefault(conn *ipc.ConnWriter, req ipc.Request) {
	mimeType, err := requestedMime(req.Params)
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	conn.Respond(req.ID, defaultResult{
		MimeType:  mimeType,
		DesktopID: desktop.GetDefault(mimeType),
	})
}

func handleSetDefault(conn *ipc.ConnWriter, req ipc.Request) {
	mimeType, err := mimeParam(req.Params, "mimeType")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	desktopID, err := params.StringNonEmpty(req.Params, "desktopId")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	if err := desktop.SetDefault(mimeType, desktopID); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	conn.Respond(req.ID, models.SuccessResult{Success: true})
}

func handleSetDefaults(conn *ipc.ConnWriter, req ipc.Request) {
	desktopID, err := params.StringNonEmpty(req.Params, "desktopId")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	mimeTypes, err := mimeListParam(req, "mimeTypes")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	if err := desktop.SetDefaults(mimeTypes, desktopID); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	conn.Respond(req.ID, models.SuccessResult{Success: true})
}

func handleAppsForMime(conn *ipc.ConnWriter, req ipc.Request) {
	mimeType, err := mimeParam(req.Params, "mimeType")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	ids := desktop.AppsForMime(mimeType)
	if ids == nil {
		ids = []string{}
	}
	conn.Respond(req.ID, appsResult{
		MimeType:   mimeType,
		DesktopIDs: ids,
	})
}

func handleHandlersForMime(conn *ipc.ConnWriter, req ipc.Request) {
	mimeType, err := mimeParam(req.Params, "mimeType")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	entries := desktop.HandlersForMime(mimeType)
	apps := make([]handlerApp, 0, len(entries))
	for _, entry := range entries {
		apps = append(apps, handlerApp{
			ID:   entry.ID,
			Name: entry.Name,
			Icon: entry.Icon,
		})
	}
	conn.Respond(req.ID, handlersResult{
		MimeType: mimeType,
		Apps:     apps,
	})
}

func handleQueryDefaults(conn *ipc.ConnWriter, req ipc.Request) {
	mimeTypes, err := mimeListParam(req, "mimeTypes")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	conn.Respond(req.ID, queryResult{
		Defaults: desktop.QueryDefaults(mimeTypes),
	})
}

func requestedMime(p map[string]any) (string, error) {
	if _, ok := p["mimeType"]; ok {
		return mimeParam(p, "mimeType")
	}
	filePath, err := params.StringNonEmpty(p, "path")
	if err != nil {
		return "", fmt.Errorf("missing 'mimeType' or 'path' parameter")
	}
	mimeType := MimeTypeForPath(filePath)
	if mimeType == "" {
		return "", fmt.Errorf("no mime type matches %q", filePath)
	}
	return mimeType, nil
}

func mimeParam(p map[string]any, key string) (string, error) {
	raw, err := params.StringNonEmpty(p, key)
	if err != nil {
		return "", err
	}
	canonical := desktop.StripMimeParams(raw)
	if canonical == "" {
		return "", fmt.Errorf("invalid '%s' parameter", key)
	}
	return canonical, nil
}

func mimeListParam(req ipc.Request, key string) ([]string, error) {
	raw, ok := req.Get[[]any](key)
	if !ok {
		return nil, fmt.Errorf("missing or invalid '%s' parameter", key)
	}
	out := make([]string, 0, len(raw))
	for _, v := range raw {
		s, ok := v.(string)
		if !ok {
			continue
		}
		canonical := desktop.StripMimeParams(s)
		if canonical == "" {
			continue
		}
		out = append(out, canonical)
	}
	if len(out) == 0 {
		return nil, fmt.Errorf("no valid mime types provided")
	}
	return out, nil
}
