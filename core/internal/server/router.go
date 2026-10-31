package server

import (
	"context"
	"fmt"

	"github.com/duxlabs-dev/dux-go/ipc"
	"github.com/duxlabs-dev/dux-go/ipc/params"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/apppicker"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/bluez"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/brightness"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/clipboard"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/cups"
	serverDbus "github.com/duxlabs-dev/dux-shell/core/internal/server/dbus"
	serverDgop "github.com/duxlabs-dev/dux-shell/core/internal/server/dgop"
	serverDrives "github.com/duxlabs-dev/dux-shell/core/internal/server/drives"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/evdev"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/freedesktop"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/location"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/loginctl"
	serverLyrics "github.com/duxlabs-dev/dux-shell/core/internal/server/lyrics"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/mime"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/models"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/network"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/notifyactions"
	serverPlugins "github.com/duxlabs-dev/dux-shell/core/internal/server/plugins"
	serverRegistries "github.com/duxlabs-dev/dux-shell/core/internal/server/registries"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/sysupdate"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/tailscale"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/thememode"
	serverThemes "github.com/duxlabs-dev/dux-shell/core/internal/server/themes"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/wallpaper"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/wayland"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/wellbeing"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/wlroutput"
	"github.com/duxlabs-dev/dux-shell/core/internal/systemd"
)

var requestMux = newRequestMux(nil)

func RouteRequest(ctx context.Context, conn *ipc.ConnWriter, req ipc.Request) {
	requestMux.ServeIPC(ctx, conn, req, nil)
}

func requestHandler(handle func(*ipc.ConnWriter, ipc.Request)) ipc.Handler {
	return func(_ context.Context, conn *ipc.ConnWriter, req ipc.Request, _ *ipc.Subscriber) {
		handle(conn, req)
	}
}

func newRequestMux(readiness *systemd.Readiness) *ipc.Mux {
	mux := ipc.NewMux()
	mux.Handle("ping", requestHandler(func(conn *ipc.ConnWriter, req ipc.Request) {
		conn.Respond(req.ID, "pong")
	}))
	mux.Handle("getServerInfo", requestHandler(func(conn *ipc.ConnWriter, req ipc.Request) {
		conn.Respond(req.ID, getServerInfo())
	}))
	mux.Handle("shell.ready", requestHandler(func(conn *ipc.ConnWriter, req ipc.Request) {
		pid, err := params.Int(req.Params, "pid")
		if err != nil || pid <= 0 || uint64(pid) > uint64(^uint32(0)) {
			conn.RespondError(req.ID, "invalid shell pid")
			return
		}
		if readiness != nil {
			readiness.ShellReady(uint32(pid))
		}
		conn.Respond(req.ID, models.SuccessResult{Success: true})
	}))
	mux.Handle("subscribe", func(ctx context.Context, conn *ipc.ConnWriter, req ipc.Request, _ *ipc.Subscriber) {
		handleSubscribe(ctx, conn, req)
	})
	mux.Handle("matugen.queue", requestHandler(handleMatugenQueue))
	mux.Handle("matugen.status", requestHandler(handleMatugenStatus))
	mux.Handle("clipboard.getConfig", requestHandler(func(conn *ipc.ConnWriter, req ipc.Request) {
		conn.Respond(req.ID, clipboard.LoadConfig())
	}))
	mux.Handle("clipboard.setConfig", requestHandler(handleClipboardSetConfig))

	mux.HandlePrefix("network.", requestHandler(func(conn *ipc.ConnWriter, req ipc.Request) {
		if networkManager == nil {
			conn.RespondError(req.ID, "network manager not initialized")
			return
		}
		network.HandleRequest(conn, req, networkManager)
	}))

	mux.HandlePrefix("plugins.", requestHandler(serverPlugins.HandleRequest))

	mux.HandlePrefix("themes.", requestHandler(serverThemes.HandleRequest))

	mux.HandlePrefix("registries.", requestHandler(serverRegistries.HandleRequest))

	mux.HandlePrefix("theme.auto.", requestHandler(func(conn *ipc.ConnWriter, req ipc.Request) {
		if themeModeManager == nil {
			conn.RespondError(req.ID, "theme mode manager not initialized")
			return
		}
		thememode.HandleRequest(conn, req, themeModeManager)
	}))

	mux.HandlePrefix("wallpaper.", requestHandler(func(conn *ipc.ConnWriter, req ipc.Request) {
		if wallpaperManager == nil {
			conn.RespondError(req.ID, "wallpaper manager not initialized")
			return
		}
		wallpaper.HandleRequest(conn, req, wallpaperManager)
	}))

	mux.HandlePrefix("loginctl.", requestHandler(func(conn *ipc.ConnWriter, req ipc.Request) {
		if loginctlManager == nil {
			conn.RespondError(req.ID, "loginctl manager not initialized")
			return
		}
		loginctl.HandleRequest(conn, req, loginctlManager)
	}))

	mux.HandlePrefix("freedesktop.", requestHandler(func(conn *ipc.ConnWriter, req ipc.Request) {
		if freedesktopManager == nil {
			conn.RespondError(req.ID, "freedesktop manager not initialized")
			return
		}
		freedesktop.HandleRequest(conn, req, freedesktopManager)
	}))

	mux.HandlePrefix("wayland.", requestHandler(func(conn *ipc.ConnWriter, req ipc.Request) {
		if waylandManager == nil {
			conn.RespondError(req.ID, "wayland manager not initialized")
			return
		}
		wayland.HandleRequest(conn, req, waylandManager)
	}))

	mux.HandlePrefix("bluetooth.", requestHandler(func(conn *ipc.ConnWriter, req ipc.Request) {
		if bluezManager == nil {
			conn.RespondError(req.ID, "bluetooth manager not initialized")
			return
		}
		bluez.HandleRequest(conn, req, bluezManager)
	}))

	mux.HandlePrefix("mime.", requestHandler(mime.HandleRequest))

	mux.HandlePrefix("files.", func(ctx context.Context, conn *ipc.ConnWriter, req ipc.Request, _ *ipc.Subscriber) {
		if filesService == nil {
			conn.RespondError(req.ID, "files service not initialized")
			return
		}
		filesService.Handle(ctx, conn, req)
	})

	mux.HandlePrefix("dgop.", requestHandler(serverDgop.HandleRequest))

	mux.HandlePrefix("drives.", requestHandler(serverDrives.HandleRequest))

	mux.HandlePrefix("lyrics.", requestHandler(serverLyrics.HandleRequest))

	appPickerHandler := requestHandler(func(conn *ipc.ConnWriter, req ipc.Request) {
		if appPickerManager == nil {
			conn.RespondError(req.ID, "apppicker manager not initialized")
			return
		}
		apppicker.HandleRequest(conn, req, appPickerManager)
	})
	mux.HandlePrefix("browser.", appPickerHandler)
	mux.HandlePrefix("apppicker.", appPickerHandler)

	mux.HandlePrefix("cups.", requestHandler(func(conn *ipc.ConnWriter, req ipc.Request) {
		mgr, err := ensureCupsManager()
		if err != nil {
			conn.RespondError(req.ID, "CUPS manager not initialized")
			return
		}
		cups.HandleRequest(conn, req, mgr)
	}))

	mux.HandlePrefix("tailscale.", requestHandler(func(conn *ipc.ConnWriter, req ipc.Request) {
		if tailscaleManager == nil {
			conn.RespondError(req.ID, "Tailscale not available")
			return
		}
		tailscale.HandleRequest(conn, req, tailscaleManager)
	}))

	mux.HandlePrefix("brightness.", requestHandler(func(conn *ipc.ConnWriter, req ipc.Request) {
		if brightnessManager == nil {
			conn.RespondError(req.ID, "brightness manager not initialized")
			return
		}
		brightness.HandleRequest(conn, req, brightnessManager)
	}))

	mux.HandlePrefix("wlroutput.", requestHandler(func(conn *ipc.ConnWriter, req ipc.Request) {
		if wlrOutputManager == nil {
			conn.RespondError(req.ID, "wlroutput manager not initialized")
			return
		}
		wlroutput.HandleRequest(conn, req, wlrOutputManager)
	}))

	mux.HandlePrefix("evdev.", requestHandler(func(conn *ipc.ConnWriter, req ipc.Request) {
		if evdevManager == nil {
			conn.RespondError(req.ID, "evdev manager not initialized")
			return
		}
		evdev.HandleRequest(conn, req, evdevManager)
	}))

	mux.HandlePrefix("dbus.", func(ctx context.Context, conn *ipc.ConnWriter, req ipc.Request, _ *ipc.Subscriber) {
		if dbusManager == nil {
			conn.RespondError(req.ID, "dbus manager not initialized")
			return
		}
		serverDbus.HandleRequest(ctx, conn, req, dbusManager, dbusClientID)
	})

	mux.HandlePrefix("clipboard.", requestHandler(func(conn *ipc.ConnWriter, req ipc.Request) {
		if clipboardManager == nil {
			conn.RespondError(req.ID, "clipboard manager not initialized")
			return
		}
		clipboard.HandleRequest(conn, req, clipboardManager)
	}))

	mux.HandlePrefix("location.", requestHandler(func(conn *ipc.ConnWriter, req ipc.Request) {
		if locationManager == nil {
			conn.RespondError(req.ID, "location manager not initialized")
			return
		}
		location.HandleRequest(conn, req, locationManager)
	}))

	mux.HandlePrefix("wellbeing.", requestHandler(func(conn *ipc.ConnWriter, req ipc.Request) {
		if wellbeingManager == nil {
			conn.RespondError(req.ID, "wellbeing manager not initialized")
			return
		}
		wellbeing.HandleRequest(conn, req, wellbeingManager)
	}))

	mux.HandlePrefix("notify.", requestHandler(func(conn *ipc.ConnWriter, req ipc.Request) {
		if notifyActionsManager == nil {
			conn.RespondError(req.ID, "notification action manager not initialized")
			return
		}
		notifyactions.HandleRequest(conn, req, notifyActionsManager)
	}))

	mux.HandlePrefix("sysupdate.", func(ctx context.Context, conn *ipc.ConnWriter, req ipc.Request, _ *ipc.Subscriber) {
		if sysUpdateManager == nil {
			conn.RespondError(req.ID, "sysupdate manager not initialized")
			return
		}
		sysupdate.HandleRequest(ctx, conn, req, sysUpdateManager)
	})

	mux.HandlePrefix("", requestHandler(func(conn *ipc.ConnWriter, req ipc.Request) {
		conn.RespondError(req.ID, fmt.Sprintf("unknown method: %s", req.Method))
	}))
	return mux
}

func handleClipboardSetConfig(conn *ipc.ConnWriter, req ipc.Request) {
	cfg := clipboard.LoadConfig()

	if v, ok := req.Get[float64]("maxHistory"); ok {
		cfg.MaxHistory = int(v)
	}
	if v, ok := req.Get[float64]("maxEntrySize"); ok {
		cfg.MaxEntrySize = int64(v)
	}
	if v, ok := req.Get[float64]("autoClearDays"); ok {
		cfg.AutoClearDays = int(v)
	}
	if v, ok := req.Get[bool]("clearAtStartup"); ok {
		cfg.ClearAtStartup = v
	}
	if v, ok := req.Get[bool]("disabled"); ok {
		cfg.Disabled = v
	}
	if v, ok := req.Get[float64]("maxPinned"); ok {
		cfg.MaxPinned = int(v)
	}

	save := clipboard.SaveConfig
	if clipboardManager != nil {
		save = clipboardManager.SetConfig
	}
	if err := save(cfg); err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}

	conn.Respond(req.ID, models.SuccessResult{Success: true, Message: "config updated"})
}
