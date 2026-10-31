// Package configprofile exports config profiles to shareable .tar.gz archives and imports them back.
package configprofile

import (
	"archive/tar"
	"bytes"
	"cmp"
	"compress/gzip"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"maps"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/internal/utils"
)

const (
	profileFile   = "profile.json"
	wallpaperPart = "wallpapers/"
)

// Archive limits, enforced on the bytes actually read.
var (
	maxEntries            = 64
	maxProfileBytes int64 = 8 << 20
	maxFileBytes    int64 = 128 << 20
	maxTotalBytes   int64 = 512 << 20
)

type fileKey struct {
	Section string
	Key     string
	Map     bool
}

var fileKeys = []fileKey{
	{Section: "settings", Key: "lockScreenWallpaperPath"},
	{Section: "session", Key: "wallpaperPath"},
	{Section: "session", Key: "wallpaperPathLight"},
	{Section: "session", Key: "wallpaperPathDark"},
	{Section: "session", Key: "monitorWallpapers", Map: true},
	{Section: "session", Key: "monitorWallpapersLight", Map: true},
	{Section: "session", Key: "monitorWallpapersDark", Map: true},
}

// shellRule marks values the shell interpolates into sh -c scripts or compositor config. An empty deny requires a number.
type shellRule struct {
	path []string
	deny string
}

const shellQuoted = "\"$`\\"

var shellRules = []shellRule{
	{[]string{"session", "wallpaperCyclingFolderPath"}, shellQuoted},
	{[]string{"session", "monitorCyclingSettings", "*", "folderPath"}, shellQuoted},
	{[]string{"settings", "customThemeFile"}, shellQuoted},
	{[]string{"settings", "cursorSettings", "theme"}, shellQuoted},
	{[]string{"settings", "cursorSettings", "size"}, ""},
	// Icon themes also land in single-quoted sed and gsettings arguments.
	{[]string{"settings", "iconThemeDark"}, shellQuoted + "'/"},
	{[]string{"settings", "iconThemeLight"}, shellQuoted + "'/"},
}

var unbundledPaths = [][]string{
	{"session", "wallpaperCyclingFolderPath"},
	{"session", "monitorCyclingSettings", "*", "folderPath"},
	{"settings", "customThemeFile"},
}

func init() {
	for _, fk := range fileKeys {
		path := []string{fk.Section, fk.Key}
		if fk.Map {
			path = append(path, "*")
		}
		shellRules = append(shellRules, shellRule{path, shellQuoted})
	}
}

// builtinWidgets are the widget types the shell ships; instances of any other type are plugin widgets.
var builtinWidgets = []string{"desktopClock", "systemMonitor", "lockDate", "lockAuth", "lockNotifications", "lockStatus", "lockPower", "greeterSession"}

var widgetInstanceKeys = []string{"desktopWidgetInstances", "lockScreenWidgetInstances"}

var (
	idRe            = regexp.MustCompile(`^[\w-]+$`)
	wallpaperNameRe = regexp.MustCompile(`^[\w][\w.-]*$`)
	unsafeCharRe    = regexp.MustCompile(`[^\w.-]`)
	hashPrefixRe    = regexp.MustCompile(`^[0-9a-f]{12}-`)
	stagingRe       = regexp.MustCompile(`^\.import-\d+$`)
	imageExts       = []string{".jpg", ".jpeg", ".png", ".bmp", ".gif", ".webp", ".jxl", ".avif", ".heif", ".exr", ".svg"}
	videoExts       = []string{".mp4", ".webm", ".mkv", ".mov"}
)

type Summary struct {
	ID   string
	Name string
}

func Dir() string {
	return filepath.Join(utils.XDGConfigHome(), "dms", "profiles")
}

func WallpaperDir() string {
	return filepath.Join(utils.XDGDataHome(), "dms", "wallpapers")
}

// List returns the profiles in dir ordered like the shell: by created, then id.
func List(dir string) ([]Summary, error) {
	entries, err := os.ReadDir(dir)
	if errors.Is(err, os.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("failed to read profiles: %w", err)
	}
	type item struct {
		Summary
		created float64
	}
	var items []item
	for _, e := range entries {
		if !e.IsDir() || !idRe.MatchString(e.Name()) {
			continue
		}
		b, err := os.ReadFile(filepath.Join(dir, e.Name(), profileFile))
		if err != nil {
			continue
		}
		var p struct {
			Name    string  `json:"name"`
			Created float64 `json:"created"`
		}
		if json.Unmarshal(b, &p) != nil {
			continue
		}
		items = append(items, item{Summary{e.Name(), p.Name}, p.Created})
	}
	slices.SortStableFunc(items, func(a, b item) int {
		return cmp.Or(cmp.Compare(a.created, b.created), strings.Compare(a.ID, b.ID))
	})
	out := make([]Summary, len(items))
	for i, it := range items {
		out[i] = it.Summary
	}
	return out, nil
}

// Export returns the paths it couldn't bundle as warnings; they stay unchanged in the profile.
func Export(dir, id, out string) (warnings []string, err error) {
	if !idRe.MatchString(id) {
		return nil, fmt.Errorf("invalid profile id %q", id)
	}
	profDir := filepath.Join(dir, id)
	raw, err := os.ReadFile(filepath.Join(profDir, profileFile))
	if err != nil {
		return nil, fmt.Errorf("failed to read profile: %w", err)
	}
	profile, err := parseProfile(raw)
	if err != nil {
		return nil, err
	}
	for _, path := range unbundledPaths {
		walkPath(profile, path, nil, func(_ string, v any) {
			if s, _ := v.(string); s != "" {
				warnings = append(warnings, fmt.Sprintf("%s not bundled: only wallpapers are bundled", s))
			}
		})
	}

	preview := ""
	budget := maxTotalBytes - maxProfileBytes
	if thumb, _ := profile["thumbnail"].(string); isPreviewName(thumb) {
		if info, err := os.Stat(filepath.Join(profDir, thumb)); err == nil && info.Mode().IsRegular() {
			preview = thumb
			budget -= info.Size()
		}
	}

	bundled := map[string]string{}
	err = rewriteFileKeys(profile, func(_, value string) (string, error) {
		file := strings.TrimPrefix(value, "file://")
		name, size, reason := bundleName(file)
		if _, dup := bundled[name]; reason == "" && !dup {
			switch {
			case len(bundled)+2 > maxEntries:
				reason = "too many files"
			case size > budget:
				reason = "archive size limit reached"
			}
			if reason == "" {
				budget -= size
			}
		}
		if reason != "" {
			warnings = append(warnings, fmt.Sprintf("%s not bundled: %s", value, reason))
			return value, nil
		}
		bundled[name] = file
		return name, nil
	})
	if err == nil {
		err = checkShellSafe(profile)
	}
	if err != nil {
		return nil, err
	}
	if _, ok := profile["thumbnail"]; ok || preview != "" {
		profile["thumbnail"] = preview
	}

	data, err := encodeProfile(profile)
	if err != nil {
		return nil, err
	}
	if int64(len(data)) > maxProfileBytes {
		return nil, errors.New("profile is too large to export")
	}

	tmp, err := os.CreateTemp(filepath.Dir(out), ".dms-profile-*")
	if err != nil {
		return nil, fmt.Errorf("failed to create archive: %w", err)
	}
	defer func() {
		if err != nil {
			tmp.Close()
			os.Remove(tmp.Name())
		}
	}()

	gz := gzip.NewWriter(tmp)
	tw := tar.NewWriter(gz)
	if err = addBytes(tw, profileFile, data); err != nil {
		return nil, fmt.Errorf("failed to write archive: %w", err)
	}
	if preview != "" {
		if err = addFile(tw, preview, filepath.Join(profDir, preview)); err != nil {
			return nil, fmt.Errorf("failed to add preview: %w", err)
		}
	}
	for _, name := range slices.Sorted(maps.Keys(bundled)) {
		if err = addFile(tw, name, bundled[name]); err != nil {
			return nil, fmt.Errorf("failed to add %s: %w", bundled[name], err)
		}
	}
	if err = errors.Join(tw.Close(), gz.Close(), tmp.Chmod(0o644), tmp.Close()); err != nil {
		return nil, fmt.Errorf("failed to write archive: %w", err)
	}
	if err = os.Rename(tmp.Name(), out); err != nil {
		return nil, fmt.Errorf("failed to write archive: %w", err)
	}
	return warnings, nil
}

func bundleName(value string) (name string, size int64, reason string) {
	if !filepath.IsAbs(value) {
		return "", 0, "not an absolute path"
	}
	info, err := os.Stat(value)
	switch {
	case err != nil:
		return "", 0, "file not found"
	case !info.Mode().IsRegular():
		return "", 0, "not a regular file"
	case !hasExt(value, imageExts) && !hasExt(value, videoExts):
		return "", 0, "not an image or video"
	case info.Size() > maxFileBytes:
		return "", 0, "file too large"
	}
	sum, err := hashFile(value)
	if err != nil {
		return "", 0, "file not readable"
	}
	base := unsafeCharRe.ReplaceAllString(filepath.Base(value), "_")
	if limit := 255 - 13; len(base) > limit {
		ext := filepath.Ext(base)
		base = base[:limit-len(ext)] + ext
	}
	return wallpaperPart + sum[:12] + "-" + base, info.Size(), ""
}

func Import(dir, wallpaperDir, archive string) (id string, err error) {
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", fmt.Errorf("failed to create profiles folder: %w", err)
	}
	removeStaleStaging(dir)
	staging, err := os.MkdirTemp(dir, ".import-")
	if err != nil {
		return "", fmt.Errorf("failed to create staging folder: %w", err)
	}
	defer func() {
		if err != nil {
			os.RemoveAll(staging)
		}
	}()

	root, err := os.OpenRoot(staging)
	if err != nil {
		return "", fmt.Errorf("failed to open staging folder: %w", err)
	}
	defer root.Close()

	contents, err := unpack(archive, root)
	if err != nil {
		return "", fmt.Errorf("invalid profile archive: %w", err)
	}
	profile, err := parseProfile(contents.profile)
	if err == nil {
		err = checkShellSafe(profile)
	}
	if err != nil {
		return "", fmt.Errorf("invalid profile archive: %w", err)
	}

	used := map[string]string{}
	err = rewriteFileKeys(profile, func(key, value string) (string, error) {
		if !strings.HasPrefix(value, wallpaperPart) {
			return value, nil
		}
		if _, ok := contents.wallpapers[value]; !ok {
			return "", fmt.Errorf("invalid profile archive: %s points to %q, which the archive doesn't contain", key, value)
		}
		used[value] = contents.wallpapers[value]
		return filepath.Join(wallpaperDir, contents.wallpapers[value]), nil
	})
	if err != nil {
		return "", err
	}

	stripPlugins(profile)
	blankKey(profile["settings"], "trashCustomCommand")

	thumb, _ := profile["thumbnail"].(string)
	if _, ok := contents.previews[thumb]; !ok {
		thumb = ""
	}
	profile["thumbnail"] = thumb
	for name := range contents.previews {
		if name != thumb {
			_ = root.Remove(name)
		}
	}
	profile["created"] = time.Now().UnixMilli()

	data, err := encodeProfile(profile)
	if err != nil {
		return "", err
	}
	if err := root.WriteFile(profileFile, data, 0o644); err != nil {
		return "", fmt.Errorf("failed to write profile: %w", err)
	}

	id, err = newID()
	if err != nil {
		return "", err
	}
	if err := installWallpapers(root, wallpaperDir, used); err != nil {
		return "", err
	}
	if err := os.Rename(staging, filepath.Join(dir, id)); err != nil {
		return "", fmt.Errorf("failed to add profile: %w", err)
	}
	return id, nil
}

// removeStaleStaging deletes leftovers of killed imports.
func removeStaleStaging(dir string) {
	entries, _ := os.ReadDir(dir)
	for _, e := range entries {
		if !e.IsDir() || !stagingRe.MatchString(e.Name()) {
			continue
		}
		if info, err := e.Info(); err == nil && time.Since(info.ModTime()) > 10*time.Minute {
			os.RemoveAll(filepath.Join(dir, e.Name()))
		}
	}
}

// Plugin settings can hold commands and script paths, and applying them can enable plugins.
func stripPlugins(p map[string]any) {
	delete(p, "pluginSettings")
	if settings, ok := p["settings"].(map[string]any); ok {
		delete(settings, "builtInPluginSettings")
		for _, key := range widgetInstanceKeys {
			if list, ok := settings[key].([]any); ok {
				settings[key] = slices.DeleteFunc(slices.Clone(list), func(w any) bool {
					inst, _ := w.(map[string]any)
					t, _ := inst["widgetType"].(string)
					return !slices.Contains(builtinWidgets, t)
				})
			}
		}
	}
	if groups, ok := p["groups"].([]any); ok {
		p["groups"] = slices.DeleteFunc(slices.Clone(groups), func(g any) bool { return g == "plugins" })
	}
}

// The dock's trash command runs through sh -c.
func blankKey(v any, key string) {
	switch v := v.(type) {
	case map[string]any:
		for k, mv := range v {
			if s, ok := mv.(string); ok && k == key && s != "" {
				v[k] = ""
			}
			blankKey(mv, key)
		}
	case []any:
		for _, e := range v {
			blankKey(e, key)
		}
	}
}

type archiveContents struct {
	profile    []byte
	wallpapers map[string]string
	previews   map[string]bool
}

func unpack(archive string, root *os.Root) (*archiveContents, error) {
	f, err := os.Open(archive)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	gz, err := gzip.NewReader(f)
	if err != nil {
		return nil, fmt.Errorf("not a gzip file: %w", err)
	}
	defer gz.Close()

	c := &archiveContents{wallpapers: map[string]string{}, previews: map[string]bool{}}
	seen := map[string]bool{}
	budget := maxTotalBytes
	tr := tar.NewReader(gz)
	for count := 0; ; count++ {
		h, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, fmt.Errorf("not a tar archive: %w", err)
		}
		if count >= maxEntries {
			return nil, fmt.Errorf("more than %d entries", maxEntries)
		}
		if h.Name == "wallpapers/" || h.Name == "wallpapers" {
			if h.Typeflag != tar.TypeDir {
				return nil, fmt.Errorf("unexpected entry %q", h.Name)
			}
			continue
		}
		if h.Typeflag != tar.TypeReg {
			return nil, fmt.Errorf("entry %q is not a regular file", h.Name)
		}
		if seen[h.Name] {
			return nil, fmt.Errorf("duplicate entry %q", h.Name)
		}
		seen[h.Name] = true

		limit := min(maxFileBytes, budget)
		switch {
		case h.Name == profileFile:
			b, err := readLimited(tr, min(maxProfileBytes, budget))
			if err != nil {
				return nil, fmt.Errorf("%s: %w", h.Name, err)
			}
			c.profile = b
			budget -= int64(len(b))
		case isPreviewName(h.Name):
			n, _, err := writeLimited(root, h.Name, tr, limit)
			if err != nil {
				return nil, fmt.Errorf("%s: %w", h.Name, err)
			}
			c.previews[h.Name] = true
			budget -= n
		case isWallpaperName(h.Name):
			if len(c.wallpapers) == 0 {
				if err := root.Mkdir("wallpapers", 0o755); err != nil {
					return nil, err
				}
			}
			n, sum, err := writeLimited(root, h.Name, tr, limit)
			if err != nil {
				return nil, fmt.Errorf("%s: %w", h.Name, err)
			}
			base := hashPrefixRe.ReplaceAllString(strings.TrimPrefix(h.Name, wallpaperPart), "")
			c.wallpapers[h.Name] = sum[:12] + "-" + base
			budget -= n
		default:
			return nil, fmt.Errorf("unexpected entry %q", h.Name)
		}
	}
	if c.profile == nil {
		return nil, errors.New("profile.json missing")
	}
	return c, nil
}

func readLimited(r io.Reader, limit int64) ([]byte, error) {
	b, err := io.ReadAll(io.LimitReader(r, limit+1))
	if err != nil {
		return nil, err
	}
	if int64(len(b)) > limit {
		return nil, errors.New("too large")
	}
	return b, nil
}

func writeLimited(root *os.Root, name string, r io.Reader, limit int64) (int64, string, error) {
	f, err := root.OpenFile(name, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o644)
	if err != nil {
		return 0, "", err
	}
	defer f.Close()
	h := sha256.New()
	n, err := io.Copy(io.MultiWriter(f, h), io.LimitReader(r, limit+1))
	if err != nil {
		return n, "", err
	}
	if n > limit {
		return n, "", errors.New("too large")
	}
	return n, hex.EncodeToString(h.Sum(nil)), nil
}

// Names carry the content hash, so an existing file is the same wallpaper.
func installWallpapers(root *os.Root, wallpaperDir string, wallpapers map[string]string) error {
	if len(wallpapers) > 0 {
		if err := os.MkdirAll(wallpaperDir, 0o755); err != nil {
			return fmt.Errorf("failed to create wallpaper folder: %w", err)
		}
	}
	for src, name := range wallpapers {
		dst := filepath.Join(wallpaperDir, name)
		if _, err := os.Lstat(dst); err == nil {
			continue
		}
		if err := copyInto(root, src, dst); err != nil {
			return fmt.Errorf("failed to install wallpaper %s: %w", name, err)
		}
	}
	return root.RemoveAll("wallpapers")
}

// copyInto copies via a temp file and rename, so the folder never holds a partial wallpaper.
func copyInto(root *os.Root, src, dst string) error {
	in, err := root.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	tmp, err := os.CreateTemp(filepath.Dir(dst), ".import-*")
	if err != nil {
		return err
	}
	_, err = io.Copy(tmp, in)
	if err = errors.Join(err, tmp.Chmod(0o644), tmp.Close()); err == nil {
		err = os.Rename(tmp.Name(), dst)
	}
	if err != nil {
		os.Remove(tmp.Name())
	}
	return err
}

func parseProfile(data []byte) (map[string]any, error) {
	dec := json.NewDecoder(bytes.NewReader(data))
	dec.UseNumber()
	var v any
	if err := dec.Decode(&v); err != nil {
		return nil, fmt.Errorf("profile.json is not valid JSON: %w", err)
	}
	p, ok := v.(map[string]any)
	if !ok {
		return nil, errors.New("profile.json is not an object")
	}
	if raw, ok := p["version"]; ok {
		n, isNum := raw.(json.Number)
		f, err := n.Float64()
		if !isNum || err != nil || f > 1 {
			return nil, fmt.Errorf("unsupported profile version %v", raw)
		}
	}
	if name, _ := p["name"].(string); strings.TrimSpace(name) == "" {
		return nil, errors.New("profile has no name")
	}
	if _, ok := p["groups"].([]any); !ok {
		return nil, errors.New("profile groups are not a list")
	}
	// Without a version the shell would run every migration on the data, and not all of them are idempotent.
	for section, version := range map[string]string{"settings": "configVersion", "session": "sessionConfigVersion"} {
		if data, _ := p[section].(map[string]any); len(data) == 0 {
			continue
		}
		if n, _ := p[version].(json.Number); !positive(n) {
			return nil, fmt.Errorf("profile has %s but no %s", section, version)
		}
	}
	return p, nil
}

func checkShellSafe(p map[string]any) error {
	var err error
	var walk func(key string, v any)
	walk = func(key string, v any) {
		switch v := v.(type) {
		case string:
			if strings.ContainsFunc(v, isControl) {
				err = cmp.Or(err, fmt.Errorf("%s contains a control character", key))
			}
		case map[string]any:
			for k, mv := range v {
				if strings.ContainsFunc(k, isControl) {
					err = cmp.Or(err, fmt.Errorf("%s has a key with a control character", key))
				}
				walk(key+"."+k, mv)
			}
		case []any:
			for i, e := range v {
				walk(key+"."+strconv.Itoa(i), e)
			}
		}
	}
	for _, section := range []string{"name", "settings", "session"} {
		walk(section, p[section])
	}
	for _, r := range shellRules {
		walkPath(p, r.path, nil, func(key string, v any) {
			_, isNum := v.(json.Number)
			s, isStr := v.(string)
			bad := !isNum
			if r.deny != "" {
				bad = !isStr && v != nil || strings.ContainsAny(s, r.deny)
			}
			if bad {
				err = cmp.Or(err, fmt.Errorf("%s has a value that is not allowed", key))
			}
		})
	}
	return err
}

func positive(n json.Number) bool {
	f, err := n.Float64()
	return err == nil && f > 0
}

func isControl(r rune) bool {
	return r < 0x20 || r == 0x7f
}

// A "*" segment in path matches every key of a map.
func walkPath(v any, path, done []string, fn func(key string, v any)) {
	if len(path) == 0 {
		fn(strings.Join(done, "."), v)
		return
	}
	m, _ := v.(map[string]any)
	if path[0] != "*" {
		if mv, ok := m[path[0]]; ok {
			walkPath(mv, path[1:], append(done, path[0]), fn)
		}
		return
	}
	keys := slices.Sorted(maps.Keys(m))
	for _, k := range keys {
		walkPath(m[k], path[1:], append(slices.Clone(done), k), fn)
	}
}

func encodeProfile(p map[string]any) ([]byte, error) {
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	enc.SetIndent("", "  ")
	if err := enc.Encode(p); err != nil {
		return nil, fmt.Errorf("failed to encode profile: %w", err)
	}
	return buf.Bytes(), nil
}

// Empty values and colors ("#…") aren't paths.
func rewriteFileKeys(p map[string]any, fn func(key, value string) (string, error)) error {
	visit := func(key string, v any) (any, error) {
		s, ok := v.(string)
		if !ok || s == "" || strings.HasPrefix(s, "#") {
			return v, nil
		}
		return fn(key, s)
	}
	for _, fk := range fileKeys {
		section, _ := p[fk.Section].(map[string]any)
		v, ok := section[fk.Key]
		if !ok {
			continue
		}
		key := fk.Section + "." + fk.Key
		if !fk.Map {
			nv, err := visit(key, v)
			if err != nil {
				return err
			}
			section[fk.Key] = nv
			continue
		}
		m, _ := v.(map[string]any)
		for k, mv := range m {
			nv, err := visit(key+"."+k, mv)
			if err != nil {
				return err
			}
			m[k] = nv
		}
	}
	return nil
}

func addBytes(tw *tar.Writer, name string, data []byte) error {
	if err := tw.WriteHeader(&tar.Header{Name: name, Typeflag: tar.TypeReg, Mode: 0o644, Size: int64(len(data)), ModTime: time.Now()}); err != nil {
		return err
	}
	_, err := tw.Write(data)
	return err
}

func addFile(tw *tar.Writer, name, src string) error {
	f, err := os.Open(src)
	if err != nil {
		return err
	}
	defer f.Close()
	info, err := f.Stat()
	if err != nil {
		return err
	}
	if err := tw.WriteHeader(&tar.Header{Name: name, Typeflag: tar.TypeReg, Mode: 0o644, Size: info.Size(), ModTime: info.ModTime()}); err != nil {
		return err
	}
	_, err = io.CopyN(tw, f, info.Size())
	return err
}

func hashFile(file string) (string, error) {
	f, err := os.Open(file)
	if err != nil {
		return "", err
	}
	defer f.Close()
	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

func isWallpaperName(name string) bool {
	base, ok := strings.CutPrefix(name, wallpaperPart)
	return ok && wallpaperNameRe.MatchString(base) && (hasExt(base, imageExts) || hasExt(base, videoExts))
}

func isPreviewName(name string) bool {
	ext, ok := strings.CutPrefix(name, "preview")
	return ok && slices.Contains(imageExts, strings.ToLower(ext))
}

func hasExt(name string, exts []string) bool {
	return slices.Contains(exts, strings.ToLower(filepath.Ext(name)))
}

// newID matches the shell's profile ids: profile_<ms>_<7 chars of [a-z0-9]>.
func newID() (string, error) {
	const chars = "abcdefghijklmnopqrstuvwxyz0123456789"
	b := make([]byte, 7)
	if _, err := rand.Read(b); err != nil {
		return "", fmt.Errorf("failed to generate profile id: %w", err)
	}
	for i := range b {
		b[i] = chars[int(b[i])%len(chars)]
	}
	return "profile_" + strconv.FormatInt(time.Now().UnixMilli(), 10) + "_" + string(b), nil
}
