package weather

import (
	"context"
	"fmt"
	"strings"

	"github.com/duxlabs-dev/dux-go/ipc"
	"github.com/duxlabs-dev/dux-go/ipc/params"
	coreweather "github.com/duxlabs-dev/dux-go/weather"
	"github.com/duxlabs-dev/dux-shell/core/internal/lowprio"
	"github.com/duxlabs-dev/dux-shell/core/internal/plugins"
)

func HandleRequest(ctx context.Context, conn *ipc.ConnWriter, req ipc.Request) {
	switch req.Method {
	case "weather.get":
		handleGet(ctx, conn, req)
	default:
		conn.RespondError(req.ID, fmt.Sprintf("unknown method: %s", req.Method))
	}
}

const pluginPrefix = "plugin_"

var client = coreweather.New(coreweather.Options{
	UserAgent: "Dux Modular Shell Weather Widget (+https://github.com/duxlabs-dev/dux-shell)",
	Resolve:   pluginSource,
})

func pluginSource(provider coreweather.Provider) (coreweather.Source, bool) {
	pluginID, ok := strings.CutPrefix(string(provider), pluginPrefix)
	if !ok {
		return coreweather.Source{}, false
	}
	manager, err := plugins.NewManager()
	if err != nil {
		return coreweather.Source{}, false
	}
	plugin, ok := manager.WeatherProvider(pluginID)
	if !ok {
		return coreweather.Source{}, false
	}
	return coreweather.Source{
		Name:  plugin.Name,
		URL:   plugin.URL,
		Fetch: lowPriority(coreweather.Command(plugin.Command)),
	}, true
}

func lowPriority(fetch coreweather.Fetcher) coreweather.Fetcher {
	return func(ctx context.Context, req coreweather.Request) (*coreweather.Forecast, error) {
		var forecast *coreweather.Forecast
		var err error
		lowprio.Run(func() { forecast, err = fetch(ctx, req) })
		return forecast, err
	}
}

// ctx ends when the shell disconnects; the shell cannot cancel a single request.
func handleGet(ctx context.Context, conn *ipc.ConnWriter, req ipc.Request) {
	request, err := parseRequest(req.Params)
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	result, err := client.Lookup(ctx, request)
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	conn.Respond(req.ID, result)
}

func parseRequest(p map[string]any) (coreweather.Request, error) {
	latitude, err := params.Float(p, "latitude")
	if err != nil {
		return coreweather.Request{}, err
	}
	longitude, err := params.Float(p, "longitude")
	if err != nil {
		return coreweather.Request{}, err
	}
	var providers []coreweather.Provider
	if _, configured := p["providers"]; configured {
		ids := params.StringSlice(p, "providers")
		// Switching every provider off still leaves Open-Meteo.
		if len(ids) == 0 {
			ids = []string{string(coreweather.OpenMeteo)}
		}
		for _, id := range ids {
			providers = append(providers, coreweather.Provider(id))
		}
	}
	return coreweather.Request{
		Latitude:   latitude,
		Longitude:  longitude,
		Providers:  providers,
		AirQuality: params.BoolOpt(p, "air_quality", false),
	}, nil
}
