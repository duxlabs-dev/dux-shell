package server

import (
	"net/http"
	_ "net/http/pprof"
	"os"
	"runtime"
	"runtime/debug"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
)

const (
	serverMaxProcs  = 4
	serverGCPercent = 50
)

func tuneRuntime() {
	if os.Getenv("GOMAXPROCS") == "" {
		runtime.GOMAXPROCS(min(runtime.NumCPU(), serverMaxProcs))
	}
	if os.Getenv("GOGC") == "" {
		debug.SetGCPercent(serverGCPercent)
	}
}

func startPprof() {
	addr := os.Getenv("DMS_PPROF")
	if addr == "" {
		return
	}
	go func() {
		log.Infof("pprof listening on http://%s/debug/pprof/", addr)
		if err := http.ListenAndServe(addr, nil); err != nil {
			log.Warnf("pprof server: %v", err)
		}
	}()
}
