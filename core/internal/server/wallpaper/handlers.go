package wallpaper

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/duxlabs-dev/dux-go/ipc"
	"github.com/duxlabs-dev/dux-go/ipc/params"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/models"
)

func HandleRequest(ctx context.Context, conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	if manager == nil {
		conn.RespondError(req.ID, "wallpaper manager not initialized")
		return
	}

	switch req.Method {
	case "wallpaper.getState":
		handleGetState(conn, req, manager)
	case "wallpaper.setConfig":
		handleSetConfig(conn, req, manager)
	case "wallpaper.trigger":
		handleTrigger(conn, req, manager)
	case "wallpaper.subscribe":
		handleSubscribe(conn, req, manager)
	case "wallpaper.list":
		handleList(ctx, conn, req)
	case "wallpaper.suggestFolders":
		conn.Respond(req.ID, SuggestFolders(params.StringSlice(req.Params, "folders")))
	case "wallpaper.folderListed":
		handleFolderListed(conn, req)
	case "wallpaper.folderOf":
		handleFolderOf(conn, req)
	default:
		conn.RespondError(req.ID, fmt.Sprintf("unknown method: %s", req.Method))
	}
}

func handleGetState(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	conn.Respond(req.ID, manager.GetState())
}

func handleSetConfig(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	var config Config
	if err := decodeParam(req.Params, "config", &config); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	manager.SetConfig(config)
	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "wallpaper schedule set"})
}

func handleList(ctx context.Context, conn *ipc.ConnWriter, req ipc.Request) {
	var folders []Folder
	if err := decodeParam(req.Params, "folders", &folders); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	extensions := params.StringSlice(req.Params, "extensions")
	if len(extensions) == 0 {
		conn.RespondError(req.ID, "missing or invalid 'extensions' parameter")
		return
	}

	ctx, cancel := context.WithTimeout(ctx, listTimeout)
	defer cancel()
	conn.Respond(req.ID, ListWallpapers(ctx, folders, extensions))
}

func handleFolderListed(conn *ipc.ConnWriter, req ipc.Request) {
	path, err := params.StringNonEmpty(req.Params, "path")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	conn.Respond(req.ID, FolderListed(path, params.StringSlice(req.Params, "folders")))
}

func handleFolderOf(conn *ipc.ConnWriter, req ipc.Request) {
	path, err := params.StringNonEmpty(req.Params, "path")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	var folders []Folder
	if err := decodeParam(req.Params, "folders", &folders); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	conn.Respond(req.ID, FolderOf(path, folders))
}

func decodeParam(reqParams map[string]any, key string, out any) error {
	raw, ok := params.Any(reqParams, key)
	if !ok {
		return fmt.Errorf("missing or invalid '%s' parameter", key)
	}

	data, err := json.Marshal(raw)
	if err != nil {
		return err
	}
	return json.Unmarshal(data, out)
}

func handleTrigger(conn *ipc.ConnWriter, req ipc.Request, manager *Manager) {
	manager.ResetSchedule(params.StringOpt(req.Params, "target", ""))
	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "wallpaper schedule reset"})
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
