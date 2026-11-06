package distros

import (
	"github.com/duxlabs-dev/dux-shell/core/internal/deps"
	"github.com/duxlabs-dev/dux-shell/core/internal/qtbaseembed"
)

func (b *BaseDistribution) detectDuxQtBase() deps.Dependency {
	dep := deps.Dependency{
		Name:        "dux-qt-base",
		Description: "Quickshell runtime library embedded in dms",
		Required:    true,
		Variant:     deps.VariantStable,
		Status:      deps.StatusMissing,
	}
	if _, err := qtbaseembed.Resolve(); err == nil {
		dep.Status = deps.StatusInstalled
	}
	return dep
}
