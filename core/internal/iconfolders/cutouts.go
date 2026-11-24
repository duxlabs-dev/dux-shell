package iconfolders

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"image"
	"image/png"
	"os"
	"path/filepath"
	"regexp"
	"sync"

	"github.com/duxlabs-dev/dux-go/atomicfile"
	"github.com/duxlabs-dev/dux-shell/core/internal/colorseed"
	"github.com/duxlabs-dev/dux-shell/core/internal/log"
)

const (
	// CutoutsDir holds each raster logo's cut-out under the state dir. They are color-independent,
	// so a theme change reuses them all.
	CutoutsDir = "icon-cutouts"
	// cutoutVersion changes whenever colorseed.Cutout would cut a logo differently; older files are pruned.
	cutoutVersion = 1
	// A logo with no mark to cut leaves this empty marker, so it is not tried again on every build.
	noCutoutExt = ".none"
)

// Only rasters: the pack draws an SVG's glyph from its own paths.
var cutoutFormats = []string{".png", ".jpg", ".jpeg"}

var cutoutFile = regexp.MustCompile(`^[0-9a-f]{64}(\.png|\.none)$`)

// cutouts returns each logo's cut-out PNG by source path, cutting only logos the cache does not hold
// as they are now, and drops the cut-outs no listed logo uses.
func (o *Options) cutouts(sources map[string]string) map[string]string {
	dir, err := filepath.Abs(filepath.Join(o.StateDir, CutoutsDir))
	if err != nil {
		return nil
	}
	type job struct{ src, out string }
	found := map[string]string{}
	keep := map[string]bool{}
	var jobs []job
	for _, path := range sources {
		info, err := os.Stat(path)
		if err != nil || !info.Mode().IsRegular() || info.Size() > tileMaxFileSize {
			continue
		}
		name := cutoutName(path, info)
		if keep[name+".png"] {
			continue
		}
		keep[name+".png"], keep[name+noCutoutExt] = true, true
		out := filepath.Join(dir, name+".png")
		if isFile(out) {
			found[path] = out
			continue
		}
		if !isFile(filepath.Join(dir, name+noCutoutExt)) {
			jobs = append(jobs, job{src: path, out: out})
		}
	}

	var mu sync.Mutex
	parallel(jobs, func(j job) {
		if cutLogo(j.src, j.out) {
			mu.Lock()
			found[j.src] = j.out
			mu.Unlock()
		}
	})
	pruneCutouts(dir, keep)
	return found
}

// cutoutName keys a cut-out to the logo file as it is and to the cutting algorithm.
func cutoutName(path string, info os.FileInfo) string {
	sum := sha256.Sum256(fmt.Appendf(nil, "%s\x00%d\x00%d\x00%d", path, info.Size(), info.ModTime().UnixNano(), cutoutVersion))
	return hex.EncodeToString(sum[:])
}

func isFile(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.Mode().IsRegular()
}

// cutLogo writes the logo's cut-out to out, or the no-cut-out marker beside it when the logo is no image or has no
// mark to cut. A read or write error leaves no marker, so the next build tries again.
func cutLogo(src, out string) bool {
	data, err := os.ReadFile(src)
	if err != nil {
		log.Warnf("Icon cut-outs: skipping %s: %v", src, err)
		return false
	}
	cut, ok := cutImage(src, data)
	if !ok {
		_ = atomicfile.WriteFileMkdir(out[:len(out)-len(".png")]+noCutoutExt, nil, 0o644, 0o755)
		return false
	}
	var buf bytes.Buffer
	if err := png.Encode(&buf, cut); err != nil {
		return false
	}
	if err := atomicfile.WriteFileMkdir(out, buf.Bytes(), 0o644, 0o755); err != nil {
		log.Warnf("Icon cut-outs: failed to write %s: %v", out, err)
		return false
	}
	return true
}

// cutImage decodes and cuts a logo; a broken file is logged, never fatal.
func cutImage(src string, data []byte) (cut *image.NRGBA, ok bool) {
	defer func() {
		if r := recover(); r != nil {
			log.Warnf("Icon cut-outs: skipping %s: %v", src, r)
			cut, ok = nil, false
		}
	}()
	img, _, err := image.Decode(bytes.NewReader(data))
	if err != nil {
		log.Warnf("Icon cut-outs: skipping %s: decode: %v", src, err)
		return nil, false
	}
	cut, _, ok = colorseed.Cutout(img)
	return cut, ok
}

// pruneCutouts removes the cut-outs and markers not in keep, and nothing it did not name.
func pruneCutouts(dir string, keep map[string]bool) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return
	}
	for _, entry := range entries {
		if name := entry.Name(); entry.Type().IsRegular() && cutoutFile.MatchString(name) && !keep[name] {
			os.Remove(filepath.Join(dir, name))
		}
	}
}
