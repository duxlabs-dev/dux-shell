package configfrag

import (
	"path/filepath"
	"strings"

	"github.com/duxlabs-dev/dux-shell/core/internal/utils"
)

type IncludeScan struct {
	Count       int
	DMSPosition int
	DMSSeen     bool
}

func NewScan() IncludeScan {
	return IncludeScan{DMSPosition: -1}
}

type Walker struct {
	isDMSFragment func(string) bool
	scan          IncludeScan
}

func NewWalker(isDMSFragment func(string) bool) *Walker {
	return &Walker{isDMSFragment: isDMSFragment, scan: NewScan()}
}

func (w *Walker) Scan() IncludeScan {
	return w.scan
}

func (w *Walker) Included() bool {
	return w.scan.DMSSeen
}

func (w *Walker) RecordMatch(matched bool) bool {
	w.scan.Count++
	if !matched {
		return false
	}
	w.scan.DMSSeen = true
	w.scan.DMSPosition = w.scan.Count
	return true
}

func (w *Walker) Record(sourcePath string) bool {
	return w.RecordMatch(w.isDMSFragment != nil && w.isDMSFragment(sourcePath))
}

func (w *Walker) Include(baseDir, sourcePath string, visit func(absPath string) error) bool {
	resolved, err := Resolve(baseDir, sourcePath)
	if err != nil {
		return w.Record(sourcePath)
	}

	matched := w.Record(resolved)
	if visit == nil {
		return matched
	}
	_ = visit(resolved)
	return matched
}

func (w *Walker) IncludeAssignment(baseDir, line string, visit func(absPath string) error) bool {
	parts := strings.SplitN(line, "=", 2)
	if len(parts) < 2 {
		return false
	}
	return w.Include(baseDir, strings.TrimSpace(parts[1]), visit)
}

func Resolve(baseDir, sourcePath string) (string, error) {
	expanded, err := utils.ExpandPath(sourcePath)
	if err != nil {
		return "", err
	}
	if filepath.IsAbs(expanded) {
		return expanded, nil
	}
	return filepath.Join(baseDir, expanded), nil
}
