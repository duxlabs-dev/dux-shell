package registries

import (
	"fmt"

	"github.com/duxlabs-dev/dux-go/ipc"
	"github.com/duxlabs-dev/dux-shell/core/internal/registries"
	"github.com/spf13/afero"
)

type RegistryInfo struct {
	Name     string `json:"name"`
	URL      string `json:"url"`
	Official bool   `json:"official"`
}

type SuccessResult struct {
	Success bool   `json:"success"`
	Message string `json:"message"`
}

func HandleRequest(conn *ipc.ConnWriter, req ipc.Request) {
	switch req.Method {
	case "registries.list":
		HandleList(conn, req)
	case "registries.add":
		HandleAdd(conn, req)
	case "registries.remove":
		HandleRemove(conn, req)
	default:
		conn.RespondError(req.ID, fmt.Sprintf("unknown method: %s", req.Method))
	}
}

func HandleList(conn *ipc.ConnWriter, req ipc.Request) {
	sources := registries.Load(afero.NewOsFs())
	result := make([]RegistryInfo, len(sources))
	for i, s := range sources {
		result[i] = RegistryInfo{Name: s.Name, URL: s.URL, Official: s.Official()}
	}
	conn.Respond(req.ID, result)
}

func HandleAdd(conn *ipc.ConnWriter, req ipc.Request) {
	name, ok := req.Get[string]("name")
	if !ok {
		conn.RespondError(req.ID, "missing or invalid 'name' parameter")
		return
	}
	url, ok := req.Get[string]("url")
	if !ok {
		conn.RespondError(req.ID, "missing or invalid 'url' parameter")
		return
	}

	if err := registries.Add(afero.NewOsFs(), name, url); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	conn.Respond(req.ID, SuccessResult{
		Success: true,
		Message: fmt.Sprintf("registry added: %s", name),
	})
}

func HandleRemove(conn *ipc.ConnWriter, req ipc.Request) {
	name, ok := req.Get[string]("name")
	if !ok {
		conn.RespondError(req.ID, "missing or invalid 'name' parameter")
		return
	}

	if err := registries.Remove(afero.NewOsFs(), name); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	conn.Respond(req.ID, SuccessResult{
		Success: true,
		Message: fmt.Sprintf("registry removed: %s", name),
	})
}
