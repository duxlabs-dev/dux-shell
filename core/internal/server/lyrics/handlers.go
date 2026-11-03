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
	"github.com/duxlabs-dev/dux-shell/core/internal/utils"
)

func HandleRequest(conn *ipc.ConnWriter, req ipc.Request) {
	switch req.Method {
	case "lyrics.get":
		handleGet(conn, req)
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
		WordSync:    plugin.WordSync,
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

func handleGet(conn *ipc.ConnWriter, req ipc.Request) {
	var providers []corelyrics.Provider
	if _, configured := req.Params["providers"]; configured {
		providers = []corelyrics.Provider{}
		for _, id := range params.StringSlice(req.Params, "providers") {
			providers = append(providers, corelyrics.Provider(id))
		}
	}
	result, err := client.Lookup(context.Background(), corelyrics.Request{
		Title:     params.StringOpt(req.Params, "title", ""),
		Artist:    params.StringOpt(req.Params, "artist", ""),
		Album:     params.StringOpt(req.Params, "album", ""),
		Duration:  time.Duration(params.IntOpt(req.Params, "duration", 0)) * time.Second,
		FileURL:   params.StringOpt(req.Params, "fileUrl", ""),
		CacheOnly: !params.BoolOpt(req.Params, "allowNetwork", false),
		Providers: providers,
	})
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	conn.Respond(req.ID, result)
	client.Prune()
}
