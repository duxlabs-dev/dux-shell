package iconfolders

import (
	"encoding/json"
	"os"
	"path/filepath"
	"regexp"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// A stand-in for the dux-icons command: it writes what it was asked for, or fails on request.
const fakeGenerator = `#!/bin/sh
here=$(dirname "$0")
while [ $# -gt 0 ]; do
	# The released pack, like argparse, rejects every flag from after its time.
	if [ -e "$here/old" ]; then
		case "$1" in
		--out|--name|--palette|--from-dms|--mode|--badge|--glyph|--back|--mono|--no-mono|--shape|--gradient|--no-gradient|-v|--verbose|-h|--help) ;;
		*) unknown="$unknown $1" ;;
		esac
	fi
	case "$1" in
	--out) out=$2; shift ;;
	--name) name=$2; shift ;;
	--tile) tile=$2; flag=tile; shift ;;
	--badge) tile=$2; flag=badge; shift ;;
	--glyph) glyph=$2; shift ;;
	--back) back=$2; shift ;;
	--mono) mono=yes ;;
	--no-mono) mono=no ;;
	--app-style) mono=$2; shift ;;
	--gradient) gradient=shaded ;;
	--no-gradient) gradient=flat ;;
	--shape) shape=$2; shift ;;
	--own-tone) own=$2; shift ;;
	--files-style) files=$2; shift ;;
	--tiles) tiles=$2; shift ;;
	--dump-sources) dump=yes ;;
	--help) help=yes ;;
	--fingerprint) fingerprint=yes ;;
	esac
	shift
done
# Only a pack given a fingerprint file fingerprints; the rest reject --fingerprint the way argparse does.
print=$(cat "$here/fingerprint" 2>/dev/null)
[ -e "$here/old" ] && print=
if [ -n "$fingerprint" ]; then
	echo x >> "$here/fingerprinted"
	[ -n "$print" ] && { echo "$print"; exit 0; }
	echo "dux-icons: error: unrecognized arguments: --fingerprint" >&2; exit 2
fi
# The released pack calls the tile color --badge. A newer pack takes both color flags but lists only --tile.
if [ -e "$here/old" ]; then
	[ -n "$help" ] && { echo x >> "$here/helped"; echo "usage: dux-icons [-h] [--out DIR] [--badge HEX] [--mono | --no-mono] [--shape NAME]"; exit 0; }
	[ -n "$unknown" ] && { echo "usage: dux-icons [-h]" >&2; echo "dux-icons: error: unrecognized arguments:$unknown" >&2; exit 2; }
fi
# A pack from before --app-style lists only --mono.
if [ -e "$here/no-app-style" ]; then
	[ -n "$help" ] && { echo x >> "$here/helped"; echo "usage: dux-icons [-h] [--tile HEX] [--mono] [--tiles FILE] [--dump-sources]"; exit 0; }
	case "$mono" in yes|no|'') ;; *) echo "dux-icons: error: unrecognized arguments: --app-style" >&2; exit 2 ;; esac
fi
[ -n "$help" ] && { echo x >> "$here/helped"; echo "usage: dux-icons [-h] [--tile HEX] [--app-style {color,themed,monochrome}] [--tiles FILE] [--own-tone L] [--files-style {standard,color}] [--dump-sources]"; exit 0; }
if [ -n "$dump" ]; then
	[ -e "$here/dump-fail" ] && { echo "first line" >&2; echo "timed out" >&2; exit 1; }
	echo "$tile $glyph $back $mono" > "$here/dumped"
	listed=$(cat "$here/dump-fingerprint" 2>/dev/null || echo "$print")
	listing=$(cat "$here/sources" 2>/dev/null || echo '{"apps":{}}')
	if [ -n "$listed" ]; then echo "$listing" | sed "s/^{/{\"fingerprint\":\"$listed\",/"; else echo "$listing"; fi
	exit 0
fi
[ -e "$here/fail" ] && { echo "first line" >&2; echo "cannot build" >&2; exit 3; }
echo x >> "$here/built"
mkdir -p "$out/scalable/places"
[ -e "$here/no-index" ] || printf '[Icon Theme]\nName=%s\nDirectories=scalable/places\n' "$name" > "$out/index.theme"
printf '%s %s %s %s' "$tile" "$glyph" "$back" "$mono" > "$out/scalable/places/folder.svg"
printf '%s' "$flag" > "$out/scalable/places/tile-flag"
ln -s folder.svg "$out/scalable/places/inode-directory.svg"
printf '%s %s' "${shape-default}" "$gradient" > "$out/scalable/places/style"
[ -e "$here/paths" ] && cp "$here/paths" "$out/icon-paths.json"
[ -e "$here/bare" ] && mkdir -p "$out/bare/apps"
[ -n "$own" ] && printf '%s' "$own" > "$out/scalable/places/own-tone"
[ -n "$files" ] && printf '%s' "$files" > "$out/scalable/places/files-style"
[ -n "$tiles" ] && cp "$tiles" "$out/tiles.json" && printf '%s' "$tiles" > "$here/tiles-path"
echo "Dux Icons: published"
[ -n "$print" ] && echo "  fingerprint: $print"
exit 0
`

type selfEnv struct {
	env
	bin string
}

func newSelfEnv(t *testing.T) selfEnv {
	e := selfEnv{env: newEnv(t), bin: t.TempDir()}
	require.NoError(t, os.WriteFile(filepath.Join(e.bin, SelfBuilt), []byte(fakeGenerator), 0o755))
	return e
}

func (e selfEnv) opts() Options {
	o := e.env.opts(SelfBuilt)
	o.Generator = filepath.Join(e.bin, SelfBuilt)
	return o
}

func (e selfEnv) apply(style string) State {
	o := e.opts()
	o.AppStyle = style
	state, err := Apply(o)
	require.NoError(e.t, err)
	return state
}

func (e selfEnv) flag(name string) {
	require.NoError(e.t, os.WriteFile(filepath.Join(e.bin, name), nil, 0o644))
}

func TestSelfBuiltPackIsNamedAfterItsContent(t *testing.T) {
	e := newSelfEnv(t)
	ramp := e.colors("#69b2ff", "#003055")

	state := e.apply(AppColor)
	require.Regexp(t, regexp.MustCompile(`^dux-icons-dms-[0-9a-f]{8}$`), state.Applied)
	assert.Equal(t, "dux-icons-dms-"+state.Inputs[:8], state.Applied)
	assert.Equal(t, SelfBuilt, state.Base)
	assert.Equal(t, filepath.Join(e.icons, state.Applied), state.Dir)
	assert.Equal(t, state, ReadState(e.state))
	assert.Equal(t, []string{state.Applied}, e.generated(), "the staging directory must be gone")

	assert.Equal(t, ramp.Front+" "+ramp.Glyph+" "+ramp.Back+" color", e.overlay(state.Applied, "scalable/places/folder.svg"))
	index := e.overlay(state.Applied, "index.theme")
	assert.Contains(t, index, "[Icon Theme]\nHidden=true\n"+generatedKey+"\nName=Dux Icons\n")
	target, err := os.Readlink(filepath.Join(state.Dir, "scalable/places/inode-directory.svg"))
	require.NoError(t, err)
	assert.Equal(t, "folder.svg", target)

	assert.Equal(t, state, e.apply(AppColor), "the same build keeps its name")
	assert.Equal(t, []string{state.Applied}, e.generated())

	mono := e.apply(AppThemed)
	assert.NotEqual(t, state.Applied, mono.Applied)
	assert.Contains(t, e.overlay(mono.Applied, "scalable/places/folder.svg"), " themed")
	assert.ElementsMatch(t, []string{state.Applied, mono.Applied}, e.generated(), "running apps may still read the previous one")

	e.colors("#a1d39a", "#0a390f")
	recolored := e.apply(AppThemed)
	assert.ElementsMatch(t, []string{mono.Applied, recolored.Applied}, e.generated())

	require.NoError(t, Clear(e.opts()))
	assert.Empty(t, e.generated())
	assert.Equal(t, State{}, ReadState(e.state))
}

func TestSelfBuiltPackTakesItsShapeAndShading(t *testing.T) {
	e := newSelfEnv(t)
	e.colors("#69b2ff", "#003055")

	plain := e.apply(AppColor)
	assert.Equal(t, "default flat", e.overlay(plain.Applied, "scalable/places/style"))

	o := e.opts()
	o.Shape, o.Gradient = "squircle", true
	styled, err := Apply(o)
	require.NoError(t, err)
	assert.NotEqual(t, plain.Applied, styled.Applied)
	assert.Equal(t, "squircle shaded", e.overlay(styled.Applied, "scalable/places/style"))

	o.Shape = "../square"
	state, err := Apply(o)
	require.ErrorContains(t, err, "bad icon shape")
	assert.Equal(t, styled, state)
	assert.ElementsMatch(t, []string{plain.Applied, styled.Applied}, e.generated())
}

func TestSelfBuiltPackTakesItsFileStyle(t *testing.T) {
	e := newSelfEnv(t)
	e.colors("#69b2ff", "#003055")

	plain := e.apply(AppColor)
	o := e.opts()
	o.FileStyle = FilesStandard
	standard, err := Apply(o)
	require.NoError(t, err)
	assert.Equal(t, plain, standard, "standard is the build without the flag")
	assert.NoFileExists(t, filepath.Join(e.icons, plain.Applied, "scalable/places/files-style"))

	o.FileStyle = FilesColor
	colored, err := Apply(o)
	require.NoError(t, err)
	assert.NotEqual(t, plain.Applied, colored.Applied, "a new file style is a new theme")
	assert.Equal(t, "color", e.overlay(colored.Applied, "scalable/places/files-style"))
}

func TestSelfBuiltPackListsTheIconsThatStandInForFilePaths(t *testing.T) {
	e := newSelfEnv(t)
	e.colors("#69b2ff", "#003055")
	listed := `{"/opt/app/icon.png": "scalable/places/folder.svg", "/opt/gone.png": "scalable/places/absent.svg", "/opt/out.png": "../folder.svg"}`
	require.NoError(t, os.WriteFile(filepath.Join(e.bin, "paths"), []byte(listed), 0o644))

	state := e.apply(AppColor)
	assert.Equal(t, map[string]string{"/opt/app/icon.png": "scalable/places/folder.svg"}, state.Icons)
	assert.Equal(t, state, ReadState(e.state))

	require.NoError(t, os.WriteFile(filepath.Join(e.bin, "paths"), []byte("not json"), 0o644))
	assert.Empty(t, e.apply(AppColor).Icons)
}

func TestSelfBuiltPackReportsItsTileFreeAppIcons(t *testing.T) {
	e := newSelfEnv(t)
	e.colors("#69b2ff", "#003055")
	assert.False(t, e.apply(AppColor).Bare, "older packs write no bare icons")

	e.flag("bare")
	state := e.apply(AppColor)
	assert.True(t, state.Bare)
	assert.Equal(t, state, ReadState(e.state))

	// A state written before Bare existed names the same build.
	old := state
	old.Bare = false
	data, err := json.Marshal(old)
	require.NoError(t, err)
	o := e.opts()
	require.NoError(t, os.WriteFile(o.statePath(), data, 0o644))
	assert.True(t, e.apply(AppColor).Bare)
}

func TestSelfBuiltPackWithoutItsCommandIsLeftAsInstalled(t *testing.T) {
	e := newSelfEnv(t)
	t.Setenv("PATH", t.TempDir())
	t.Setenv("HOME", t.TempDir())
	missing := e.env.opts(SelfBuilt)

	state, err := Apply(missing)
	require.NoError(t, err)
	assert.Equal(t, State{}, state)
	assert.NoFileExists(t, filepath.Join(e.state, StateFile))
	assert.Empty(t, e.generated())

	assert.Equal(t, CodeNoGenerator, ProbeTheme(missing).Code)
	probe := ProbeTheme(e.opts())
	assert.Equal(t, CodeSelfColored, probe.Code)
	assert.False(t, probe.Supported, "the folder toggle has nothing to add to this pack")
	assert.Empty(t, e.generated(), "a probe builds nothing")
}

func TestSelfBuiltPackIsFoundInTheUserBinDir(t *testing.T) {
	e := newSelfEnv(t)
	home := t.TempDir()
	t.Setenv("PATH", t.TempDir())
	t.Setenv("HOME", home)
	require.NoError(t, os.MkdirAll(filepath.Join(home, ".local", "bin"), 0o755))
	require.NoError(t, os.Symlink(filepath.Join(e.bin, SelfBuilt), filepath.Join(home, ".local", "bin", SelfBuilt)))

	found := e.env.opts(SelfBuilt)
	assert.Equal(t, filepath.Join(home, ".local", "bin", SelfBuilt), found.generator())

	require.NoError(t, os.Chmod(filepath.Join(e.bin, SelfBuilt), 0o644))
	assert.Empty(t, found.generator(), "a file that cannot run is not the command")
}

func TestFailedSelfBuildKeepsThePreviousTheme(t *testing.T) {
	tests := []struct {
		name string
		flag string
		want string
	}{
		{name: "the command fails", flag: "fail", want: "cannot build"},
		{name: "the command writes no index", flag: "no-index", want: "is not an icon theme index"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			e := newSelfEnv(t)
			prev := e.apply(AppColor)
			e.colors("#a1d39a", "#0a390f")
			e.flag(tc.flag)

			state, err := Apply(e.opts())
			require.ErrorContains(t, err, tc.want)
			assert.Equal(t, prev, state)
			assert.Equal(t, prev, ReadState(e.state))
			assert.Equal(t, []string{prev.Applied}, e.generated())
		})
	}
}

func TestSelfBuiltPackNeverReplacesWhatItDidNotWrite(t *testing.T) {
	e := newSelfEnv(t)
	state := e.apply(AppColor)
	index := filepath.Join(state.Dir, "index.theme")
	require.NoError(t, os.WriteFile(index, []byte("[Icon Theme]\nName=Mine\n"), 0o644))
	require.NoError(t, os.Remove(filepath.Join(e.state, StateFile)))

	_, err := Apply(e.opts())
	require.ErrorIs(t, err, ErrOccupied)
	assert.Equal(t, "[Icon Theme]\nName=Mine\n", e.overlay(state.Applied, "index.theme"))
}
