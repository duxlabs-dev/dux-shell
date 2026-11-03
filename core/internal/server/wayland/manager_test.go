package wayland

import (
	"encoding/json"
	"errors"
	"fmt"
	"maps"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"

	wlclient "github.com/duxlabs-dev/dux-go/wayland/client"

	"github.com/duxlabs-dev/dux-shell/core/internal/icc"
	mocks_wlclient "github.com/duxlabs-dev/dux-shell/core/internal/mocks/wlclient"
	"github.com/duxlabs-dev/dux-shell/core/internal/proto/wlr_gamma_control"
)

func TestManager_ActorSerializesOutputStateAccess(t *testing.T) {
	m := &Manager{
		cmdq:     make(chan cmd, 8192),
		stopChan: make(chan struct{}),
	}

	m.wg.Add(1)
	go m.waylandActor()

	state := &outputState{
		id:           1,
		registryName: 100,
		rampSize:     256,
	}
	m.outputs.Store(state.id, state)

	var wg sync.WaitGroup
	const goroutines = 50
	const iterations = 100

	for i := range goroutines {
		wg.Add(1)
		go func(id int) {
			defer wg.Done()
			for j := range iterations {
				m.post(func() {
					if out, ok := m.outputs.Load(state.id); ok {
						out.rampSize = uint32(j)
						out.failed = j%2 == 0
						out.retryCount = j
						out.lastFailTime = time.Now()
					}
				})
			}
		}(i)
	}

	wg.Wait()

	done := make(chan struct{})
	m.post(func() { close(done) })
	<-done

	close(m.stopChan)
	m.wg.Wait()
}

func TestManager_ConcurrentGetState(t *testing.T) {
	m := &Manager{
		state: &State{
			CurrentTemp: 5000,
			IsDay:       true,
		},
	}

	var wg sync.WaitGroup
	const goroutines = 50
	const iterations = 100

	for range goroutines / 2 {
		wg.Go(func() {
			for range iterations {
				s := m.GetState()
				assert.GreaterOrEqual(t, s.CurrentTemp, 0)
			}
		})
	}

	for i := range goroutines / 2 {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			for j := range iterations {
				m.stateMutex.Lock()
				m.state = &State{
					CurrentTemp: 4000 + i*100,
					IsDay:       j%2 == 0,
				}
				m.stateMutex.Unlock()
			}
		}(i)
	}

	wg.Wait()
}

func TestInterpolate_EdgeCases(t *testing.T) {
	now := time.Now()

	tests := []struct {
		name     string
		now      time.Time
		start    time.Time
		stop     time.Time
		expected float64
	}{
		{
			name:     "same start and stop",
			now:      now,
			start:    now,
			stop:     now,
			expected: 1.0,
		},
		{
			name:     "now before start",
			now:      now,
			start:    now.Add(time.Hour),
			stop:     now.Add(2 * time.Hour),
			expected: 0.0,
		},
		{
			name:     "now after stop",
			now:      now.Add(3 * time.Hour),
			start:    now,
			stop:     now.Add(time.Hour),
			expected: 1.0,
		},
		{
			name:     "now at midpoint",
			now:      now.Add(30 * time.Minute),
			start:    now,
			stop:     now.Add(time.Hour),
			expected: 0.5,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := interpolate(tt.now, tt.start, tt.stop)
			assert.InDelta(t, tt.expected, result, 0.01)
		})
	}
}

func TestNotifySubscribers_NonBlocking(t *testing.T) {
	m := &Manager{
		dirty: make(chan struct{}, 1),
	}

	for range 10 {
		m.notifySubscribers()
	}

	assert.Len(t, m.dirty, 1)
}

func TestNewManager_GetRegistryError(t *testing.T) {
	mockDisplay := mocks_wlclient.NewMockWaylandDisplay(t)

	mockDisplay.EXPECT().Context().Return(nil)
	mockDisplay.EXPECT().GetRegistry().Return(nil, errors.New("failed to get registry"))

	config := DefaultConfig()
	_, err := NewManager(mockDisplay, config)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "get registry")
}

func TestNewManager_InvalidConfig(t *testing.T) {
	mockDisplay := mocks_wlclient.NewMockWaylandDisplay(t)

	config := Config{
		LowTemp:  500,
		HighTemp: 6500,
		Gamma:    1.0,
		Contrast: 1.0,
	}

	_, err := NewManager(mockDisplay, config)
	assert.Error(t, err)
}

func TestSetters_RejectedValuesLeaveConfigUntouched(t *testing.T) {
	newManager := func() *Manager {
		return &Manager{
			config:        DefaultConfig(),
			updateTrigger: make(chan struct{}, 1),
		}
	}

	t.Run("SetTemperature", func(t *testing.T) {
		m := newManager()
		before := m.config

		err := m.SetTemperature(3200, 2500)
		assert.Error(t, err)
		assert.Equal(t, before, m.config)
		assert.Empty(t, m.updateTrigger)
	})

	t.Run("SetLocation", func(t *testing.T) {
		m := newManager()
		before := m.config

		err := m.SetLocation(120.0, 10.0)
		assert.Error(t, err)
		assert.Equal(t, before, m.config)
		assert.Empty(t, m.updateTrigger)
	})

	t.Run("SetAdjustments", func(t *testing.T) {
		m := newManager()
		before := m.config

		err := m.SetAdjustments(-1.0, 1.0)
		assert.Error(t, err)
		assert.Equal(t, before, m.config)
		assert.Empty(t, m.updateTrigger)
	})
}

func TestSetters_ValidValuesCommitAndTrigger(t *testing.T) {
	m := &Manager{
		config:        DefaultConfig(),
		updateTrigger: make(chan struct{}, 1),
	}

	err := m.SetTemperature(3000, 6000)
	assert.NoError(t, err)
	assert.Equal(t, 3000, m.config.LowTemp)
	assert.Equal(t, 6000, m.config.HighTemp)
	assert.Len(t, m.updateTrigger, 1)
}

func TestApplyGamma_SkipsUnchangedTempAndGamma(t *testing.T) {
	m := &Manager{config: DefaultConfig()}
	m.controlsInitialized = true

	out := &outputState{
		id:           1,
		rampSize:     256,
		gammaControl: &wlr_gamma_control.ZwlrGammaControlV1{},
		lastTemp:     5000,
		lastGamma:    m.config.Gamma,
	}
	m.outputs.Store(out.id, out)

	m.applyGamma(5000)

	assert.False(t, out.failed, "unchanged temp must not reach the compositor write path")
	assert.Equal(t, 5000, out.lastTemp)
	assert.Equal(t, uint32(256), out.rampSize)
}

func TestSetAdjustments_UnchangedValuesDoNotTouchActor(t *testing.T) {
	m := &Manager{config: DefaultConfig(), cmdq: make(chan cmd, 1)}

	assert.NoError(t, m.SetAdjustments(1.0, 1.0))
	assert.Empty(t, m.cmdq, "neutral defaults resent must not schedule any work")

	assert.Error(t, m.SetAdjustments(1.0, 3.0))
	assert.Equal(t, DefaultConfig(), m.config)
	assert.Empty(t, m.cmdq)

	assert.NoError(t, m.SetAdjustments(1.2, 1.5))
	assert.Equal(t, 1.2, m.config.Gamma)
	assert.Equal(t, 1.5, m.config.Contrast)
	assert.Len(t, m.cmdq, 1, "one change must schedule exactly one sync")

	assert.NoError(t, m.SetAdjustments(1.2, 1.5))
	assert.Len(t, m.cmdq, 1, "resending the same values must not schedule more work")
}

func TestOutputState_RampCurrent(t *testing.T) {
	out := &outputState{lastTemp: 5000, lastGamma: 1.0, lastContrast: 1.0}

	assert.True(t, out.rampCurrent(5000, 1.0, 1.0))
	assert.False(t, out.rampCurrent(4500, 1.0, 1.0))
	assert.False(t, out.rampCurrent(5000, 1.2, 1.0))
	assert.False(t, out.rampCurrent(5000, 1.0, 1.4))
}

// needsControls decides whether gamma controls are created at all. ICC
// profiles and per-output temperatures apply independently of the night light
// schedule, so they have to keep the controls alive: otherwise turning the
// night light off tears the controls down and drops the ICC ramps.
func TestManager_NeedsControlsCoversICCAndOutputTemps(t *testing.T) {
	base := Config{Enabled: false, Gamma: 1.0, Contrast: 1.0}

	cases := []struct {
		name string
		cfg  Config
		want bool
	}{
		{"idle", base, false},
		{"night light on", Config{Enabled: true, Gamma: 1.0, Contrast: 1.0}, true},
		{"gamma tweak", Config{Gamma: 1.2, Contrast: 1.0}, true},
		{"contrast tweak", Config{Gamma: 1.0, Contrast: 1.2}, true},
		{"icc profile only", Config{Gamma: 1.0, Contrast: 1.0, ICCProfiles: map[string]string{"DP-1": "/tmp/display.icc"}}, true},
		{"output temp only", Config{Gamma: 1.0, Contrast: 1.0, OutputTemps: map[string]int{"DP-1": 7000}}, true},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			m := &Manager{config: tc.cfg}
			assert.Equal(t, tc.want, m.needsControls())
		})
	}
}

// The registry handler can establish the gamma controls before the startup post
// runs, so loading the configured ICC profiles and temperatures must not depend
// on the controls still being uninitialized.
func TestManager_LoadConfiguredICCWhenControlsAlreadyExist(t *testing.T) {
	dir := t.TempDir()
	m := &Manager{config: Config{
		ICCProfiles: map[string]string{"DP-2": filepath.Join(dir, "missing.icm")},
		OutputTemps: map[string]int{"DP-1": 7000},
	}}
	m.controlsInitialized = true

	dp1 := &outputState{id: 1}
	m.outputs.Store(1, dp1)
	m.outputNames.Store(1, "DP-1")

	dp2 := &outputState{id: 2}
	m.outputs.Store(2, dp2)
	m.outputNames.Store(2, "DP-2")

	if !m.loadConfiguredICC() {
		t.Fatal("loadConfiguredICC() = false, want true")
	}
	assert.Equal(t, 7000, dp1.outputTemp, "configured temperature should attach")

	// An unreadable profile must be skipped without aborting the rest.
	assert.Empty(t, dp2.iccPath, "unparsable profile should not attach")
}

// A hotplugged output gets its configured profile and temperature attached as
// soon as its name is known.
func TestManager_AttachConfiguredICCForNamedOutput(t *testing.T) {
	m := &Manager{config: Config{OutputTemps: map[string]int{"DP-3": 6500}}}

	configured := &outputState{id: 3}
	m.outputs.Store(3, configured)
	m.outputNames.Store(3, "DP-3")

	m.attachConfiguredICC(3, "DP-3")
	assert.Equal(t, 6500, configured.outputTemp)

	plain := &outputState{id: 4}
	m.outputs.Store(4, plain)
	m.attachConfiguredICC(4, "HDMI-A-1")
	assert.Zero(t, plain.outputTemp, "outputs without configuration are left alone")
}

// Each display can keep its own temperature: a per-output override wins over the
// night light schedule, and 0 means "no override" rather than 0K.
func TestEffectiveTempTarget(t *testing.T) {
	cases := []struct {
		name         string
		outputTemp   int
		scheduleTemp int
		want         int
	}{
		{"override wins over the schedule", 7000, 5000, 7000},
		{"schedule applies without an override", 0, 5000, 5000},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			out := &outputState{outputTemp: tc.outputTemp}
			assert.Equal(t, tc.want, effectiveTempTarget(out, tc.scheduleTemp))
		})
	}
}

// A re-created gamma control (night light toggled, outputs re-enumerated) must
// not drop the configured ICC state of the output it belongs to.
func TestManager_ControlStateReuseKeepsAttachedICC(t *testing.T) {
	m := &Manager{}
	existing := &outputState{
		id:           1,
		registryName: 10,
		iccPath:      "/tmp/display.icm",
		iccProfile:   &icc.Profile{Description: "Test Display"},
		outputTemp:   7000,
		rampSize:     256,
		failed:       true,
		retryCount:   3,
		lastFailTime: time.Now(),
		lastTemp:     7000,
		lastGamma:    1.1,
		lastContrast: 0.9,
	}
	m.outputs.Store(1, existing)

	got := m.controlStateFor(1, 10, nil, "control-2")

	assert.Same(t, existing, got, "the output keeps its state across control re-creation")
	assert.Equal(t, "/tmp/display.icm", got.iccPath, "the attached profile survives")
	assert.Equal(t, 7000, got.outputTemp, "the per-output temperature survives")
	assert.Equal(t, "control-2", got.gammaControl, "the new control is attached")

	assert.Zero(t, got.rampSize, "the new control has not reported gamma_size yet")
	assert.False(t, got.failed)
	assert.Zero(t, got.retryCount)
	assert.Zero(t, got.lastTemp, "the ramp has to be written again")

	fresh := m.controlStateFor(2, 20, nil, "control-3")
	assert.NotSame(t, existing, fresh)
	assert.Empty(t, fresh.iccPath, "an output seen for the first time starts clean")
	assert.Zero(t, fresh.outputTemp)
}

// A wl_output that has no gamma control (the default install: night light off,
// no profile, no override) exists only in the name maps. It still has to
// disappear from listOutputs/status once it is gone, or every dock/undock cycle
// leaves another monitor in maps that live as long as the daemon.
func TestManager_RemoveOutputByRegistryNameWithoutControl(t *testing.T) {
	m := &Manager{}
	m.outputNames.Store(9, "HDMI-A-1")
	m.outputRegNames.Store(9, 77)

	assert.Equal(t, []string{"HDMI-A-1"}, m.ListOutputs())

	m.removeOutputByRegistryName(77)

	assert.Empty(t, m.ListOutputs(), "a monitor with no control must not stay listed")
	_, nameStored := m.outputNames.Load(9)
	assert.False(t, nameStored, "the name entry should be gone")
	_, regStored := m.outputRegNames.Load(9)
	assert.False(t, regStored, "the registry name entry should be gone")
}

// The status payload is what the settings UI shows for a profile, so the
// descriptive metadata has to be carried through.
func TestManager_GetICCStatusDescribesProfile(t *testing.T) {
	dir := t.TempDir()
	profilePath := filepath.Join(dir, "display.icm")
	if err := os.WriteFile(profilePath, []byte("stub"), 0o644); err != nil {
		t.Fatalf("write stub profile: %v", err)
	}

	gamma := icc.Curve{Type: icc.CurveParametric, Gamma: 2.2}
	m := &Manager{}
	m.outputs.Store(1, &outputState{
		id:      1,
		iccPath: profilePath,
		iccProfile: &icc.Profile{
			Description: "Test Display",
			Version:     "2.1.0",
			Class:       "mntr",
			ColorSpace:  "RGB",
			HasTRC:      true,
			TRC:         [3]icc.Curve{gamma, gamma, gamma},
			HasVCGT:     true,
			VCGT:        &icc.VCGT{Channels: 3, Entries: 1024},
			WhitePoint:  [3]float64{0.9505, 1.0, 1.0890},
		},
	})
	m.outputNames.Store(1, "DP-2")
	m.publishICCState()

	status := m.GetICCStatus()["DP-2"]
	if status == nil {
		t.Fatal("no status for DP-2")
	}

	assert.True(t, status.Active)
	assert.Equal(t, "mntr", status.Class)
	assert.Equal(t, "gamma", status.TRCKind)
	assert.Equal(t, 2.2, status.TRCGamma)
	assert.Equal(t, 3, status.VCGTChannels)
	assert.Equal(t, 1024, status.VCGTEntries)
	assert.Equal(t, "D65", status.WhitePointName)
	assert.Equal(t, int64(4), status.Size)
	assert.NotZero(t, status.Modified)
}

// The exported getters serve the published snapshot, so callers on other
// goroutines (IPC handlers, the scheduler) never read the per-output fields the
// actor mutates. A profile therefore appears in the status only once the actor
// has published it, and an empty snapshot has to clear the previous one.
func TestManager_ICCStatusServesPublishedSnapshot(t *testing.T) {
	m := &Manager{}
	out := &outputState{id: 1, iccPath: "/tmp/display.icm", outputTemp: 7000}
	m.outputs.Store(1, out)
	m.outputNames.Store(1, "DP-1")

	assert.Empty(t, m.GetICCStatus(), "nothing is published before the first publish")
	assert.Empty(t, m.GetOutputTemps())

	m.publishICCState()
	assert.Contains(t, m.GetICCStatus(), "DP-1")
	assert.Equal(t, 7000, m.GetOutputTemps()["DP-1"])

	// A mutation the actor has not published yet is invisible to callers.
	out.outputTemp = 5000
	out.iccPath = ""
	assert.Equal(t, 7000, m.GetOutputTemps()["DP-1"])

	m.publishICCState()
	assert.Equal(t, 5000, m.GetOutputTemps()["DP-1"])
	assert.Empty(t, m.GetICCStatus(), "the removed profile is gone from the snapshot")
}

// Outputs that go away (unplugged, monitor sleep) must not stay in the name
// maps: they are what `dms icc listOutputs` and `status` enumerate, and a
// rebound wl_output reusing the object ID would attach the previous monitor's
// profile from the stale name.
func TestManager_RemoveOutputByRegistryNamePrunesNames(t *testing.T) {
	m := &Manager{}
	out := &outputState{id: 7, registryName: 42, iccPath: "/tmp/display.icm", outputTemp: 6500}
	m.outputs.Store(7, out)
	m.outputNames.Store(7, "DP-1")
	m.outputRegNames.Store(7, 42)
	m.controlsInitialized = true
	m.publishICCState()

	m.removeOutputByRegistryName(42)

	_, stillStored := m.outputs.Load(7)
	assert.False(t, stillStored, "the output state should be gone")
	_, nameStored := m.outputNames.Load(7)
	assert.False(t, nameStored, "the output name should be gone")
	_, regNameStored := m.outputRegNames.Load(7)
	assert.False(t, regNameStored, "the registry name should be gone")
	assert.Empty(t, m.ListOutputs(), "a disconnected monitor must not be listed")
	assert.Empty(t, m.GetICCStatus(), "nor reported as a profiled output")
	assert.Empty(t, m.GetOutputTemps())
	assert.False(t, m.controlsInitialized, "the last output going away clears the controls")

	// A registry name that no output uses is a no-op.
	m.removeOutputByRegistryName(99)
}

// The getters are called from the scheduler and the IPC handlers while the
// actor publishes, so they must not share unsynchronised state with it (run
// with -race).
func TestManager_ICCStatusConcurrentPublishAndRead(t *testing.T) {
	m := &Manager{}
	out := &outputState{id: 1, iccPath: "/tmp/display.icm"}
	m.outputs.Store(1, out)
	m.outputNames.Store(1, "DP-1")

	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		for i := range 500 {
			out.outputTemp = 6000 + i
			out.iccProfile = nil
			m.publishICCState()
		}
	}()

	for range 500 {
		_ = m.GetICCStatus()
		_ = m.GetOutputTemps()
		_ = m.ListOutputs()
	}
	wg.Wait()
}

// The config is copied by value all over the manager, so a copy has to be a real
// snapshot: the maps must not alias the ones the manager writes under its lock,
// or a state push marshalled on another goroutine becomes a fatal
// "concurrent map iteration and map write".
func TestManager_ConfigSnapshotOwnsItsMaps(t *testing.T) {
	m := &Manager{config: DefaultConfig()}
	m.config.ICCProfiles = map[string]string{"DP-1": "/tmp/dp1.icc"}
	m.config.OutputTemps = map[string]int{"DP-1": 7000}

	snapshot := m.configSnapshot()

	m.configMutex.Lock()
	m.config.ICCProfiles["DP-2"] = "/tmp/dp2.icc"
	m.config.OutputTemps["DP-1"] = 4000
	m.config.OutputTemps["DP-2"] = 5000
	m.configMutex.Unlock()

	assert.Equal(t, map[string]string{"DP-1": "/tmp/dp1.icc"}, snapshot.ICCProfiles)
	assert.Equal(t, map[string]int{"DP-1": 7000}, snapshot.OutputTemps)
}

// Marshalling the copied config happens on the connection writer goroutine
// while the IPC goroutine stores a profile, so the copy has to be taken under
// the lock and own its maps (run with -race).
func TestManager_ConfigSnapshotConcurrentMarshal(t *testing.T) {
	m := &Manager{config: DefaultConfig()}
	m.config.ICCProfiles = make(map[string]string)
	m.config.OutputTemps = make(map[string]int)

	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		for i := range 500 {
			name := fmt.Sprintf("DP-%d", i)
			m.configMutex.Lock()
			m.config.ICCProfiles[name] = "/tmp/profile.icc"
			m.config.OutputTemps[name] = 6000 + i
			m.configMutex.Unlock()
		}
	}()

	for range 500 {
		if _, err := json.Marshal(m.configSnapshot()); err != nil {
			t.Fatalf("marshal config snapshot: %v", err)
		}
	}
	wg.Wait()
}

// On a default install (night light off, no profile) no gamma control exists,
// so a per-output temperature used to be persisted without ever being applied
// or reported: the settings slider snapped back to "Default" and the value only
// took effect after a daemon restart.
func TestManager_SetOutputTempWithoutControlsPublishesValue(t *testing.T) {
	t.Setenv("XDG_CONFIG_HOME", t.TempDir())

	m := &Manager{
		config:   DefaultConfig(),
		cmdq:     make(chan cmd, 8),
		stopChan: make(chan struct{}),
	}
	m.wg.Add(1)
	go m.waylandActor()
	defer func() {
		close(m.stopChan)
		m.wg.Wait()
	}()

	if err := m.SetOutputTemp("DP-1", 7000); err != nil {
		t.Fatalf("SetOutputTemp() = %v", err)
	}

	// Wait for the posted body, so the assertions below are ordered after it.
	done := make(chan struct{})
	m.post(func() { close(done) })
	<-done

	assert.Equal(t, 7000, m.GetOutputTemps()["DP-1"], "the value is reported even without gamma controls")

	path := iccConfigPath()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	var saved iccConfig
	if err := json.Unmarshal(data, &saved); err != nil {
		t.Fatalf("unmarshal %s: %v", path, err)
	}
	assert.Equal(t, 7000, saved.OutputTemps["DP-1"], "and persisted to the config file")
}

// Arguments that no wl_output or file can satisfy are rejected before anything is
// written: an empty name would persist an entry in icc.json that nothing can
// match, and a relative profile path cannot be resolved by the daemon, which
// does not have the caller's working directory.
func TestManager_RejectsInvalidICCArguments(t *testing.T) {
	m := &Manager{config: DefaultConfig()}

	t.Run("empty output name", func(t *testing.T) {
		assert.Error(t, m.ApplyICC("", "/tmp/profile.icc"))
		assert.Error(t, m.RemoveICC(""))
		assert.Error(t, m.SetOutputTemp("", 7000))
		assert.Empty(t, m.config.ICCProfiles, "nothing may be stored for a name that cannot exist")
		assert.Empty(t, m.config.OutputTemps)
	})

	t.Run("output name with whitespace", func(t *testing.T) {
		assert.Error(t, m.SetOutputTemp(" DP-1", 7000))
		assert.Empty(t, m.config.OutputTemps)
	})

	t.Run("relative profile path", func(t *testing.T) {
		assert.Error(t, m.ApplyICC("DP-1", "profile.icc"))
		assert.Error(t, m.ApplyICC("DP-1", ""))
		assert.Empty(t, m.config.ICCProfiles)
	})
}

// A gamma control that the compositor dropped on an output with an ICC profile
// (or a per-output temperature) has to be recreated even while the night light
// is off, because the controls exist for the profile in that case. Gating on
// config.Enabled left out.failed set for the life of the daemon, and applyGamma
// skips those outputs.
func TestManager_RecreateOutputControlFollowsNeedsControls(t *testing.T) {
	output := &wlclient.Output{}
	out := &outputState{id: 1, registryName: 10, output: output, rampSize: 256, failed: true}

	m := &Manager{config: DefaultConfig()}
	m.outputs.Store(out.id, out)
	m.availOutputsMu.Lock()
	m.availableOutputs = []*wlclient.Output{output}
	m.availOutputsMu.Unlock()
	m.controlsInitialized = true

	// Night light off and nothing configured: there is nothing to recreate.
	assert.NoError(t, m.recreateOutputControl(out))

	// Still no night light, but the output has a profile: the control has to be
	// recreated (the missing gamma manager is what stops it in this test).
	m.config.ICCProfiles = map[string]string{"DP-1": "/tmp/dp1.icc"}
	assert.Error(t, m.recreateOutputControl(out), "a profiled output needs its control back with the night light off")

	// A per-output temperature counts as well.
	m.config.ICCProfiles = nil
	m.config.OutputTemps = map[string]int{"DP-1": 7000}
	assert.Error(t, m.recreateOutputControl(out), "so does an output with a temperature override")
}

// Clearing an override is what the reset button in Display Config does: it has to
// drop the stored value and the published entry, so the row goes back to
// "Default" and the output follows the schedule again.
func TestManager_SetOutputTempZeroClearsTheOverride(t *testing.T) {
	t.Setenv("XDG_CONFIG_HOME", t.TempDir())

	m := &Manager{
		config:   DefaultConfig(),
		cmdq:     make(chan cmd, 8),
		stopChan: make(chan struct{}),
	}
	m.wg.Add(1)
	go m.waylandActor()
	defer func() {
		close(m.stopChan)
		m.wg.Wait()
	}()

	if err := m.SetOutputTemp("DP-1", 7000); err != nil {
		t.Fatalf("SetOutputTemp(7000) = %v", err)
	}
	if err := m.SetOutputTemp("DP-1", 0); err != nil {
		t.Fatalf("SetOutputTemp(0) = %v", err)
	}

	done := make(chan struct{})
	m.post(func() { close(done) })
	<-done

	assert.NotContains(t, m.GetOutputTemps(), "DP-1", "the published override has to disappear")
	assert.NotContains(t, m.config.OutputTemps, "DP-1", "and so has the stored one")
}

func startTestActor(t *testing.T, m *Manager) func() {
	t.Helper()
	m.cmdq = make(chan cmd, 8)
	m.stopChan = make(chan struct{})
	m.wg.Add(1)
	go m.waylandActor()
	t.Cleanup(func() {
		close(m.stopChan)
		m.wg.Wait()
	})
	return func() {
		done := make(chan struct{})
		m.post(func() { close(done) })
		<-done
	}
}

func TestManager_ClearingLastOverrideReleasesControls(t *testing.T) {
	t.Setenv("XDG_CONFIG_HOME", t.TempDir())

	cfg := DefaultConfig()
	cfg.OutputTemps = map[string]int{"DP-1": 7000}
	m := &Manager{config: cfg, controlsInitialized: true}
	m.outputs.Store(1, &outputState{id: 1, outputTemp: 7000})
	m.outputNames.Store(1, "DP-1")
	drain := startTestActor(t, m)

	if err := m.SetOutputTemp("DP-1", 0); err != nil {
		t.Fatalf("SetOutputTemp() = %v", err)
	}
	drain()

	assert.False(t, m.controlsInitialized, "nothing needs the controls once the last override is gone")
	_, kept := m.outputs.Load(1)
	assert.False(t, kept, "the output state goes with the controls")
	assert.Empty(t, m.GetOutputTemps())
}

func TestManager_ClearingOverrideWithoutControlsCreatesNone(t *testing.T) {
	t.Setenv("XDG_CONFIG_HOME", t.TempDir())

	m := &Manager{config: DefaultConfig()}
	drain := startTestActor(t, m)

	if err := m.SetOutputTemp("DP-1", 0); err != nil {
		t.Fatalf("SetOutputTemp() = %v", err)
	}
	drain()

	assert.False(t, m.controlsInitialized, "clearing a value nothing holds must not create controls")
}

func TestManager_RemovingLastProfileReleasesControls(t *testing.T) {
	t.Setenv("XDG_CONFIG_HOME", t.TempDir())

	cfg := DefaultConfig()
	cfg.ICCProfiles = map[string]string{"DP-1": "/tmp/display.icc"}
	m := &Manager{config: cfg, controlsInitialized: true}
	m.outputs.Store(1, &outputState{id: 1, iccPath: "/tmp/display.icc"})
	m.outputNames.Store(1, "DP-1")
	drain := startTestActor(t, m)

	if err := m.RemoveICC("DP-1"); err != nil {
		t.Fatalf("RemoveICC() = %v", err)
	}
	drain()

	assert.False(t, m.controlsInitialized, "nothing needs the controls once the last profile is gone")
	assert.Empty(t, m.GetICCStatus())
}

func TestManager_RemovingProfileKeepsControlsForNightLight(t *testing.T) {
	t.Setenv("XDG_CONFIG_HOME", t.TempDir())

	cfg := DefaultConfig()
	cfg.Enabled = true
	cfg.ICCProfiles = map[string]string{"DP-1": "/tmp/display.icc"}
	m := &Manager{config: cfg, controlsInitialized: true}
	m.outputs.Store(1, &outputState{id: 1, iccPath: "/tmp/display.icc"})
	m.outputNames.Store(1, "DP-1")
	drain := startTestActor(t, m)

	if err := m.RemoveICC("DP-1"); err != nil {
		t.Fatalf("RemoveICC() = %v", err)
	}
	drain()

	assert.True(t, m.controlsInitialized, "the night light still needs the controls")
	_, kept := m.outputs.Load(1)
	assert.True(t, kept)
}

func TestManager_StateCarriesSortedOutputs(t *testing.T) {
	m := &Manager{config: DefaultConfig()}
	m.outputNames.Store(2, "HDMI-A-1")
	m.outputNames.Store(1, "DP-1")

	m.updateStateFromSchedule()

	assert.Equal(t, []string{"DP-1", "HDMI-A-1"}, m.GetState().Outputs)
}

func TestRampCurrentUsesEffectiveTarget(t *testing.T) {
	overridden := &outputState{outputTemp: 7000, lastTemp: 7000, lastGamma: 1.0, lastContrast: 1.0}
	for _, scheduleTemp := range []int{noTempTarget, 4000, 4025, 6500} {
		assert.True(t, overridden.rampCurrent(effectiveTempTarget(overridden, scheduleTemp), 1.0, 1.0),
			"an overridden output must not be resent when the schedule moves to %d", scheduleTemp)
	}

	scheduled := &outputState{lastTemp: 4000, lastGamma: 1.0, lastContrast: 1.0}
	assert.True(t, scheduled.rampCurrent(effectiveTempTarget(scheduled, 4000), 1.0, 1.0))
	assert.False(t, scheduled.rampCurrent(effectiveTempTarget(scheduled, 4025), 1.0, 1.0))

	forced := &outputState{outputTemp: 7000, lastTemp: 0, lastGamma: 1.0, lastContrast: 1.0}
	assert.False(t, forced.rampCurrent(effectiveTempTarget(forced, 7000), 1.0, 1.0), "lastTemp 0 always resends")
}

func TestManager_SameOverrideValueDoesNotForceResend(t *testing.T) {
	t.Setenv("XDG_CONFIG_HOME", t.TempDir())

	cfg := DefaultConfig()
	cfg.OutputTemps = map[string]int{"DP-1": 7000}
	m := &Manager{config: cfg, controlsInitialized: true}
	out := &outputState{id: 1, outputTemp: 7000, lastTemp: 7000, lastGamma: 1.0, lastContrast: 1.0}
	m.outputs.Store(1, out)
	m.outputNames.Store(1, "DP-1")
	drain := startTestActor(t, m)

	if err := m.SetOutputTemp("DP-1", 7000); err != nil {
		t.Fatalf("SetOutputTemp() = %v", err)
	}
	drain()

	assert.Equal(t, 7000, out.lastTemp, "an unchanged override must not clear the dedupe state")
}

func TestManager_RemovingAbsentProfileDoesNotForceResend(t *testing.T) {
	t.Setenv("XDG_CONFIG_HOME", t.TempDir())

	cfg := DefaultConfig()
	cfg.Enabled = true
	m := &Manager{config: cfg, controlsInitialized: true}
	out := &outputState{id: 1, lastTemp: 4000, lastGamma: 1.0, lastContrast: 1.0}
	m.outputs.Store(1, out)
	m.outputNames.Store(1, "DP-1")
	drain := startTestActor(t, m)

	if err := m.RemoveICC("DP-1"); err != nil {
		t.Fatalf("RemoveICC() = %v", err)
	}
	drain()

	assert.Equal(t, 4000, out.lastTemp, "removing a profile that was never attached must not clear the dedupe state")
}

func TestManager_SetOutputBrightnessClampsAndPersists(t *testing.T) {
	t.Setenv("XDG_CONFIG_HOME", t.TempDir())

	m := &Manager{
		config:   DefaultConfig(),
		cmdq:     make(chan cmd, 8),
		stopChan: make(chan struct{}),
	}
	m.wg.Add(1)
	go m.waylandActor()
	defer func() {
		close(m.stopChan)
		m.wg.Wait()
	}()

	tests := []struct {
		percent int
		want    map[string]int
	}{
		{0, map[string]int{"eDP-1": 0}},
		{40, map[string]int{"eDP-1": 40}},
		{150, nil},
	}
	for _, tt := range tests {
		assert.NoError(t, m.SetOutputBrightness("eDP-1", tt.percent))
		assert.True(t, maps.Equal(tt.want, m.GetOutputBrightness()), "percent %d", tt.percent)
		assert.True(t, maps.Equal(tt.want, LoadConfig().OutputBrightness), "percent %d persisted", tt.percent)
	}
	assert.False(t, m.needsControls(), "full brightness must release the gamma controls")
}

// A control that fails before gamma_size was refused by the compositor, so
// software brightness cannot use the output; a failure after it worked is a
// lost control that the retry path recovers.
func TestOutputState_MarkFailedDetectsRefusal(t *testing.T) {
	tests := []struct {
		name     string
		rampSize uint32
		refused  bool
	}{
		{"failed before gamma_size", 0, true},
		{"failed after gamma_size", 256, false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			out := &outputState{rampSize: tt.rampSize, retryCount: 1}
			out.markFailed(time.Now())
			assert.Equal(t, tt.refused, out.gammaRefused)
			assert.True(t, out.failed)
			assert.Zero(t, out.rampSize)
			assert.Equal(t, 2, out.retryCount)
		})
	}
}
