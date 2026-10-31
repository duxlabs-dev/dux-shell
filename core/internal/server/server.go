package server

import (
	"context"
	"errors"
	"fmt"
	"runtime/debug"
	"slices"
	"sync"
	"time"

	"github.com/duxlabs-dev/dux-go/ipc"
	"github.com/duxlabs-dev/dux-go/syncmap"
	"github.com/duxlabs-dev/dux-shell/core/internal/clipolicy"
	"github.com/duxlabs-dev/dux-shell/core/internal/geolocation"
	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/duxlabs-dev/dux-shell/core/internal/matugen"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/apppicker"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/bluez"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/brightness"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/clipboard"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/cups"
	serverDbus "github.com/duxlabs-dev/dux-shell/core/internal/server/dbus"
	serverDgop "github.com/duxlabs-dev/dux-shell/core/internal/server/dgop"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/evdev"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/freedesktop"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/location"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/loginctl"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/network"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/notifyactions"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/sysupdate"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/tailscale"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/thememode"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/trayrecovery"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/wallpaper"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/wayland"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/wellbeing"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/wlcontext"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/wlroutput"
	"github.com/duxlabs-dev/dux-shell/core/internal/systemd"
	"github.com/duxlabs-dev/dux-shell/core/internal/utils"
	"github.com/spf13/afero"
)

const APIVersion = 38

var CLIVersion = "dev"

type Capabilities struct {
	Capabilities []string `json:"capabilities"`
}

type ServerInfo struct {
	APIVersion   int      `json:"apiVersion"`
	CLIVersion   string   `json:"cliVersion,omitempty"`
	Capabilities []string `json:"capabilities"`
}

type ServiceEvent struct {
	Service string `json:"service"`
	Data    any    `json:"data"`
}

var networkManager *network.Manager
var loginctlManager *loginctl.Manager
var freedesktopManager *freedesktop.Manager
var waylandManager *wayland.Manager
var bluezManager *bluez.Manager
var appPickerManager *apppicker.Manager
var cupsManager *cups.Manager
var tailscaleManager *tailscale.Manager
var brightnessManager *brightness.Manager
var wlrOutputManager *wlroutput.Manager
var evdevManager *evdev.Manager
var clipboardManager *clipboard.Manager
var dbusManager *serverDbus.Manager
var wlContext *wlcontext.SharedContext
var themeModeManager *thememode.Manager
var wallpaperManager *wallpaper.Manager
var trayRecoveryManager *trayrecovery.Manager
var locationManager *location.Manager
var sysUpdateManager *sysupdate.Manager
var notifyActionsManager *notifyactions.Manager
var wellbeingManager *wellbeing.Manager
var geoClientInstance geolocation.Client

const dbusClientID = "dms-dbus-client"

var capabilitySubscribers syncmap.Map[string, chan ServerInfo]
var cupsMu sync.Mutex
var cupsSubscriberCount int
var cupsEverAvailable bool

var appPaths = utils.App()

func GetSocketPath() string {
	return appPaths.SocketPath()
}

func InitializeNetworkManager() error {
	manager, err := network.NewManager()
	if err != nil {
		log.Warnf("Failed to initialize network manager: %v", err)
		return err
	}

	networkManager = manager

	log.Info("Network manager initialized")
	return nil
}

func InitializeLoginctlManager() error {
	keepLockOnUnlock, err := clipolicy.LogindUnlockDisabled(afero.NewOsFs())
	if err != nil {
		log.Errorf("CLI policy unreadable, keeping locks through logind Unlock: %v", err)
		keepLockOnUnlock = true
	}
	lockSettings, err := clipolicy.LockSettings(afero.NewOsFs())
	if err != nil {
		log.Errorf("CLI policy unreadable, ignoring its lock settings: %v", err)
	}
	manager, err := loginctl.NewManager(keepLockOnUnlock, loginctl.LockPolicy{
		LockBeforeSuspend:       clipolicy.LockSettingBool(lockSettings, "lockBeforeSuspend"),
		LoginctlLockIntegration: clipolicy.LockSettingBool(lockSettings, "loginctlLockIntegration"),
	})
	if err != nil {
		log.Warnf("Failed to initialize loginctl manager: %v", err)
		return err
	}

	loginctlManager = manager

	log.Info("Loginctl manager initialized")
	return nil
}

func InitializeFreedeskManager() error {
	manager, err := freedesktop.NewManager()
	if err != nil {
		log.Warnf("Failed to initialize freedesktop manager: %v", err)
		return err
	}

	freedesktopManager = manager
	matugen.SetColorSchemeEchoHook(manager.ExpectColorSchemeEcho)

	log.Info("Freedesktop manager initialized")
	return nil
}

func InitializeWaylandManager() error {
	log.Info("Attempting to initialize Wayland gamma control...")

	if wlContext == nil {
		ctx, err := wlcontext.New()
		if err != nil {
			log.Errorf("Failed to create shared Wayland context: %v", err)
			return err
		}
		wlContext = ctx
	}

	config := wayland.LoadConfig()
	manager, err := wayland.NewManager(wlContext.Display(), config)
	if err != nil {
		log.Errorf("Failed to initialize wayland manager: %v", err)
		return err
	}

	waylandManager = manager

	log.Info("Wayland gamma control initialized successfully")
	return nil
}

func InitializeBluezManager() error {
	manager, err := bluez.NewManager()
	if err != nil {
		log.Warnf("Failed to initialize bluez manager: %v", err)
		return err
	}

	bluezManager = manager

	log.Info("Bluez manager initialized")
	return nil
}

func InitializeAppPickerManager() error {
	manager := apppicker.NewManager()
	appPickerManager = manager
	log.Info("AppPicker manager initialized")
	return nil
}

// Reports whether the cups capability was newly gained, not whether a manager was created.
func initializeCupsManagerLocked() (bool, error) {
	if cupsManager != nil {
		return false, nil
	}
	manager, err := cups.NewManager()
	if err != nil {
		log.Warnf("Failed to initialize cups manager: %v", err)
		return false, err
	}
	cupsManager = manager
	log.Info("CUPS manager initialized")
	gained := !cupsEverAvailable
	cupsEverAvailable = true
	return gained, nil
}

func ensureCupsManager() (*cups.Manager, error) {
	cupsMu.Lock()
	gained, err := initializeCupsManagerLocked()
	mgr := cupsManager
	cupsMu.Unlock()
	if err != nil {
		return nil, err
	}
	if gained {
		notifyCapabilityChange()
	}
	return mgr, nil
}

// Sticky: the manager is torn down when nobody is subscribed, but CUPS itself stays available.
func cupsAvailable() bool {
	cupsMu.Lock()
	defer cupsMu.Unlock()
	return cupsEverAvailable
}

func releaseCupsSubscriber() {
	cupsMu.Lock()
	if cupsSubscriberCount > 0 {
		cupsSubscriberCount--
	}
	var mgr *cups.Manager
	if cupsSubscriberCount == 0 && cupsManager != nil {
		mgr = cupsManager
		cupsManager = nil
	}
	cupsMu.Unlock()
	if mgr == nil {
		return
	}
	log.Info("Last CUPS subscriber disconnected, shutting down CUPS manager")
	mgr.Close()
}

func InitializeBrightnessManager() error {
	manager, err := brightness.NewManager()
	if err != nil {
		log.Warnf("Failed to initialize brightness manager: %v", err)
		return err
	}

	brightnessManager = manager
	if waylandManager != nil {
		manager.AttachGamma(waylandManager)
	}

	log.Info("Brightness manager initialized")
	return nil
}

func InitializeWlrOutputManager() error {
	log.Info("Attempting to initialize WlrOutput management...")

	if wlContext == nil {
		ctx, err := wlcontext.New()
		if err != nil {
			log.Errorf("Failed to create shared Wayland context: %v", err)
			return err
		}
		wlContext = ctx
	}

	manager, err := wlroutput.NewManager(wlContext.Display())
	if err != nil {
		log.Debug("Failed to initialize wlroutput manager: %v", err)
		return err
	}

	wlrOutputManager = manager

	log.Info("WlrOutput management initialized successfully")
	return nil
}

func InitializeEvdevManager() error {
	manager, err := evdev.InitializeManager()
	if err != nil {
		log.Warnf("Failed to initialize evdev manager: %v", err)
		return err
	}

	evdevManager = manager

	log.Info("Evdev manager initialized")
	return nil
}

func InitializeClipboardManager() error {
	log.Info("Attempting to initialize clipboard manager...")

	if wlContext == nil {
		ctx, err := wlcontext.New()
		if err != nil {
			log.Errorf("Failed to create shared Wayland context: %v", err)
			return err
		}
		wlContext = ctx
	}

	config := clipboard.LoadConfig()
	manager, err := clipboard.NewManager(wlContext, config)
	if err != nil {
		log.Errorf("Failed to initialize clipboard manager: %v", err)
		return err
	}

	clipboardManager = manager

	log.Info("Clipboard manager initialized successfully")
	return nil
}

func InitializeDbusManager() error {
	manager, err := serverDbus.NewManager()
	if err != nil {
		log.Warnf("Failed to initialize dbus manager: %v", err)
		return err
	}

	dbusManager = manager

	log.Info("DBus manager initialized")
	return nil
}

func InitializeThemeModeManager() error {
	manager := thememode.NewManager()
	themeModeManager = manager

	log.Info("Theme mode automation manager initialized")
	return nil
}

func InitializeWallpaperManager() error {
	wallpaperManager = wallpaper.NewManager()

	log.Info("Wallpaper rotation scheduler initialized")
	return nil
}

func InitializeTrayRecoveryManager() error {
	manager, err := trayrecovery.NewManager()
	if err != nil {
		return err
	}

	trayRecoveryManager = manager
	manager.WatchWatcherOwner()

	log.Info("TrayRecovery manager initialized")
	return nil
}

func InitializeWellbeingManager() error {
	manager, err := wellbeing.NewManager()
	if err != nil {
		return err
	}
	wellbeingManager = manager
	log.Info("Wellbeing manager initialized")
	return nil
}

func InitializeLocationManager(geoClient geolocation.Client) error {
	manager, err := location.NewManager(geoClient)
	if err != nil {
		log.Warnf("Failed to initialize location manager: %v", err)
		return err
	}

	locationManager = manager

	log.Info("Location manager initialized")
	return nil
}

func InitializeNotifyActionsManager() error {
	manager, err := notifyactions.NewManager()
	if err != nil {
		return err
	}
	notifyActionsManager = manager
	log.Info("Notification action manager initialized")
	return nil
}

func InitializeSysUpdateManager() error {
	manager, err := sysupdate.NewManager(CLIVersion)
	if err != nil {
		log.Warnf("Failed to initialize sysupdate manager: %v", err)
		return err
	}

	sysUpdateManager = manager

	log.Info("Sysupdate manager initialized")
	return nil
}

func routeHandler(mux *ipc.Mux) ipc.Handler {
	return func(ctx context.Context, conn *ipc.ConnWriter, req ipc.Request, _ *ipc.Subscriber) {
		routeRequestRecovered(ctx, conn, req, mux)
	}
}

func subscribeHandler(ctx context.Context, conn *ipc.ConnWriter, req ipc.Request, _ *ipc.Subscriber) {
	switch req.Method {
	case "subscribe":
		routeRequestRecovered(ctx, conn, req, requestMux)
	default:
		conn.RespondError(req.ID, fmt.Sprintf("unknown method: %s", req.Method))
	}
}

// routeRequestRecovered keeps a panicking handler from taking down the whole daemon
func routeRequestRecovered(ctx context.Context, conn *ipc.ConnWriter, req ipc.Request, mux *ipc.Mux) {
	defer func() {
		if r := recover(); r != nil {
			log.Errorf("RouteRequest panic recovered: method=%s panic=%v\n%s", req.Method, r, debug.Stack())
			conn.RespondError(req.ID, "internal server error")
		}
	}()
	mux.ServeIPC(ctx, conn, req, nil)
}

func getCapabilities() Capabilities {
	caps := []string{"plugins", "dgop", "drives", "lyrics", "lyrics.plugins"}

	if networkManager != nil {
		caps = append(caps, "network")
	}

	if loginctlManager != nil {
		caps = append(caps, "loginctl")
	}

	if freedesktopManager != nil {
		caps = append(caps, "freedesktop")
	}

	if waylandManager != nil {
		caps = append(caps, "gamma")
	}

	if bluezManager != nil {
		caps = append(caps, "bluetooth")
	}

	if appPickerManager != nil {
		caps = append(caps, "browser")
	}

	if cupsAvailable() {
		caps = append(caps, "cups")
	}

	if tailscaleManager != nil && tailscaleManager.IsAvailable() {
		caps = append(caps, "tailscale")
	}

	if brightnessManager != nil {
		caps = append(caps, "brightness")
	}

	if wlrOutputManager != nil {
		caps = append(caps, "wlroutput")
	}

	if evdevManager != nil {
		caps = append(caps, "evdev")
	}

	if clipboardManager != nil {
		caps = append(caps, "clipboard")
	}

	if themeModeManager != nil {
		caps = append(caps, "theme.auto")
	}

	if wallpaperManager != nil {
		caps = append(caps, "wallpaper")
	}

	if locationManager != nil {
		caps = append(caps, "location")
	}

	if wellbeingManager != nil {
		caps = append(caps, "wellbeing")
	}

	if dbusManager != nil {
		caps = append(caps, "dbus")
	}

	if sysUpdateManager != nil {
		caps = append(caps, "sysupdate")
	}

	if filesService != nil {
		caps = append(caps, "files")
	}

	return Capabilities{Capabilities: caps}
}

func getServerInfo() ServerInfo {
	return ServerInfo{
		APIVersion:   APIVersion,
		CLIVersion:   CLIVersion,
		Capabilities: getCapabilities().Capabilities,
	}
}

func notifyCapabilityChange() {
	info := getServerInfo()
	capabilitySubscribers.Range(func(key string, ch chan ServerInfo) bool {
		select {
		case ch <- info:
		default:
		}
		return true
	})
}

func serviceSubscribed(services []string, service string, includeAll bool) bool {
	return slices.Contains(services, service) || includeAll && slices.Contains(services, "all")
}

func handleSubscribe(ctx context.Context, conn *ipc.ConnWriter, req ipc.Request) {
	clientID := fmt.Sprintf("meta-client-%p", conn)

	dbusClient := dbusClientID
	if id, ok := req.Get[string]("clientId"); ok && id != "" {
		dbusClient = id
	}

	var services []string
	if servicesParam, ok := req.Get[[]any]("services"); ok {
		for _, s := range servicesParam {
			if str, ok := s.(string); ok {
				services = append(services, str)
			}
		}
	}

	if len(services) == 0 {
		services = []string{"all"}
	}

	subscribeAll := slices.Contains(services, "all")

	var wg sync.WaitGroup
	eventChan := make(chan ServiceEvent, 256)
	stopChan := make(chan struct{})
	stop := sync.OnceFunc(func() { close(stopChan) })
	stopContext := context.AfterFunc(ctx, stop)
	defer func() {
		stopContext()
		stop()
		wg.Wait()
	}()

	capChan := make(chan ServerInfo, 64)
	capabilitySubscribers.Store(clientID+"-capabilities", capChan)

	forwardSubscription(&wg, eventChan, stopChan, "server", capChan, func() {
		capabilitySubscribers.Delete(clientID + "-capabilities")
	}, nil)

	shouldSubscribe := func(service string) bool {
		return serviceSubscribed(services, service, subscribeAll)
	}

	if shouldSubscribe("network") && networkManager != nil {
		mgr := networkManager
		id := clientID + "-network"
		states := mgr.Subscribe(id)
		forwardSubscription(&wg, eventChan, stopChan, "network", states, func() {
			mgr.Unsubscribe(id)
		}, mgr.GetState)
	}

	if shouldSubscribe("network.credentials") && networkManager != nil {
		mgr := networkManager
		id := clientID + "-credentials"
		prompts := mgr.SubscribeCredentials(id)
		forwardSubscription(&wg, eventChan, stopChan, "network.credentials", prompts, func() {
			mgr.UnsubscribeCredentials(id)
		}, nil)
	}

	if shouldSubscribe("loginctl") && loginctlManager != nil {
		mgr := loginctlManager
		id := clientID + "-loginctl"
		source := mgr.Subscribe(id)
		forwardSubscription(&wg, eventChan, stopChan, "loginctl", source, func() {
			mgr.Unsubscribe(id)
		}, mgr.GetState)
	}

	if shouldSubscribe("freedesktop") && freedesktopManager != nil {
		mgr := freedesktopManager
		id := clientID + "-freedesktop"
		source := mgr.Subscribe(id)
		forwardSubscription(&wg, eventChan, stopChan, "freedesktop", source, func() {
			mgr.Unsubscribe(id)
		}, mgr.GetState)
	}

	if shouldSubscribe("freedesktop.screensaver") && freedesktopManager != nil {
		mgr := freedesktopManager
		id := clientID + "-screensaver"
		source := mgr.SubscribeScreensaver(id)
		forwardSubscription(&wg, eventChan, stopChan, "freedesktop.screensaver", source, func() {
			mgr.UnsubscribeScreensaver(id)
		}, mgr.GetScreensaverState)
	}

	if shouldSubscribe("gamma") && waylandManager != nil {
		mgr := waylandManager
		id := clientID + "-gamma"
		source := mgr.Subscribe(id)
		forwardSubscription(&wg, eventChan, stopChan, "gamma", source, func() {
			mgr.Unsubscribe(id)
		}, mgr.GetState)
	}

	if shouldSubscribe("theme.auto") && themeModeManager != nil {
		mgr := themeModeManager
		id := clientID + "-theme-auto"
		source := mgr.Subscribe(id)
		forwardSubscription(&wg, eventChan, stopChan, "theme.auto", source, func() {
			mgr.Unsubscribe(id)
		}, mgr.GetState)
	}

	if shouldSubscribe("wallpaper") && wallpaperManager != nil {
		mgr := wallpaperManager
		id := clientID + "-wallpaper"
		source := mgr.Subscribe(id)
		forwardSubscription(&wg, eventChan, stopChan, "wallpaper", source, func() {
			mgr.Unsubscribe(id)
		}, mgr.GetState)
	}

	if shouldSubscribe("bluetooth") && bluezManager != nil {
		mgr := bluezManager
		id := clientID + "-bluetooth"
		source := mgr.Subscribe(id)
		forwardSubscription(&wg, eventChan, stopChan, "bluetooth", source, func() {
			mgr.Unsubscribe(id)
		}, mgr.GetState)
	}

	if serviceSubscribed(services, "mpris.command", false) && bluezManager != nil {
		mgr := bluezManager
		id := clientID + "-mpris-command"
		commands, err := mgr.SubscribePlayerCommands(id)
		if err != nil {
			log.Warnf("MPRIS command subscription rejected: %v", err)
		} else {
			forwardSubscription(&wg, eventChan, stopChan, "mpris.command", commands, func() {
				mgr.UnsubscribePlayerCommands(id)
			}, nil)
		}
	}

	if shouldSubscribe("bluetooth.pairing") && bluezManager != nil {
		mgr := bluezManager
		id := clientID + "-pairing"
		source := mgr.SubscribePairing(id)
		forwardSubscription(&wg, eventChan, stopChan, "bluetooth.pairing", source, func() {
			mgr.UnsubscribePairing(id)
		}, nil)
	}

	if shouldSubscribe("browser") && appPickerManager != nil {
		mgr := appPickerManager
		id := clientID + "-browser"
		source := mgr.Subscribe(id)
		forwardSubscription(&wg, eventChan, stopChan, "browser.open_requested", source, func() {
			mgr.Unsubscribe(id)
		}, nil)
	}

	if shouldSubscribe("cups") {
		subscribeCups(&wg, eventChan, stopChan, clientID)
	}

	if shouldSubscribe("tailscale") && tailscaleManager != nil && tailscaleManager.IsAvailable() {
		mgr := tailscaleManager
		id := clientID + "-tailscale"
		source := mgr.Subscribe(id)
		forwardSubscription(&wg, eventChan, stopChan, "tailscale", source, func() {
			mgr.Unsubscribe(id)
		}, mgr.GetState)
	}

	if shouldSubscribe("brightness") && brightnessManager != nil {
		mgr := brightnessManager
		stateID := clientID + "-brightness-state"
		updateID := clientID + "-brightness-updates"
		states := mgr.Subscribe(stateID)
		updates := mgr.SubscribeUpdates(updateID)
		forwardSubscription(&wg, eventChan, stopChan, "brightness", states, func() {
			mgr.Unsubscribe(stateID)
		}, mgr.GetState)
		forwardSubscription(&wg, eventChan, stopChan, "brightness.update", updates, func() {
			mgr.UnsubscribeUpdates(updateID)
		}, nil)
	}

	if shouldSubscribe("wlroutput") && wlrOutputManager != nil {
		mgr := wlrOutputManager
		id := clientID + "-wlroutput"
		source := mgr.Subscribe(id)
		forwardSubscription(&wg, eventChan, stopChan, "wlroutput", source, func() {
			mgr.Unsubscribe(id)
		}, mgr.GetState)
	}

	if shouldSubscribe("evdev") && evdevManager != nil {
		mgr := evdevManager
		id := clientID + "-evdev"
		source := mgr.Subscribe(id)
		forwardSubscription(&wg, eventChan, stopChan, "evdev", source, func() {
			mgr.Unsubscribe(id)
		}, mgr.GetState)
	}

	if shouldSubscribe("clipboard") && clipboardManager != nil {
		mgr := clipboardManager
		id := clientID + "-clipboard"
		source := mgr.Subscribe(id)
		forwardSubscription(&wg, eventChan, stopChan, "clipboard", source, func() {
			mgr.Unsubscribe(id)
		}, mgr.GetState)
	}

	if shouldSubscribe("location") && locationManager != nil {
		mgr := locationManager
		id := clientID + "-location"
		source := mgr.Subscribe(id)
		forwardSubscription(&wg, eventChan, stopChan, "location", source, func() {
			mgr.Unsubscribe(id)
		}, mgr.GetState)
	}

	if shouldSubscribe("wellbeing") && wellbeingManager != nil {
		mgr := wellbeingManager
		id := clientID + "-wellbeing"
		source := mgr.Subscribe(id)
		forwardSubscription(&wg, eventChan, stopChan, "wellbeing", source, func() {
			mgr.Unsubscribe(id)
		}, mgr.Snapshot)
	}

	if shouldSubscribe("sysupdate") && sysUpdateManager != nil {
		mgr := sysUpdateManager
		id := clientID + "-sysupdate"
		source := mgr.Subscribe(id)
		forwardSubscription(&wg, eventChan, stopChan, "sysupdate", source, func() {
			mgr.Unsubscribe(id)
		}, mgr.GetState)
	}

	if shouldSubscribe("files") && filesService != nil {
		id := clientID + "-files"
		source := filesEvents.Subscribe(id)
		forwardSubscription(&wg, eventChan, stopChan, "files", source, func() {
			filesEvents.Unsubscribe(id)
		}, nil)
	}

	if shouldSubscribe("dbus") && dbusManager != nil {
		mgr := dbusManager
		events := mgr.SubscribeSignals(dbusClient)
		forwardSubscription(&wg, eventChan, stopChan, "dbus", events, func() {
			mgr.UnsubscribeSignals(dbusClient, events)
		}, nil)
	}

	go func() {
		wg.Wait()
		close(eventChan)
	}()

	info := getServerInfo()
	if err := conn.WriteResponse(ipc.Response[ServiceEvent]{
		ID:     req.ID,
		Result: &ServiceEvent{Service: "server", Data: info},
	}); err != nil {
		return
	}

	for {
		select {
		case <-ctx.Done():
			return
		case event, ok := <-eventChan:
			if !ok {
				return
			}
			if err := conn.WriteResponse(ipc.Response[ServiceEvent]{
				ID:     req.ID,
				Result: &event,
			}); err != nil {
				return
			}
		}
	}
}

func subscribeCups(wg *sync.WaitGroup, events chan<- ServiceEvent, stop <-chan struct{}, clientID string) {
	cupsMu.Lock()
	cupsSubscriberCount++
	gained, err := initializeCupsManagerLocked()
	mgr := cupsManager
	cupsMu.Unlock()

	if err != nil {
		log.Warnf("Failed to initialize CUPS manager for subscription: %v", err)
	}
	if gained {
		notifyCapabilityChange()
	}
	if mgr == nil {
		releaseCupsSubscriber()
		return
	}

	id := clientID + "-cups"
	states := mgr.Subscribe(id)
	forwardSubscription(wg, events, stop, "cups", states, func() {
		mgr.Unsubscribe(id)
		releaseCupsSubscriber()
	}, mgr.GetState)
}

func cleanupManagers() {
	if networkManager != nil {
		networkManager.Close()
	}
	if loginctlManager != nil {
		loginctlManager.Close()
	}
	if freedesktopManager != nil {
		freedesktopManager.Close()
	}
	if waylandManager != nil {
		waylandManager.Close()
	}
	if bluezManager != nil {
		bluezManager.Close()
	}
	if appPickerManager != nil {
		appPickerManager.Close()
	}
	cupsMu.Lock()
	if cupsManager != nil {
		cupsManager.Close()
		cupsManager = nil
	}
	cupsMu.Unlock()
	if brightnessManager != nil {
		brightnessManager.Close()
	}
	if wlrOutputManager != nil {
		wlrOutputManager.Close()
	}
	if evdevManager != nil {
		evdevManager.Close()
	}
	if clipboardManager != nil {
		clipboardManager.Close()
	}
	if dbusManager != nil {
		dbusManager.Close()
	}
	if notifyActionsManager != nil {
		notifyActionsManager.Close()
	}
	if themeModeManager != nil {
		themeModeManager.Close()
	}
	if wallpaperManager != nil {
		wallpaperManager.Close()
	}
	if trayRecoveryManager != nil {
		trayRecoveryManager.Close()
	}
	if wlContext != nil {
		wlContext.Close()
	}
	if locationManager != nil {
		locationManager.Close()
	}
	if sysUpdateManager != nil {
		sysUpdateManager.Close()
	}
	if wellbeingManager != nil {
		wellbeingManager.Close()
	}
	if geoClientInstance != nil {
		geoClientInstance.Close()
	}
	if tailscaleManager != nil {
		tailscaleManager.Close()
	}
	if filesService != nil {
		filesService.Close()
	}
	serverDgop.Close()
}

type Server struct {
	ipc       *ipc.Server
	readiness *systemd.Readiness
}

func New() *Server {
	s := &Server{readiness: systemd.NewReadiness()}
	s.ipc = ipc.NewServer(ipc.Config{
		AppName:          appPaths.Name,
		APIVersion:       APIVersion,
		CapabilitiesFunc: func() []string { return getCapabilities().Capabilities },
		MaxLineSize:      64 * 1024 * 1024, // large clipboard payloads
		SubscribeHandler: subscribeHandler,
	}, routeHandler(newRequestMux(s.readiness)))
	return s
}

func (s *Server) WaitReady(ctx context.Context) { s.readiness.Wait(ctx) }

func (s *Server) Listen() error { return s.ipc.Listen() }

func (s *Server) SocketPath() string { return s.ipc.SocketPath() }

func (s *Server) Close() {
	s.ipc.Close()
}

func Start(printDocs bool) error {
	s := New()
	if err := s.Listen(); err != nil {
		return err
	}
	return s.Serve(printDocs)
}

func (s *Server) Serve(printDocs bool) error {
	defer s.ipc.Close()
	defer cleanupManagers()

	tuneRuntime()
	startPprof()

	// Tailscale manager always starts — reconnects internally via WatchIPNBus.
	// The capability is only advertised once tailscaled is reachable; the
	// callback wakes capability subscribers so QML clients see it transition.
	tailscaleManager = tailscale.NewManager("")
	tailscaleManager.SetAvailabilityCallback(func(bool) {
		notifyCapabilityChange()
	})

	log.Infof("DMS API Server listening on: %s", s.ipc.SocketPath())
	log.Infof("API Version: %d", APIVersion)
	log.Info("Protocol: JSON over Unix socket")
	log.Info("Request format: {\"id\": <any>, \"method\": \"...\", \"params\": {...}}")
	log.Info("Response format: {\"id\": <any>, \"result\": {...}} or {\"id\": <any>, \"error\": \"...\"}")
	log.Info("")
	if printDocs {
		log.Info("Available methods:")
		log.Info("  ping          - Test connection")
		log.Info("  getServerInfo - Get server info (API version and capabilities)")
		log.Info("  subscribe     - Subscribe to multiple services (params: services [default: all])")
		log.Info("Plugins:")
		log.Info(" plugins.list                - List all plugins")
		log.Info(" plugins.listInstalled       - List installed plugins")
		log.Info(" plugins.install             - Install plugin (params: name)")
		log.Info(" plugins.uninstall           - Uninstall plugin (params: name)")
		log.Info(" plugins.update              - Update plugin (params: name)")
		log.Info(" plugins.search              - Search plugins (params: query, category?, compositor?, capability?)")
		log.Info("Network:")
		log.Info(" network.getState            - Get current network state")
		log.Info(" network.wifi.scan           - Scan for WiFi networks (params: device?)")
		log.Info(" network.wifi.networks       - Get WiFi network list")
		log.Info(" network.wifi.connect        - Connect to WiFi (params: ssid, password?, username?, device?, eapMethod?, phase2Auth?, caCertPath?, clientCertPath?, privateKeyPath?, useSystemCACerts?)")
		log.Info(" network.wifi.disconnect     - Disconnect WiFi (params: device?)")
		log.Info(" network.wifi.forget         - Forget network (params: ssid)")
		log.Info(" network.wifi.toggle         - Toggle WiFi radio")
		log.Info(" network.wifi.enable         - Enable WiFi")
		log.Info(" network.wifi.disable        - Disable WiFi")
		log.Info(" network.wifi.setAutoconnect - Set network autoconnect (params: ssid, autoconnect)")
		log.Info(" network.ethernet.connect    - Connect Ethernet")
		log.Info(" network.ethernet.connect.config - Connect Ethernet to a specific configuration")
		log.Info(" network.ethernet.disconnect - Disconnect Ethernet")
		log.Info(" network.cellular.connect    - Connect Cellular")
		log.Info(" network.cellular.connect.config - Connect Cellular to a specific configuration (params: uuid)")
		log.Info(" network.cellular.disconnect - Disconnect Cellular (params: device?)")
		log.Info(" network.cellular.toggle     - Toggle Cellular radio")
		log.Info(" network.cellular.enable     - Enable Cellular")
		log.Info(" network.cellular.disable    - Disable Cellular")
		log.Info(" network.vpn.profiles        - List VPN profiles")
		log.Info(" network.vpn.active          - List active VPN connections")
		log.Info(" network.vpn.connect         - Connect VPN (params: uuidOrName|name|uuid, singleActive?)")
		log.Info(" network.vpn.disconnect      - Disconnect VPN (params: uuidOrName|name|uuid)")
		log.Info(" network.vpn.disconnectAll   - Disconnect all VPNs")
		log.Info(" network.vpn.clearCredentials - Clear saved VPN credentials (params: uuidOrName|name|uuid)")
		log.Info(" network.vpn.plugins         - List available VPN plugins")
		log.Info(" network.vpn.import          - Import VPN from file (params: file|path, name?)")
		log.Info(" network.vpn.getConfig       - Get VPN configuration (params: uuid|name|uuidOrName)")
		log.Info(" network.vpn.updateConfig    - Update VPN configuration (params: uuid, name?, autoconnect?, data?)")
		log.Info(" network.vpn.delete          - Delete VPN connection (params: uuid|name|uuidOrName)")
		log.Info(" network.preference.set      - Set preference (params: preference [auto|wifi|ethernet|cellular])")
		log.Info(" network.info                - Get network info (params: ssid)")
		log.Info(" network.credentials.submit  - Submit credentials for prompt (params: token, secrets, save?)")
		log.Info(" network.credentials.cancel  - Cancel credential prompt (params: token)")
		log.Info(" network.subscribe           - Subscribe to network state changes (streaming)")
		log.Info("Loginctl:")
		log.Info(" loginctl.getState           - Get current session state")
		log.Info(" loginctl.lock               - Lock session")
		log.Info(" loginctl.unlock             - Unlock session")
		log.Info(" loginctl.activate           - Activate session")
		log.Info(" loginctl.setIdleHint        - Set idle hint (params: idle)")
		log.Info(" loginctl.setLockBeforeSuspend - Set lock before suspend (params: enabled)")
		log.Info(" loginctl.setSleepInhibitorEnabled - Enable/disable sleep inhibitor (params: enabled)")
		log.Info(" loginctl.lockerReady        - Signal locker UI is ready (releases sleep inhibitor)")
		log.Info(" loginctl.terminate          - Terminate session")
		log.Info(" loginctl.subscribe          - Subscribe to session state changes (streaming)")
		log.Info("Freedesktop:")
		log.Info(" freedesktop.getState                  - Get accounts & settings state")
		log.Info(" freedesktop.accounts.setIconFile      - Set profile icon (params: path)")
		log.Info(" freedesktop.accounts.setRealName      - Set real name (params: name)")
		log.Info(" freedesktop.accounts.setEmail         - Set email (params: email)")
		log.Info(" freedesktop.accounts.setLanguage      - Set language (params: language)")
		log.Info(" freedesktop.accounts.setLocation      - Set location (params: location)")
		log.Info(" freedesktop.accounts.getUserIconFile  - Get user icon (params: username)")
		log.Info(" freedesktop.settings.getColorScheme   - Get color scheme")
		log.Info(" freedesktop.settings.setIconTheme     - Set icon theme (params: iconTheme)")
		log.Info("Wayland:")
		log.Info(" wayland.gamma.getState                - Get current gamma control state")
		log.Info(" wayland.gamma.setTemperature          - Set temperature range (params: low, high)")
		log.Info(" wayland.gamma.setLocation             - Set location (params: latitude, longitude)")
		log.Info(" wayland.gamma.setManualTimes          - Set manual times (params: sunrise, sunset, durationMinutes)")
		log.Info(" wayland.gamma.setGamma                - Set gamma and contrast (params: gamma, contrast)")
		log.Info(" wayland.gamma.setEnabled              - Enable/disable gamma control (params: enabled)")
		log.Info(" wayland.gamma.subscribe               - Subscribe to gamma state changes (streaming)")
		log.Info("Theme automation:")
		log.Info(" theme.auto.getState                   - Get current theme automation state")
		log.Info(" theme.auto.setEnabled                 - Enable/disable theme automation (params: enabled)")
		log.Info(" theme.auto.setMode                    - Set automation mode (params: mode [time|location])")
		log.Info(" theme.auto.setSchedule                - Set time schedule (params: startHour, startMinute, endHour, endMinute)")
		log.Info(" theme.auto.setLocation                - Set location (params: latitude, longitude)")
		log.Info(" theme.auto.setUseIPLocation           - Use IP location (params: use)")
		log.Info(" theme.auto.trigger                    - Trigger immediate re-evaluation")
		log.Info(" theme.auto.subscribe                  - Subscribe to theme automation state changes (streaming)")
		log.Info("Bluetooth:")
		log.Info(" bluetooth.getState                    - Get current bluetooth state")
		log.Info(" bluetooth.startDiscovery              - Start device discovery (params: adapter?)")
		log.Info(" bluetooth.stopDiscovery               - Stop device discovery (params: adapter?)")
		log.Info(" bluetooth.setPowered                  - Set adapter power state (params: powered, adapter?)")
		log.Info(" bluetooth.togglePowered               - Toggle adapter power state from its live value (params: adapter?)")
		log.Info(" bluetooth.pair                        - Pair with device (params: device)")
		log.Info(" bluetooth.connect                     - Connect to device (params: device)")
		log.Info(" bluetooth.disconnect                  - Disconnect from device (params: device)")
		log.Info(" bluetooth.remove                      - Remove/unpair device (params: device)")
		log.Info(" bluetooth.trust                       - Trust device (params: device)")
		log.Info(" bluetooth.untrust                     - Untrust device (params: device)")
		log.Info(" bluetooth.pairing.submit              - Submit pairing response (params: token, secrets?, accept?)")
		log.Info(" bluetooth.pairing.cancel              - Cancel pairing prompt (params: token)")
		log.Info(" bluetooth.subscribe                   - Subscribe to bluetooth state changes (streaming)")
		log.Info("CUPS:")
		log.Info(" cups.getPrinters                      - Get printers list")
		log.Info(" cups.getJobs                          - Get non-completed jobs list (params: printerName)")
		log.Info(" cups.pausePrinter                     - Pause printer (params: printerName)")
		log.Info(" cups.resumePrinter                    - Resume printer (params: printerName)")
		log.Info(" cups.cancelJob                        - Cancel job (params: printerName, jobID)")
		log.Info(" cups.purgeJobs                        - Cancel all jobs (params: printerName)")
		log.Info("Brightness:")
		log.Info(" brightness.getState                   - Get current brightness state for all devices")
		log.Info(" brightness.setBrightness              - Set device brightness (params: device, percent)")
		log.Info(" brightness.increment                  - Increment device brightness (params: device, step?)")
		log.Info(" brightness.decrement                  - Decrement device brightness (params: device, step?)")
		log.Info(" brightness.rescan                     - Rescan for brightness devices (e.g., after plugging in monitor)")
		log.Info(" brightness.subscribe                  - Subscribe to brightness state changes (streaming)")
		log.Info("   Subscription events:")
		log.Info("     - brightness       : Full device list (on rescan, DDC discovery, device changes)")
		log.Info("     - brightness.update: Single device update (on brightness change for efficiency)")
		log.Info("WlrOutput:")
		log.Info(" wlroutput.getState                    - Get current output configuration state")
		log.Info(" wlroutput.applyConfiguration          - Apply output configuration (params: heads)")
		log.Info(" wlroutput.testConfiguration           - Test output configuration without applying (params: heads)")
		log.Info(" wlroutput.subscribe                   - Subscribe to output state changes (streaming)")
		log.Info("   Head configuration params:")
		log.Info("     - name         : Output name (required)")
		log.Info("     - enabled      : Enable/disable output (required)")
		log.Info("     - modeId       : Mode ID from available modes (optional)")
		log.Info("     - customMode   : Custom mode {width, height, refresh} (optional)")
		log.Info("     - position     : Position {x, y} (optional)")
		log.Info("     - transform    : Transform value (optional)")
		log.Info("     - scale        : Scale value (optional)")
		log.Info("     - adaptiveSync : Adaptive sync state (optional)")
		log.Info("Evdev:")
		log.Info(" evdev.getState                        - Get current evdev state (caps lock)")
		log.Info(" evdev.subscribe                       - Subscribe to evdev state changes (streaming)")
		log.Info("Clipboard:")
		log.Info(" clipboard.getState                    - Get clipboard state (enabled, history, current)")
		log.Info(" clipboard.getHistory                  - Get clipboard history with previews")
		log.Info(" clipboard.getEntry                    - Get full entry by ID (params: id)")
		log.Info(" clipboard.deleteEntry                 - Delete entry by ID (params: id)")
		log.Info(" clipboard.deleteEntries               - Delete entries by ID, skipping pinned ones (params: ids)")
		log.Info(" clipboard.clearHistory                - Clear all clipboard history")
		log.Info(" clipboard.copy                        - Copy text to clipboard (params: text)")
		log.Info(" clipboard.paste                       - Get current clipboard text")
		log.Info(" clipboard.search                      - Search history (params: query?, mimeType?, isImage?, limit?, offset?, before?, after?)")
		log.Info(" clipboard.getConfig                   - Get clipboard configuration")
		log.Info(" clipboard.setConfig                   - Set configuration (params: maxHistory?, maxEntrySize?, autoClearDays?, clearAtStartup?, disabled?, maxPinned?)")
		log.Info(" clipboard.subscribe                   - Subscribe to clipboard state changes (streaming)")
		log.Info("Notify:")
		log.Info(" notify.watchAction                    - Open a file when a notification action fires (params: id, path)")
		log.Info("Location:")
		log.Info(" location.getState                      - Get current location state")
		log.Info(" location.subscribe                     - Subscribe to location changes (streaming)")
		log.Info("Wellbeing:")
		log.Info(" wellbeing.getState                     - Today's screen time per app")
		log.Info(" wellbeing.setState                     - Report the focused app and whether the session is active (params: appId?, active, seq?)")
		log.Info(" wellbeing.setLimits                    - Set daily and per-app limits in seconds (params: daily?, apps?)")
		log.Info(" wellbeing.summary                      - Per-day screen time ending today (params: days?)")
		log.Info(" wellbeing.clear                        - Delete the screen time history")
		log.Info("")
	}
	log.Info("Initializing managers...")
	log.Info("")

	go func() {
		switch err := InitializeNetworkManager(); {
		case err == nil:
			notifyCapabilityChange()
			return
		case errors.Is(err, network.ErrNoNetworkBackend):
			log.Warn("No supported network backend present; skipping retries")
			return
		default:
			log.Warnf("Network manager unavailable, will retry: %v", err)
		}

		ticker := time.NewTicker(30 * time.Second)
		defer ticker.Stop()

		for range 10 {
			<-ticker.C
			if networkManager != nil {
				return
			}
			switch err := InitializeNetworkManager(); {
			case err == nil:
				log.Info("Network manager initialized")
				notifyCapabilityChange()
				return
			case errors.Is(err, network.ErrNoNetworkBackend):
				log.Warn("No supported network backend present; stopping retries")
				return
			}
		}
		log.Warn("Network manager still unavailable after retries; giving up")
	}()

	loginctlReady := make(chan struct{})
	freedesktopReady := make(chan struct{})

	go func() {
		defer close(loginctlReady)
		if err := InitializeLoginctlManager(); err != nil {
			log.Warnf("Loginctl manager unavailable: %v", err)
		} else {
			notifyCapabilityChange()
		}
	}()

	go func() {
		defer close(freedesktopReady)
		if err := InitializeFreedeskManager(); err != nil {
			log.Warnf("Freedesktop manager unavailable: %v", err)
		} else if freedesktopManager != nil {
			freedesktopManager.NotifySubscribers()
			notifyCapabilityChange()
		}
	}()

	// Bridge loginctl lock state to the freedesktop/gnome screensaver
	// ActiveChanged signal so apps like Bitwarden can detect screen lock.
	go func() {
		<-loginctlReady
		<-freedesktopReady

		if loginctlManager == nil || freedesktopManager == nil {
			return
		}

		ch := loginctlManager.Subscribe("dms-lock-bridge")
		defer loginctlManager.Unsubscribe("dms-lock-bridge")

		initial := loginctlManager.GetState()
		lastLocked := initial.Locked
		freedesktopManager.SetScreenLockActive(lastLocked)

		for state := range ch {
			if state.Locked != lastLocked {
				lastLocked = state.Locked
				freedesktopManager.SetScreenLockActive(lastLocked)
			}
		}
	}()

	if err := InitializeWaylandManager(); err != nil {
		log.Warnf("Wayland manager unavailable: %v", err)
	}

	if err := InitializeThemeModeManager(); err != nil {
		log.Warnf("Theme mode manager unavailable: %v", err)
	} else {
		notifyCapabilityChange()
		go func() {
			<-loginctlReady
			if loginctlManager == nil {
				return
			}
			themeModeManager.WatchLoginctl(loginctlManager)
		}()
	}

	if err := InitializeWellbeingManager(); err != nil {
		log.Warnf("Wellbeing manager unavailable: %v", err)
	}

	if err := InitializeWallpaperManager(); err != nil {
		log.Warnf("Wallpaper scheduler unavailable: %v", err)
	} else {
		notifyCapabilityChange()
		go func() {
			<-loginctlReady
			if loginctlManager == nil {
				return
			}
			wallpaperManager.WatchLoginctl(loginctlManager)
		}()
	}

	go func() {
		<-loginctlReady
		if loginctlManager == nil {
			return
		}
		if err := InitializeTrayRecoveryManager(); err != nil {
			log.Warnf("TrayRecovery manager unavailable: %v", err)
		} else {
			trayRecoveryManager.WatchLoginctl(loginctlManager)
		}
	}()

	go func() {
		geoClient := geolocation.NewClient()
		geoClientInstance = geoClient

		if waylandManager != nil {
			waylandManager.SetGeoClient(geoClient)
		}
		if themeModeManager != nil {
			themeModeManager.SetGeoClient(geoClient)
		}

		if err := InitializeLocationManager(geoClient); err != nil {
			log.Warnf("Location manager unavailable: %v", err)
		} else {
			notifyCapabilityChange()
		}
	}()

	go func() {
		for {
			err := InitializeBluezManager()
			if err == nil {
				notifyCapabilityChange()
				return
			}
			log.Warnf("Bluez manager unavailable: %v", err)
			if !errors.Is(err, bluez.ErrNoAdapter) {
				return
			}
			if err := bluez.WaitForAdapter(); err != nil {
				log.Warnf("Bluetooth adapter watch failed: %v", err)
				return
			}
			log.Info("Bluetooth adapter appeared, initializing bluez manager")
		}
	}()

	if err := InitializeAppPickerManager(); err != nil {
		log.Debugf("AppPicker manager unavailable: %v", err)
	}

	InitializeFilesService()

	if err := InitializeWlrOutputManager(); err != nil {
		log.Debugf("WlrOutput manager unavailable: %v", err)
	}

	fatalErrChan := make(chan error, 1)
	if wlrOutputManager != nil {
		go func() {
			err := <-wlrOutputManager.FatalError()
			fatalErrChan <- fmt.Errorf("WlrOutput fatal error: %w", err)
		}()
	}
	if wlContext != nil {
		go func() {
			err := <-wlContext.FatalError()
			fatalErrChan <- fmt.Errorf("wayland context fatal error: %w", err)
		}()
	}

	go func() {
		if err := InitializeBrightnessManager(); err != nil {
			log.Warnf("Brightness manager unavailable: %v", err)
		} else {
			notifyCapabilityChange()
		}
	}()

	go func() {
		if err := InitializeEvdevManager(); err != nil {
			log.Debugf("Evdev manager unavailable: %v", err)
		} else {
			notifyCapabilityChange()
		}
	}()

	go func() {
		if err := InitializeClipboardManager(); err != nil {
			log.Warnf("Clipboard manager unavailable: %v", err)
		}
		if wlContext != nil {
			wlContext.Start()
			log.Info("Wayland event dispatcher started")
		}
	}()

	go func() {
		if err := InitializeDbusManager(); err != nil {
			log.Warnf("DBus manager unavailable: %v", err)
		} else {
			notifyCapabilityChange()
		}
	}()

	go func() {
		if err := InitializeNotifyActionsManager(); err != nil {
			log.Warnf("Notification action manager unavailable: %v", err)
		}
	}()

	if err := InitializeSysUpdateManager(); err != nil {
		log.Warnf("Sysupdate manager unavailable: %v", err)
	}

	log.Info("")
	log.Infof("Ready! Capabilities: %v", getCapabilities().Capabilities)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	serveErrChan := make(chan error, 1)
	go func() {
		serveErrChan <- s.ipc.Serve(ctx)
	}()

	select {
	case err := <-serveErrChan:
		return err
	case err := <-fatalErrChan:
		return err
	}
}
