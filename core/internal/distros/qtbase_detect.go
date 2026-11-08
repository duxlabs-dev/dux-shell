package distros

import (
	"context"
	"time"

	"github.com/duxlabs-dev/dux-go/qtbase"
	"github.com/duxlabs-dev/dux-shell/core/internal/deps"
)

var probeDuxQtBase = func(ctx context.Context) error {
	return qtbase.Command(ctx, "--version").Run()
}

func (b *BaseDistribution) detectDuxQtBase() deps.Dependency {
	dep := deps.Dependency{
		Name:        "dux-qt-base",
		Description: "Quickshell runtime: dux-qt-base embedded in dms or installed as a package",
		Required:    true,
		Variant:     deps.VariantStable,
		Status:      deps.StatusMissing,
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := probeDuxQtBase(ctx); err == nil {
		dep.Status = deps.StatusInstalled
	}
	return dep
}
