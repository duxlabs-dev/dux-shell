package iconfolders

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

const (
	fingerprintA = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	fingerprintB = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
)

// runs counts the fake generator's runs of one kind: built, helped or fingerprinted.
func (e selfEnv) runs(kind string) int {
	data, err := os.ReadFile(filepath.Join(e.bin, kind))
	if os.IsNotExist(err) {
		return 0
	}
	require.NoError(e.t, err)
	return strings.Count(string(data), "x")
}

func (e selfEnv) write(name, content string) {
	require.NoError(e.t, os.WriteFile(filepath.Join(e.bin, name), []byte(content), 0o644))
}

func (e selfEnv) applyOpts(o Options) State {
	state, err := Apply(o)
	require.NoError(e.t, err)
	return state
}

// tiledOpts colors app tiles from their logos, so a build also lists the pack's sources.
func (e selfEnv) tiledOpts() Options {
	o := e.opts()
	o.TileColor = TileApp
	return o
}

func TestSelfBuiltSkipsTheBuildWhenNothingChanged(t *testing.T) {
	e := newSelfEnv(t)
	e.colors("#69b2ff", "#003055")
	e.write("fingerprint", fingerprintA+"\n")
	e.write("sources", `{"apps":{"org.red.App":"/nowhere/red.png"}}`)

	first := e.applyOpts(e.tiledOpts())
	require.Equal(t, 1, e.runs("built"))
	require.FileExists(t, filepath.Join(e.bin, "dumped"))
	assert.Regexp(t, `^[0-9a-f]{32}-`+fingerprintA+`$`, first.Key)
	assert.Equal(t, 0, e.runs("fingerprinted"), "a build reports its fingerprint itself")
	assert.Equal(t, first, ReadState(e.state), "the key is committed with the state")
	helped := e.runs("helped")

	require.NoError(t, os.Remove(filepath.Join(e.bin, "dumped")))
	for range 2 {
		assert.Equal(t, first, e.applyOpts(e.tiledOpts()))
	}
	assert.Equal(t, 1, e.runs("built"), "nothing changed, so nothing is built")
	assert.NoFileExists(t, filepath.Join(e.bin, "dumped"), "nor are the sources listed")
	assert.Equal(t, helped, e.runs("helped"), "nor is the pack probed")
	assert.Equal(t, 2, e.runs("fingerprinted"))
}

func TestSelfBuiltRebuildsWhenAnInputChanges(t *testing.T) {
	e := newSelfEnv(t)
	e.colors("#69b2ff", "#003055")
	e.write("fingerprint", fingerprintA)
	o := e.opts()
	state := e.applyOpts(o)
	builds := 1

	rebuilt := func(why string, o Options, asked int) {
		t.Helper()
		fingerprinted := e.runs("fingerprinted")
		next := e.applyOpts(o)
		builds++
		require.Equal(t, builds, e.runs("built"), why)
		assert.Equal(t, fingerprinted+asked, e.runs("fingerprinted"), why)
		assert.NotEqual(t, state.Key, next.Key, why)
		state = e.applyOpts(o)
		assert.Equal(t, next, state, why+": and the new key holds")
		require.Equal(t, builds, e.runs("built"), why+": once")
	}

	// What DMS decides itself needs no fingerprint to tell it changed.
	o.Shape = "square"
	rebuilt("an argument", o, 0)
	o.TileColor = TileRing
	rebuilt("a tile option", o, 0)
	e.colors("#ffb4a8", "#690003")
	rebuilt("the colors", o, 0)
	o.Mode = "light"
	rebuilt("the mode", o, 0)
	generator, err := os.ReadFile(o.Generator)
	require.NoError(t, err)
	require.NoError(t, os.WriteFile(o.Generator, append(generator, "# upgraded\n"...), 0o755))
	rebuilt("the generator", o, 0)
	// The pack's own fingerprint covers its code, src and the apps and icon dirs it reads.
	e.write("fingerprint", fingerprintB)
	rebuilt("the apps and icons", o, 1)

	require.NoError(t, os.RemoveAll(state.Dir))
	next := e.applyOpts(o)
	assert.Equal(t, builds+1, e.runs("built"), "a pack deleted from under the state is built again")
	assert.Equal(t, state.Applied, next.Applied)
	assert.DirExists(t, next.Dir)
}

func TestSelfBuiltKeyTakesTheListingsFingerprint(t *testing.T) {
	e := newSelfEnv(t)
	e.colors("#69b2ff", "#003055")
	// An app icon changed after the listing read it and before the build did: the tiles are from the old one.
	e.write("dump-fingerprint", fingerprintA)
	e.write("fingerprint", fingerprintB)
	state := e.applyOpts(e.tiledOpts())
	assert.True(t, strings.HasSuffix(state.Key, "-"+fingerprintA), state.Key)

	require.NoError(t, os.Remove(filepath.Join(e.bin, "dump-fingerprint")))
	e.applyOpts(e.tiledOpts())
	assert.Equal(t, 2, e.runs("built"), "so the next apply builds again")
	e.applyOpts(e.tiledOpts())
	assert.Equal(t, 2, e.runs("built"))
}

func TestSelfBuiltSameContentKeepsItsNameAndTakesTheNewKey(t *testing.T) {
	e := newSelfEnv(t)
	e.colors("#69b2ff", "#003055")
	e.write("fingerprint", fingerprintA)
	first := e.applyOpts(e.opts())

	// An app installed without an icon of its own changes nothing in the pack.
	e.write("fingerprint", fingerprintB)
	second := e.applyOpts(e.opts())
	assert.Equal(t, 2, e.runs("built"))
	assert.Equal(t, first.Applied, second.Applied)
	assert.NotEqual(t, first.Key, second.Key)
	assert.Equal(t, second, ReadState(e.state))
	e.applyOpts(e.opts())
	assert.Equal(t, 2, e.runs("built"))
}

func TestSelfBuiltWithoutAFingerprintAlwaysBuilds(t *testing.T) {
	for _, tc := range []struct {
		name  string
		setup func(e selfEnv)
	}{
		{name: "a pack from before --fingerprint", setup: func(e selfEnv) {}},
		{name: "the released pack", setup: func(e selfEnv) { e.write("fingerprint", fingerprintA); e.flag("old") }},
		{name: "a fingerprint that is no digest", setup: func(e selfEnv) { e.write("fingerprint", "usage") }},
	} {
		t.Run(tc.name, func(t *testing.T) {
			e := newSelfEnv(t)
			e.colors("#69b2ff", "#003055")
			tc.setup(e)
			first := e.applyOpts(e.tiledOpts())
			assert.Empty(t, first.Key)
			second := e.applyOpts(e.tiledOpts())
			assert.Equal(t, first, second)
			assert.Equal(t, 2, e.runs("built"), "every apply builds")
			assert.Equal(t, 0, e.runs("fingerprinted"), "and the pack is never asked for a fingerprint")
		})
	}
}

func TestSelfBuiltStateWithoutAKeyRebuilds(t *testing.T) {
	e := newSelfEnv(t)
	e.colors("#69b2ff", "#003055")
	e.write("fingerprint", fingerprintA)
	first := e.applyOpts(e.opts())

	// A state written before keys, as an older DMS left it.
	old := first
	old.Key = ""
	data, err := json.Marshal(old)
	require.NoError(t, err)
	assert.NotContains(t, string(data), `"key"`)
	require.NoError(t, os.WriteFile(filepath.Join(e.state, StateFile), data, 0o644))
	require.Equal(t, old, ReadState(e.state))

	assert.Equal(t, first, e.applyOpts(e.opts()))
	assert.Equal(t, 2, e.runs("built"))
	e.applyOpts(e.opts())
	assert.Equal(t, 2, e.runs("built"))
}

func TestSelfBuiltKeyIsNotReusedForAnotherIconsDir(t *testing.T) {
	e := newSelfEnv(t)
	e.colors("#69b2ff", "#003055")
	e.write("fingerprint", fingerprintA)
	first := e.applyOpts(e.opts())

	o := e.opts()
	o.IconsDir = t.TempDir()
	moved := e.applyOpts(o)
	assert.Equal(t, 2, e.runs("built"), "a pack in another icons dir is not the committed one")
	assert.Equal(t, filepath.Join(o.IconsDir, first.Applied), moved.Dir)
}

func TestSelfBuiltFailureThatFellBackIsNotKept(t *testing.T) {
	e := newSelfEnv(t)
	e.colors("#69b2ff", "#003055")
	e.write("fingerprint", fingerprintA)

	// A source listing that fails keeps the theme tiles for this build only.
	e.flag("dump-fail")
	assert.Empty(t, e.applyOpts(e.tiledOpts()).Key)
	require.NoError(t, os.Remove(filepath.Join(e.bin, "dump-fail")))
	e.write("sources", `{"apps":{"org.red.App":"/nowhere/red.png"}}`)
	listed := e.applyOpts(e.tiledOpts())
	assert.Equal(t, 2, e.runs("built"), "the next apply lists and builds again")
	assert.NotEmpty(t, listed.Key)
	dumpWarned.Delete(e.opts().Generator)
}

func TestSelfBuiltUntiledBuildIsNotKept(t *testing.T) {
	e := newSelfEnv(t)
	e.colors("#69b2ff", "#003055")
	e.write("fingerprint", fingerprintA)
	o := e.opts()
	// A --help that failed reads as a pack without --tiles, which no pack that fingerprints is.
	info, err := os.Stat(o.Generator)
	require.NoError(t, err)
	key := generatorFile{path: o.Generator, size: info.Size(), modTime: info.ModTime().UnixNano()}
	probedFlags.Store(key, generatorFlags{})
	defer probedFlags.Delete(key)
	assert.Empty(t, e.applyOpts(o).Key)
	probedFlags.Delete(key)
	assert.NotEmpty(t, e.applyOpts(o).Key)
	assert.Equal(t, 2, e.runs("built"))
}
