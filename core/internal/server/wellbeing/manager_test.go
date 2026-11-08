package wellbeing

import (
	"path/filepath"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

type clock struct{ now time.Time }

func (c *clock) advance(d time.Duration) { c.now = c.now.Add(d) }

func newTestManager(t *testing.T, start time.Time) (*Manager, *clock) {
	t.Helper()
	c := &clock{now: start}
	m, err := newManager(filepath.Join(t.TempDir(), "db"), func() time.Time { return c.now })
	require.NoError(t, err)
	t.Cleanup(m.Close)
	return m, c
}

func drain(ch chan State) []State {
	var out []State
	for {
		select {
		case s := <-ch:
			out = append(out, s)
		default:
			return out
		}
	}
}

func TestFocusTimeSplitsAtMidnightPerApp(t *testing.T) {
	start := time.Date(2026, 10, 1, 23, 59, 30, 0, time.UTC)
	m, c := newTestManager(t, start)

	m.SetState("firefox", true, 1)
	c.advance(50 * time.Second)
	m.SetState("kitty", true, 2)
	c.advance(10 * time.Second)
	m.SetState("", false, 3)

	days := m.Summary(2)
	assert.Equal(t, "2026-10-01", days[0].Date)
	assert.Equal(t, int64(30), days[0].Active)
	assert.Equal(t, map[string]int64{"firefox": 30}, days[0].Apps)
	assert.Equal(t, "2026-10-02", days[1].Date)
	assert.Equal(t, int64(30), days[1].Active)
	assert.Equal(t, map[string]int64{"firefox": 20, "kitty": 10}, days[1].Apps)
}

func TestInactiveAndFrozenGapsCountNothing(t *testing.T) {
	start := time.Date(2026, 10, 1, 12, 0, 0, 0, time.UTC)
	m, c := newTestManager(t, start)

	m.SetState("firefox", false, 1)
	c.advance(40 * time.Second)
	m.SetState("firefox", true, 2)
	c.advance(maxCreditGap + time.Second)
	m.Flush()
	c.advance(20 * time.Second)
	m.SetState("", false, 3)

	today := m.Summary(1)[0]
	assert.Equal(t, int64(20), today.Active)
	assert.Equal(t, map[string]int64{"firefox": 20}, today.Apps)
}

func TestStaleSequenceIsIgnored(t *testing.T) {
	m, c := newTestManager(t, time.Date(2026, 10, 1, 12, 0, 0, 0, time.UTC))

	m.SetState("kitty", true, 10)
	m.SetState("firefox", true, 9)
	c.advance(15 * time.Second)
	m.SetState("", false, 11)

	assert.Equal(t, map[string]int64{"kitty": 15}, m.Summary(1)[0].Apps)
}

func TestOpenSegmentShowsInSummaryWithoutBeingStored(t *testing.T) {
	m, c := newTestManager(t, time.Date(2026, 10, 1, 12, 0, 0, 0, time.UTC))

	m.SetState("firefox", true, 1)
	c.advance(25 * time.Second)

	assert.Equal(t, int64(25), m.Summary(1)[0].Apps["firefox"])
	assert.Equal(t, int64(25), m.GetState().Today.Active)
	assert.Equal(t, int64(25), m.Summary(1)[0].Apps["firefox"], "a read must not credit twice")
}

func TestLimitsAlertOncePerDayAndAgainAfterRaise(t *testing.T) {
	m, c := newTestManager(t, time.Date(2026, 10, 1, 12, 0, 0, 0, time.UTC))
	ch := m.Subscribe("test")
	m.SetLimits(Limits{Daily: 60, Apps: map[string]int64{"firefox": 30}})

	m.SetState("firefox", true, 1)
	c.advance(30 * time.Second)
	m.Flush()
	c.advance(30 * time.Second)
	m.Flush()
	c.advance(30 * time.Second)
	m.Flush()

	var kinds []string
	for _, s := range drain(ch) {
		if s.Limit != nil {
			kinds = append(kinds, s.Limit.Kind+":"+s.Limit.AppID)
		}
	}
	assert.Equal(t, []string{"app:firefox", "daily:"}, kinds)

	m.SetLimits(Limits{Daily: 60, Apps: map[string]int64{"firefox": 80}})
	c.advance(30 * time.Second)
	m.Flush()
	limits := 0
	for _, s := range drain(ch) {
		if s.Limit != nil {
			limits++
			assert.Equal(t, int64(120), s.Limit.Used)
		}
	}
	assert.Equal(t, 1, limits, "a raised app limit alerts again, the unchanged daily limit does not")

	c.advance(12 * time.Hour)
	m.Flush()
	c.advance(30 * time.Second)
	m.Flush()
	for _, s := range drain(ch) {
		assert.Nil(t, s.Limit, "nothing crosses on a frozen gap or a fresh day under the limits")
	}
	assert.Equal(t, int64(30), m.Summary(1)[0].Active)
}

func TestLastUnsubscribeEndsTheOpenSegment(t *testing.T) {
	m, c := newTestManager(t, time.Date(2026, 10, 1, 12, 0, 0, 0, time.UTC))
	m.Subscribe("shell")
	m.SetState("firefox", true, 1)
	c.advance(10 * time.Second)
	m.Unsubscribe("shell")
	c.advance(50 * time.Second)

	assert.Equal(t, int64(10), m.Summary(1)[0].Active)
	assert.True(t, m.Snapshot().Resync)
}

func TestClearDropsHistoryAndRearmsAlerts(t *testing.T) {
	m, c := newTestManager(t, time.Date(2026, 10, 1, 12, 0, 0, 0, time.UTC))
	ch := m.Subscribe("test")
	m.SetLimits(Limits{Daily: 10})
	m.SetState("firefox", true, 1)
	c.advance(10 * time.Second)
	m.Flush()
	require.NotNil(t, drain(ch)[0].Limit)

	m.Clear()
	assert.Equal(t, int64(0), m.Summary(1)[0].Active)
	c.advance(10 * time.Second)
	m.Flush()
	alerts := 0
	for _, s := range drain(ch) {
		if s.Limit != nil {
			alerts++
		}
	}
	assert.Equal(t, 1, alerts)
}

func TestAlertRecordSurvivesRestart(t *testing.T) {
	path := filepath.Join(t.TempDir(), "db")
	c := &clock{now: time.Date(2026, 10, 1, 12, 0, 0, 0, time.UTC)}
	now := func() time.Time { return c.now }

	m, err := newManager(path, now)
	require.NoError(t, err)
	m.SetLimits(Limits{Daily: 10})
	m.SetState("firefox", true, 1)
	c.advance(10 * time.Second)
	m.Close()

	m, err = newManager(path, now)
	require.NoError(t, err)
	defer m.Close()
	ch := m.Subscribe("test")
	m.SetLimits(Limits{Daily: 10})
	m.SetState("firefox", true, 2)
	c.advance(10 * time.Second)
	m.Flush()
	assert.Equal(t, int64(20), m.Summary(1)[0].Active)
	for _, s := range drain(ch) {
		assert.Nil(t, s.Limit, "the alert already fired before the restart")
	}
}

func TestOpenDBLockedByAnotherProcessKeepsData(t *testing.T) {
	path := filepath.Join(t.TempDir(), "db")
	c := &clock{now: time.Date(2026, 10, 1, 12, 0, 0, 0, time.UTC)}
	now := func() time.Time { return c.now }

	m, err := newManager(path, now)
	require.NoError(t, err)
	m.SetState("firefox", true, 1)
	c.advance(10 * time.Second)
	m.Flush()

	_, err = newManager(path, now)
	require.Error(t, err)
	m.Close()

	m, err = newManager(path, now)
	require.NoError(t, err)
	defer m.Close()
	assert.Equal(t, int64(10), m.Summary(1)[0].Active)
}
