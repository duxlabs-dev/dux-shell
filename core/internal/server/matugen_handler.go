package server

import (
	"context"
	"time"

	"github.com/duxlabs-dev/dux-go/ipc"
	"github.com/duxlabs-dev/dux-shell/core/internal/matugen"
)

type MatugenQueueResult struct {
	Success bool   `json:"success"`
	Message string `json:"message,omitempty"`
}

// matugenQueueOptions reads a queue request; a key the client leaves out keeps the default.
func matugenQueueOptions(req ipc.Request) matugen.Options {
	return matugen.Options{
		StateDir:            req.GetOr("stateDir", ""),
		ShellDir:            req.GetOr("shellDir", ""),
		ConfigDir:           req.GetOr("configDir", ""),
		Kind:                req.GetOr("kind", ""),
		Value:               req.GetOr("value", ""),
		Mode:                matugen.ColorMode(req.GetOr("mode", "")),
		IconTheme:           req.GetOr("iconTheme", ""),
		MatugenType:         req.GetOr("matugenType", ""),
		RunUserTemplates:    req.GetOr("runUserTemplates", true),
		StockColors:         req.GetOr("stockColors", ""),
		SyncModeWithPortal:  req.GetOr("syncModeWithPortal", false),
		TerminalsAlwaysDark: req.GetOr("terminalsAlwaysDark", false),
		TerminalOpacity:     int(req.GetOr("terminalOpacity", 0.0)),
		TerminalPalette:     req.GetOr("terminalPalette", ""),
		SkipTemplates:       req.GetOr("skipTemplates", ""),
		IconFolders:         req.GetOr("iconFolders", false),
		IconAppStyle:        req.GetOr("iconAppStyle", ""),
		IconShape:           req.GetOr("iconShape", ""),
		IconGradient:        req.GetOr("iconGradient", false),
		IconTileColor:       req.GetOr("iconTileColor", ""),
		IconColorSource:     req.GetOr("iconColorSource", ""),
		IconTileStyle:       req.GetOr("iconTileStyle", ""),
		IconTileTone:        int(req.GetOr("iconTileTone", -1.0)),
		IconOwnTone:         int(req.GetOr("iconOwnTone", -1.0)),
		IconFileStyle:       req.GetOr("iconFileStyle", ""),
		Contrast:            req.GetOr("contrast", 0.0),
		SourceMode:          req.GetOr("sourceMode", ""),
		SeedColor:           req.GetOr("seedColor", ""),
		Spec:                req.GetOr("spec", ""),
	}
}

func handleMatugenQueue(conn *ipc.ConnWriter, req ipc.Request) {
	opts := matugenQueueOptions(req)
	wait := req.GetOr("wait", true)

	queue := matugen.GetQueue()
	resultCh := queue.Submit(opts)

	if !wait {
		conn.Respond(req.ID, MatugenQueueResult{
			Success: true,
			Message: "queued",
		})
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	select {
	case result := <-resultCh:
		if result.Error != nil {
			if result.Error == context.Canceled {
				conn.Respond(req.ID, MatugenQueueResult{
					Success: false,
					Message: "cancelled",
				})
				return
			}
			conn.RespondError(req.ID, result.Error.Error())
			return
		}
		conn.Respond(req.ID, MatugenQueueResult{
			Success: true,
			Message: "completed",
		})
	case <-ctx.Done():
		conn.RespondError(req.ID, "timeout waiting for theme generation")
	}
}

func handleMatugenStatus(conn *ipc.ConnWriter, req ipc.Request) {
	queue := matugen.GetQueue()
	conn.Respond(req.ID, map[string]bool{
		"running":        queue.IsRunning(),
		"pending":        queue.HasPending(),
		"smartSupported": matugen.SupportsSmart(),
	})
}
