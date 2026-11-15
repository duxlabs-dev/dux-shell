package wallpaper

import (
	"context"
	"encoding/json"
	"errors"
	"image"
	_ "image/gif"
	_ "image/jpeg"
	_ "image/png"
	"io"
	"math"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	_ "golang.org/x/image/bmp"
	_ "golang.org/x/image/webp"
)

const (
	maxSizeReads    = 4
	ffprobeTimeout  = 5 * time.Second
	ffprobeMaxBytes = 64 << 10
	sizeCacheMax    = 100_000
)

type sizeKey struct {
	path        string
	size, mtime int64
}

type pixelSize struct{ width, height int }

var (
	sizeReads = make(chan struct{}, maxSizeReads)
	sizeMu    sync.Mutex
	sizeCache = map[sizeKey]pixelSize{}
)

// readSizes fills in Width and Height of plain items, reading at most maxSizeReads files at once across all callers.
// Items not reached before ctx ends stay unknown.
func readSizes(ctx context.Context, items []Item) {
	var todo []int
	for i, item := range items {
		if item.Variants == nil && !strings.EqualFold(filepath.Ext(item.Path), ".svg") {
			todo = append(todo, i)
		}
	}
	if len(todo) == 0 {
		return
	}
	ffprobe, _ := exec.LookPath("ffprobe")
	var next atomic.Int64
	var wg sync.WaitGroup
	for range min(maxSizeReads, len(todo)) {
		wg.Go(func() {
			for {
				n := int(next.Add(1) - 1)
				if n >= len(todo) || ctx.Err() != nil {
					return
				}
				item := &items[todo[n]]
				s := readSize(ctx, item, ffprobe)
				item.Width, item.Height = s.width, s.height
			}
		})
	}
	wg.Wait()
}

func readSize(ctx context.Context, item *Item, ffprobe string) pixelSize {
	key := sizeKey{item.Path, item.Size, item.Mtime}
	sizeMu.Lock()
	s, ok := sizeCache[key]
	sizeMu.Unlock()
	if ok {
		return s
	}

	select {
	case sizeReads <- struct{}{}:
	case <-ctx.Done():
		return pixelSize{}
	}
	s, final := readFileSize(ctx, item.Path, ffprobe)
	<-sizeReads
	if !final {
		return s
	}

	sizeMu.Lock()
	// Cleared rather than evicted: a full 50,000-item list plus a cycling folder fits below the cap.
	if len(sizeCache) >= sizeCacheMax {
		clear(sizeCache)
	}
	sizeCache[key] = s
	sizeMu.Unlock()
	return s
}

// readFileSize returns the size (zero when unknown) and whether that answer holds until the file changes.
func readFileSize(ctx context.Context, path, ffprobe string) (pixelSize, bool) {
	f, err := os.Open(path)
	if err != nil {
		return pixelSize{}, false
	}
	cfg, _, err := image.DecodeConfig(f)
	f.Close()
	switch {
	case err == nil:
		return positive(cfg.Width, cfg.Height), true
	case !errors.Is(err, image.ErrFormat):
		return pixelSize{}, true
	case ffprobe == "":
		return pixelSize{}, false
	}
	return probeSize(ctx, ffprobe, path)
}

type probeVideo struct {
	Width    int `json:"width"`
	Height   int `json:"height"`
	SideData []struct {
		Rotation float64 `json:"rotation"`
	} `json:"side_data_list"`
}

func probeSize(ctx context.Context, ffprobe, path string) (pixelSize, bool) {
	ctx, cancel := context.WithTimeout(ctx, ffprobeTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, ffprobe, "-v", "error", "-select_streams", "v:0",
		"-show_entries", "stream=width,height:stream_side_data=rotation:stream_group_component=width,height:stream_group_side_data=rotation",
		"-of", "json", "-i", "file:"+path)
	cmd.WaitDelay = time.Second
	pipe, err := cmd.StdoutPipe()
	if err != nil {
		return pixelSize{}, false
	}
	if err := cmd.Start(); err != nil {
		return pixelSize{}, false
	}
	out, readErr := io.ReadAll(io.LimitReader(pipe, ffprobeMaxBytes+1))
	tooBig := len(out) > ffprobeMaxBytes
	if tooBig {
		cancel()
	}
	err = cmd.Wait()
	var exitErr *exec.ExitError
	switch {
	case tooBig:
		return pixelSize{}, true
	case ctx.Err() != nil, readErr != nil:
		return pixelSize{}, false
	case errors.As(err, &exitErr):
		return pixelSize{}, true
	case err != nil:
		return pixelSize{}, false
	}

	var probe struct {
		StreamGroups []struct {
			Components []probeVideo `json:"components"`
		} `json:"stream_groups"`
		Streams []probeVideo `json:"streams"`
	}
	if json.Unmarshal(out, &probe) != nil {
		return pixelSize{}, true
	}
	// A HEIF/AVIF tile grid lists its tiles as streams; the full canvas is the group component.
	for _, group := range probe.StreamGroups {
		for _, c := range group.Components {
			if c.Width > 0 && c.Height > 0 {
				return c.size(), true
			}
		}
	}
	if len(probe.Streams) == 0 {
		return pixelSize{}, true
	}
	return probe.Streams[0].size(), true
}

func (v probeVideo) size() pixelSize {
	for _, d := range v.SideData {
		if math.Mod(math.Abs(d.Rotation), 180) == 90 {
			return positive(v.Height, v.Width)
		}
	}
	return positive(v.Width, v.Height)
}

func positive(w, h int) pixelSize {
	if w <= 0 || h <= 0 {
		return pixelSize{}
	}
	return pixelSize{w, h}
}
