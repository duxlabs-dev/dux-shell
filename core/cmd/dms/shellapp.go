package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/duxlabs-dev/dux-go/shellapp"
	"github.com/duxlabs-dev/dux-shell/core/internal/clipolicy"
	"github.com/duxlabs-dev/dux-shell/core/internal/gpu"
	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/duxlabs-dev/dux-shell/core/internal/qtbaseembed"
	"github.com/duxlabs-dev/dux-shell/core/internal/server"
	"github.com/duxlabs-dev/dux-shell/core/internal/shellembed"
	"github.com/duxlabs-dev/dux-shell/core/internal/utils"
	"github.com/spf13/afero"
)

var shellApp = shellapp.New(shellapp.Config{
	ID:                     "dms",
	LegacyIDs:              []string{"danklinux"},
	EnvPrefix:              "DMS",
	QSAppID:                "dev.duxlabs.shell",
	Version:                Version,
	Embedded:               embeddedShell{},
	QtBase:                 qtbaseembed.Extract,
	Boot:                   bootBackend,
	PreLaunch:              preLaunch,
	ExtraEnv:               dmsExtraEnv,
	OnUIExit:               logStartupFailure,
	SessionRestartExitCode: dmsSessionRestartExitCode,
	TryManagedRestart:      trySystemdRestart,
})

type embeddedShell struct{}

func (embeddedShell) Available() bool { return shellembed.Available() }

func (embeddedShell) Extract(baseDir string) (string, error) { return shellembed.Extract(baseDir) }

func (embeddedShell) Prune(baseDir, keep string) { shellembed.Prune(baseDir, keep) }

type dmsBackend struct {
	srv    *server.Server
	done   chan error
	cancel context.CancelFunc
}

func (b *dmsBackend) SocketPath() string { return b.srv.SocketPath() }

func (b *dmsBackend) Close() {
	b.cancel()
	b.srv.Close()
}

func (b *dmsBackend) Done() <-chan error { return b.done }

func bootBackend(ctx context.Context) (shellapp.Backend, error) {
	server.CLIVersion = Version

	srv := server.New()
	if err := srv.Listen(); err != nil {
		return nil, err
	}

	ctx, cancel := context.WithCancel(ctx)
	backend := &dmsBackend{srv: srv, done: make(chan error, 1), cancel: cancel}
	go srv.WaitReady(ctx)
	go func() {
		defer cancel()
		defer func() {
			if r := recover(); r != nil {
				backend.done <- fmt.Errorf("server panic: %v", r)
			}
		}()
		backend.done <- srv.Serve(false)
	}()

	return backend, nil
}

func preLaunch() {
	go printASCII()
	ensureFontCache()
}

func shellSettings() []byte {
	configDir, err := os.UserConfigDir()
	if err != nil {
		return nil
	}
	data, err := os.ReadFile(filepath.Join(configDir, "dms", "settings.json"))
	if err != nil {
		return nil
	}
	return data
}

// The elapsed-timer driver keeps the scrolling wallpaper spring in step above 60 Hz,
// but it makes every other animation jump after a dropped frame (#3837).
func wantsSimpleAnimationDriver(settings []byte) bool {
	var parsed struct {
		WallpaperFillMode string `json:"wallpaperFillMode"`
	}
	if json.Unmarshal(settings, &parsed) != nil {
		return false
	}
	return parsed.WallpaperFillMode == "Scrolling"
}

// shell.qml turns these on with pragmas, which only the runtime's environment can override.
func runtimeSwitchEnv(settings []byte) []string {
	parsed := struct {
		QmlCacheEnabled      bool `json:"qmlCacheEnabled"`
		RenderControlEnabled bool `json:"renderControlEnabled"`
	}{QmlCacheEnabled: true, RenderControlEnabled: true}
	_ = json.Unmarshal(settings, &parsed)

	var env []string
	if !parsed.QmlCacheEnabled {
		env = append(env, "QS_DISABLE_DISK_CACHE=1")
	}
	if !parsed.RenderControlEnabled {
		env = append(env, "QS_DISABLE_RENDER_CONTROL=1")
	}
	return env
}

// Qt < 6.10 reserves a JS stack slot per object of the shell's whole type tree while
// creating it, which overflows the 4 MiB default and breaks early handlers (#4175).
const qmlJSStackSize = 16 << 20

func dmsExtraEnv(string) []string {
	var env []string
	if selfPath, err := os.Executable(); err == nil {
		env = append(env, "DMS_EXECUTABLE="+selfPath)
	}
	settings := shellSettings()
	if os.Getenv("QSG_USE_SIMPLE_ANIMATION_DRIVER") == "" && wantsSimpleAnimationDriver(settings) {
		env = append(env, "QSG_USE_SIMPLE_ANIMATION_DRIVER=1")
	}
	env = append(env, runtimeSwitchEnv(settings)...)
	if _, set := os.LookupEnv("MALLOC_CONF"); !set {
		env = append(env, "MALLOC_CONF=thp:never,narenas:4,dirty_decay_ms:3000")
	}
	if os.Getenv("QV4_JS_MAX_STACK_SIZE") == "" {
		env = append(env, "QV4_JS_MAX_STACK_SIZE="+strconv.Itoa(qmlJSStackSize))
	}
	env = append(env, gpu.ShellEnv()...)
	policyEnv, err := clipolicy.ShellEnv(afero.NewOsFs())
	if err != nil {
		log.Errorf("CLI policy unreadable, enforcing every shell switch and ignoring its lock settings: %v", err)
	}
	env = append(env, policyEnv...)
	// systemd user services miss the login shell PATH, so tools in ~/.local/bin
	// (herdr, pip/cargo installs) would be invisible to the shell and its children.
	for _, entry := range utils.EnvWithUserBinPath(nil) {
		if strings.HasPrefix(entry, "PATH=") {
			env = append(env, entry)
		}
	}
	return env
}
