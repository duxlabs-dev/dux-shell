package lyrics

import (
	"context"
	"fmt"
	"path/filepath"
	"strings"
	"time"

	"github.com/duxlabs-dev/dux-go/ipc"
	"github.com/duxlabs-dev/dux-go/ipc/params"
	corelyrics "github.com/duxlabs-dev/dux-go/lyrics"
	"github.com/duxlabs-dev/dux-shell/core/internal/lowprio"
	"github.com/duxlabs-dev/dux-shell/core/internal/plugins"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/models"
	"github.com/duxlabs-dev/dux-shell/core/internal/utils"
)

func HandleRequest(conn *ipc.ConnWriter, req ipc.Request) {
	switch req.Method {
	case "lyrics.get":
		handleGet(conn, req)
	case "lyrics.choices":
		handleChoices(conn, req)
	case "lyrics.choose":
		handleChoose(conn, req)
	default:
		conn.RespondError(req.ID, fmt.Sprintf("unknown method: %s", req.Method))
	}
}

const pluginPrefix = "plugin_"

var client = corelyrics.New(corelyrics.Options{
	CacheDir:  filepath.Join(utils.XDGCacheHome(), "dms", "lyrics"),
	UserAgent: "DuxShell/1 (+https://github.com/duxlabs-dev/dux-shell)",
	Resolve:   pluginSource,
})

func pluginSource(provider corelyrics.Provider) (corelyrics.Source, bool) {
	pluginID, ok := strings.CutPrefix(string(provider), pluginPrefix)
	if !ok {
		return corelyrics.Source{}, false
	}
	manager, err := plugins.NewManager()
	if err != nil {
		return corelyrics.Source{}, false
	}
	plugin, ok := manager.LyricsProvider(pluginID)
	if !ok {
		return corelyrics.Source{}, false
	}
	return corelyrics.Source{
		Attribution: corelyrics.Attribution{Name: plugin.Name, URL: plugin.URL},
		Fetch:       lowPriority(corelyrics.Command(plugin.Command)),
	}, true
}

func lowPriority(fetch corelyrics.Fetcher) corelyrics.Fetcher {
	return func(ctx context.Context, req corelyrics.Request) (*corelyrics.Lyrics, error) {
		var lyrics *corelyrics.Lyrics
		var err error
		lowprio.Run(func() { lyrics, err = fetch(ctx, req) })
		return lyrics, err
	}
}

func trackRequest(args map[string]any) corelyrics.Request {
	var providers []corelyrics.Provider
	if _, configured := args["providers"]; configured {
		providers = []corelyrics.Provider{}
		for _, id := range params.StringSlice(args, "providers") {
			providers = append(providers, corelyrics.Provider(id))
		}
	}
	return corelyrics.Request{
		Title:     params.StringOpt(args, "title", ""),
		Artist:    params.StringOpt(args, "artist", ""),
		Album:     params.StringOpt(args, "album", ""),
		Duration:  time.Duration(params.IntOpt(args, "duration", 0)) * time.Second,
		FileURL:   params.StringOpt(args, "fileUrl", ""),
		CacheOnly: !params.BoolOpt(args, "allowNetwork", false),
		Providers: providers,
	}
}

func handleGet(conn *ipc.ConnWriter, req ipc.Request) {
	result, err := client.Lookup(context.Background(), trackRequest(req.Params))
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	conn.Respond(req.ID, result)
	client.Prune()
}

type choicesResult struct {
	Chosen  corelyrics.Provider `json:"chosen"`
	Choices []corelyrics.Choice `json:"choices"`
}

func handleChoices(conn *ipc.ConnWriter, req ipc.Request) {
	track := trackRequest(req.Params)
	choices, err := client.Choices(context.Background(), track)
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	conn.Respond(req.ID, choicesResult{Chosen: client.Chosen(track), Choices: choices})
}

func handleChoose(conn *ipc.ConnWriter, req ipc.Request) {
	source := corelyrics.Provider(params.StringOpt(req.Params, "source", ""))
	if err := client.Choose(trackRequest(req.Params), source); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	conn.Respond(req.ID, models.SuccessResult{Success: true})
}
