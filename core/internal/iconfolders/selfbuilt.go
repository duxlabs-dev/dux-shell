package iconfolders

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"time"
)

const (
	// SelfBuilt is the pack whose own command builds the whole theme in the DMS colors.
	SelfBuilt = "dux-icons"

	selfBuiltLabel   = "Dux Icons"
	selfBuiltTimeout = 2 * time.Minute
	indexHeader      = "[Icon Theme]\n"
	// pathsFile is written by the pack: each Icon= value that is a file path, by the icon built from it.
	pathsFile = "icon-paths.json"
	bareDir   = "bare/apps"
)

var shapeName = regexp.MustCompile(`^[a-z0-9][a-z0-9-]{0,31}$`)

// generator returns the pack's build command, or "" when it is not installed.
func (o *Options) generator() string {
	if o.Generator != "" {
		return o.Generator
	}
	if path, err := exec.LookPath(SelfBuilt); err == nil {
		return path
	}
	// A session started by systemd often has no ~/.local/bin on PATH.
	home, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	path := filepath.Join(home, ".local", "bin", SelfBuilt)
	if info, err := os.Stat(path); err == nil && info.Mode().IsRegular() && info.Mode()&0o111 != 0 {
		return path
	}
	return ""
}

// applySelfBuilt names the theme after what was built: only the command knows its inputs.
func (o *Options) applySelfBuilt(prev State) (State, error) {
	generator := o.generator()
	if generator == "" {
		return State{}, forget(o.StateDir)
	}
	// Runs on every theme apply, so with nothing changed neither the source listing nor the build runs. Taken
	// before anything is read: a change that lands during the build only costs the next apply a rebuild.
	own := o.ownKey(generator)
	if o.unchangedSince(prev, own, generator) {
		return prev, nil
	}
	o.listedFingerprint = ""
	primary, onPrimary, err := loadPrimary(filepath.Join(o.StateDir, "dms-colors.json"), o.Mode)
	if err != nil {
		return o.surviving(prev), err
	}
	ramp, err := o.themeRamp(primary, onPrimary)
	if err != nil {
		return o.surviving(prev), err
	}
	if o.Shape != "" && !shapeName.MatchString(o.Shape) {
		return o.surviving(prev), fmt.Errorf("bad icon shape %q", o.Shape)
	}
	if err := os.MkdirAll(o.IconsDir, 0o755); err != nil {
		return o.surviving(prev), err
	}

	// Named like a crashed run's leftover, so prune removes it if this run dies.
	staging := filepath.Join(o.IconsDir, "."+SelfBuilt+"-dms-00000000.tmp-"+strconv.Itoa(os.Getpid()))
	defer os.RemoveAll(staging)
	if err := os.RemoveAll(staging); err != nil {
		return o.surviving(prev), err
	}
	tiled := supportsTiles(generator)
	tiles, cleanup := o.tiles(generator, primary, ramp, tiled)
	defer cleanup()
	output, err := o.runGenerator(generator, staging, ramp, tiled, tiles)
	if err != nil {
		return o.surviving(prev), err
	}
	// The source listing read the app icons first, so its fingerprint is the one the tiles were made from.
	fingerprint := o.listedFingerprint
	if fingerprint == "" {
		fingerprint = reportedFingerprint(output)
	}
	key := builtKey(own, fingerprint)
	// A pack that fingerprints lists --tiles, so here the probe failed, and the next apply must try again.
	if !tiled {
		key = ""
	}
	if err := markGenerated(staging); err != nil {
		return o.surviving(prev), err
	}
	inputs, err := treeHash(staging)
	if err != nil {
		return o.surviving(prev), err
	}

	name := appliedName(SelfBuilt, inputs)
	dir := filepath.Join(o.IconsDir, name)
	if !isGenerated(dir) {
		if _, err := os.Lstat(dir); err == nil {
			return o.surviving(prev), fmt.Errorf("%s: %w", dir, ErrOccupied)
		}
		if err := os.Rename(staging, dir); err != nil {
			return o.surviving(prev), err
		}
	}
	bare := hasBare(dir)
	if prev.Applied == name && prev.Dir == dir && prev.Bare == bare && prev.Key == key {
		return prev, nil
	}
	return o.commit(State{Base: SelfBuilt, Applied: name, Inputs: inputs, Dir: dir, Icons: pathIcons(dir), Bare: bare, Key: key}, prev)
}

// hasBare reports whether the pack wrote tile-free app icons, which older versions do not.
func hasBare(dir string) bool {
	info, err := os.Stat(filepath.Join(dir, bareDir))
	return err == nil && info.IsDir()
}

// pathIcons reads the icons that stand in for file paths, which no theme lookup would find.
func pathIcons(dir string) map[string]string {
	data, err := readPlain(filepath.Join(dir, pathsFile))
	if err != nil {
		return nil
	}
	var listed map[string]string
	if json.Unmarshal(data, &listed) != nil {
		return nil
	}
	icons := map[string]string{}
	for path, rel := range listed {
		if !filepath.IsLocal(rel) {
			continue
		}
		if info, err := os.Stat(filepath.Join(dir, rel)); err == nil && info.Mode().IsRegular() {
			icons[path] = rel
		}
	}
	return icons
}

func (o *Options) runGenerator(generator, out string, ramp Ramp, tiled bool, tiles string) ([]byte, error) {
	args, err := o.generatorArgs(out, ramp, flagsOf(generator, tiled), tiles)
	if err != nil {
		return nil, err
	}
	ctx, cancel := context.WithTimeout(context.Background(), selfBuiltTimeout)
	defer cancel()

	cmd := exec.CommandContext(ctx, generator, args...)
	// A child that keeps the pipe open must not hold the theme run lock.
	cmd.WaitDelay = time.Second
	output, err := cmd.CombinedOutput()
	if err != nil {
		lines := strings.Split(strings.TrimSpace(string(output)), "\n")
		return nil, fmt.Errorf("%s failed: %w: %s", generator, err, lines[len(lines)-1])
	}
	return output, nil
}

// generatorArgs builds the pack's command line; the defaults leave out every flag a newer pack adds.
// flags is what the pack lists, as probeGenerator probes it.
func (o *Options) generatorArgs(out string, ramp Ramp, flags generatorFlags, tiles string) ([]string, error) {
	if o.Shape != "" && !shapeName.MatchString(o.Shape) {
		return nil, fmt.Errorf("bad icon shape %q", o.Shape)
	}
	args := append([]string{"--out", out, "--name", selfBuiltLabel}, o.styleArgs(ramp, flags)...)
	if flags.tiles && tiles != "" {
		args = append(args, "--tiles", tiles)
	}
	return args, nil
}

// styleArgs are the colors and look every run of the pack shares. A pack that lists --tiles takes the
// tile color as --tile; an older one only knows it as --badge. A pack without --app-style only knows the tinted style, as --mono. A pack without
// --own-tone or --files-style builds with its own defaults for them.
func (o *Options) styleArgs(ramp Ramp, flags generatorFlags) []string {
	tile := "--badge"
	if flags.tiles {
		tile = "--tile"
	}
	args := []string{tile, ramp.Front, "--glyph", ramp.Glyph, "--back", ramp.Back}
	style := o.appStyle()
	if flags.appStyle {
		args = append(args, "--app-style", style)
	} else {
		args = append(args, onOff("mono", style != AppColor))
	}
	args = append(args, onOff("gradient", o.Gradient))
	if o.Shape != "" {
		args = append(args, "--shape", o.Shape)
	}
	// Only the color style keeps the pack's own apps' tones; the others repaint them, so a tone would only rename the build.
	if tone := clampTone(o.OwnTone); flags.ownTone && tone != ToneAuto && style == AppColor {
		args = append(args, "--own-tone", strconv.Itoa(tone))
	}
	// Standard is the pack's default, so it is never passed and a build without the flag stays the same theme.
	if flags.filesStyle && o.fileStyle() == FilesColor {
		args = append(args, "--files-style", FilesColor)
	}
	return args
}

func onOff(flag string, on bool) string {
	if on {
		return "--" + flag
	}
	return "--no-" + flag
}

// markGenerated adds the key that lets prune delete the directory and nothing it did not write.
func markGenerated(dir string) error {
	path := filepath.Join(dir, "index.theme")
	data, err := readPlain(path)
	if err != nil || !bytes.HasPrefix(data, []byte(indexHeader)) {
		return fmt.Errorf("%s is not an icon theme index", path)
	}
	marked := slices.Concat([]byte(indexHeader+"Hidden=true\n"+generatedKey+"\n"), data[len(indexHeader):])
	return os.WriteFile(path, marked, 0o644)
}

// treeHash covers every path, link target and file content, so equal names mean equal themes.
func treeHash(root string) (string, error) {
	sum := sha256.New()
	err := filepath.WalkDir(root, func(path string, entry fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		rel, err := filepath.Rel(root, path)
		if err != nil {
			return err
		}
		switch {
		case entry.IsDir():
			fmt.Fprintf(sum, "d\x00%s\x00", rel)
		case entry.Type()&fs.ModeSymlink != 0:
			target, err := os.Readlink(path)
			if err != nil {
				return err
			}
			fmt.Fprintf(sum, "l\x00%s\x00%s\x00", rel, target)
		case entry.Type().IsRegular():
			data, err := os.ReadFile(path)
			if err != nil {
				return err
			}
			fmt.Fprintf(sum, "f\x00%s\x00%d\x00", rel, len(data))
			sum.Write(data)
		default:
			return errors.New(rel + " is not a file, link or directory")
		}
		return nil
	})
	if err != nil {
		return "", err
	}
	return hex.EncodeToString(sum.Sum(nil)[:16]), nil
}
