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
while [ $# -gt 0 ]; do
	case "$1" in
	--out) out=$2; shift ;;
	--name) name=$2; shift ;;
	--badge) badge=$2; shift ;;
	--glyph) glyph=$2; shift ;;
	--back) back=$2; shift ;;
	--mono) mono=yes ;;
	--no-mono) mono=no ;;
	--gradient) gradient=shaded ;;
	--no-gradient) gradient=flat ;;
	--shape) shape=$2; shift ;;
	esac
	shift
done
here=$(dirname "$0")
[ -e "$here/fail" ] && { echo "first line" >&2; echo "cannot build" >&2; exit 3; }
mkdir -p "$out/scalable/places"
[ -e "$here/no-index" ] || printf '[Icon Theme]\nName=%s\nDirectories=scalable/places\n' "$name" > "$out/index.theme"
printf '%s %s %s %s' "$badge" "$glyph" "$back" "$mono" > "$out/scalable/places/folder.svg"
ln -s folder.svg "$out/scalable/places/inode-directory.svg"
printf '%s %s' "${shape-default}" "$gradient" > "$out/scalable/places/style"
[ -e "$here/paths" ] && cp "$here/paths" "$out/icon-paths.json"
[ -e "$here/bare" ] && mkdir -p "$out/bare/apps"
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

func (e selfEnv) apply(mono bool) State {
	o := e.opts()
	o.MonoApps = mono
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

	state := e.apply(false)
	require.Regexp(t, regexp.MustCompile(`^dux-icons-dms-[0-9a-f]{8}$`), state.Applied)
	assert.Equal(t, "dux-icons-dms-"+state.Inputs[:8], state.Applied)
	assert.Equal(t, SelfBuilt, state.Base)
	assert.Equal(t, filepath.Join(e.icons, state.Applied), state.Dir)
	assert.Equal(t, state, ReadState(e.state))
	assert.Equal(t, []string{state.Applied}, e.generated(), "the staging directory must be gone")

	assert.Equal(t, ramp.Front+" "+ramp.Glyph+" "+ramp.Back+" no", e.overlay(state.Applied, "scalable/places/folder.svg"))
	index := e.overlay(state.Applied, "index.theme")
	assert.Contains(t, index, "[Icon Theme]\nHidden=true\n"+generatedKey+"\nName=Dux Icons\n")
	target, err := os.Readlink(filepath.Join(state.Dir, "scalable/places/inode-directory.svg"))
	require.NoError(t, err)
	assert.Equal(t, "folder.svg", target)

	assert.Equal(t, state, e.apply(false), "the same build keeps its name")
	assert.Equal(t, []string{state.Applied}, e.generated())

	mono := e.apply(true)
	assert.NotEqual(t, state.Applied, mono.Applied)
	assert.Contains(t, e.overlay(mono.Applied, "scalable/places/folder.svg"), " yes")
	assert.ElementsMatch(t, []string{state.Applied, mono.Applied}, e.generated(), "running apps may still read the previous one")

	e.colors("#a1d39a", "#0a390f")
	recolored := e.apply(true)
	assert.ElementsMatch(t, []string{mono.Applied, recolored.Applied}, e.generated())

	require.NoError(t, Clear(e.opts()))
	assert.Empty(t, e.generated())
	assert.Equal(t, State{}, ReadState(e.state))
}

func TestSelfBuiltPackTakesItsShapeAndShading(t *testing.T) {
	e := newSelfEnv(t)
	e.colors("#69b2ff", "#003055")

	plain := e.apply(false)
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

func TestSelfBuiltPackListsTheIconsThatStandInForFilePaths(t *testing.T) {
	e := newSelfEnv(t)
	e.colors("#69b2ff", "#003055")
	listed := `{"/opt/app/icon.png": "scalable/places/folder.svg", "/opt/gone.png": "scalable/places/absent.svg", "/opt/out.png": "../folder.svg"}`
	require.NoError(t, os.WriteFile(filepath.Join(e.bin, "paths"), []byte(listed), 0o644))

	state := e.apply(false)
	assert.Equal(t, map[string]string{"/opt/app/icon.png": "scalable/places/folder.svg"}, state.Icons)
	assert.Equal(t, state, ReadState(e.state))

	require.NoError(t, os.WriteFile(filepath.Join(e.bin, "paths"), []byte("not json"), 0o644))
	assert.Empty(t, e.apply(false).Icons)
}

func TestSelfBuiltPackReportsItsBadgeFreeAppIcons(t *testing.T) {
	e := newSelfEnv(t)
	e.colors("#69b2ff", "#003055")
	assert.False(t, e.apply(false).Bare, "older packs write no bare icons")

	e.flag("bare")
	state := e.apply(false)
	assert.True(t, state.Bare)
	assert.Equal(t, state, ReadState(e.state))

	// A state written before Bare existed names the same build.
	old := state
	old.Bare = false
	data, err := json.Marshal(old)
	require.NoError(t, err)
	o := e.opts()
	require.NoError(t, os.WriteFile(o.statePath(), data, 0o644))
	assert.True(t, e.apply(false).Bare)
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
			prev := e.apply(false)
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
	state := e.apply(false)
	index := filepath.Join(state.Dir, "index.theme")
	require.NoError(t, os.WriteFile(index, []byte("[Icon Theme]\nName=Mine\n"), 0o644))
	require.NoError(t, os.Remove(filepath.Join(e.state, StateFile)))

	_, err := Apply(e.opts())
	require.ErrorIs(t, err, ErrOccupied)
	assert.Equal(t, "[Icon Theme]\nName=Mine\n", e.overlay(state.Applied, "index.theme"))
}
