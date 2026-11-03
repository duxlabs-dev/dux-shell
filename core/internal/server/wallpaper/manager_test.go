package wallpaper

import (
	"testing"
	"time"
)

func TestParseHHMM(t *testing.T) {
	cases := []struct {
		in     string
		hour   int
		minute int
		ok     bool
	}{
		{"06:00", 6, 0, true},
		{"24:00", 0, 0, false},
		{"6:5", 6, 5, true},
		{"12", 0, 0, false},
		{"12:60", 0, 0, false},
	}
	for _, c := range cases {
		hour, minute, ok := parseHHMM(c.in)
		if ok != c.ok || (ok && (hour != c.hour || minute != c.minute)) {
			t.Errorf("parseHHMM(%q) = (%d, %d, %v), want (%d, %d, %v)", c.in, hour, minute, ok, c.hour, c.minute, c.ok)
		}
	}
}

func TestComputeNextInterval(t *testing.T) {
	now := time.Date(2026, 6, 30, 12, 0, 0, 0, time.UTC)
	got := computeNext(now, ScheduleConfig{Mode: "interval", IntervalSec: 300})
	if want := now.Add(300 * time.Second); !got.Equal(want) {
		t.Errorf("interval next = %v, want %v", got, want)
	}

	clamped := computeNext(now, ScheduleConfig{Mode: "interval", IntervalSec: 0})
	if want := now.Add(time.Second); !clamped.Equal(want) {
		t.Errorf("interval clamp = %v, want %v", clamped, want)
	}
}

func TestComputeNextTime(t *testing.T) {
	now := time.Date(2026, 6, 30, 12, 0, 0, 0, time.UTC)

	later := computeNext(now, ScheduleConfig{Mode: "time", Time: "18:00"})
	if want := time.Date(2026, 6, 30, 18, 0, 0, 0, time.UTC); !later.Equal(want) {
		t.Errorf("time next (today) = %v, want %v", later, want)
	}

	tomorrow := computeNext(now, ScheduleConfig{Mode: "time", Time: "06:00"})
	if want := time.Date(2026, 7, 1, 6, 0, 0, 0, time.UTC); !tomorrow.Equal(want) {
		t.Errorf("time next (tomorrow) = %v, want %v", tomorrow, want)
	}
}

func TestActiveSchedules(t *testing.T) {
	global := activeSchedules(Config{
		Global: ScheduleConfig{Enabled: true, Mode: "interval", IntervalSec: 60},
	})
	if len(global) != 1 {
		t.Fatalf("global active = %d, want 1", len(global))
	}
	if _, ok := global[""]; !ok {
		t.Errorf("global active missing global key")
	}

	perMonitor := activeSchedules(Config{
		PerMonitor: true,
		Global:     ScheduleConfig{Enabled: true},
		Monitors: map[string]ScheduleConfig{
			"DP-1": {Enabled: true, Mode: "interval", IntervalSec: 60},
			"DP-2": {Enabled: false},
		},
	})
	if len(perMonitor) != 1 {
		t.Fatalf("per-monitor active = %d, want 1", len(perMonitor))
	}
	if _, ok := perMonitor["DP-1"]; !ok {
		t.Errorf("per-monitor active missing DP-1")
	}
}

func TestPrevDailyTime(t *testing.T) {
	now := time.Date(2026, 6, 30, 12, 0, 0, 0, time.UTC)

	earlier, ok := prevDailyTime(now, "06:00")
	if !ok || !earlier.Equal(time.Date(2026, 6, 30, 6, 0, 0, 0, time.UTC)) {
		t.Errorf("prev (today) = %v, %v", earlier, ok)
	}

	later, ok := prevDailyTime(now, "18:00")
	if !ok || !later.Equal(time.Date(2026, 6, 29, 18, 0, 0, 0, time.UTC)) {
		t.Errorf("prev (yesterday) = %v, %v", later, ok)
	}

	if _, ok := prevDailyTime(now, "bad"); ok {
		t.Error("prev (invalid) should not be ok")
	}
}

func TestTimeScheduleCatchUpAfterRestart(t *testing.T) {
	origDelay := catchUpDelay
	catchUpDelay = 100 * time.Millisecond
	defer func() { catchUpDelay = origDelay }()

	now := time.Now()
	hhmm := now.Add(-2 * time.Hour).Format("15:04")
	seed := map[string]time.Time{"": now.Add(-26 * time.Hour)}

	m := newManager(seed, func(map[string]time.Time) {})
	defer m.Close()

	sub := m.Subscribe("test")
	defer m.Unsubscribe("test")

	m.SetConfig(Config{Global: ScheduleConfig{Enabled: true, Mode: "time", Time: hhmm}})

	deadline := time.After(3 * time.Second)
	for {
		select {
		case state := <-sub:
			if state.CycleSeq > 0 && state.Target == "" {
				return
			}
		case <-deadline:
			t.Fatal("missed time schedule did not catch up within 3s")
		}
	}
}

func TestTimeScheduleNoFireOnFirstEnable(t *testing.T) {
	now := time.Now()
	hhmm := now.Add(-2 * time.Hour).Format("15:04")

	m := newManager(map[string]time.Time{}, func(map[string]time.Time) {})
	defer m.Close()

	sub := m.Subscribe("test")
	defer m.Unsubscribe("test")

	m.SetConfig(Config{Global: ScheduleConfig{Enabled: true, Mode: "time", Time: hhmm}})

	deadline := time.After(1500 * time.Millisecond)
	for {
		select {
		case state := <-sub:
			if state.CycleSeq > 0 {
				t.Fatal("first enable must not fire immediately")
			}
		case <-deadline:
			return
		}
	}
}

func TestSchedulerEmitsCycle(t *testing.T) {
	m := newManager(map[string]time.Time{}, func(map[string]time.Time) {})
	defer m.Close()

	sub := m.Subscribe("test")
	defer m.Unsubscribe("test")

	m.SetConfig(Config{Global: ScheduleConfig{Enabled: true, Mode: "interval", IntervalSec: 1}})

	deadline := time.After(3 * time.Second)
	for {
		select {
		case state := <-sub:
			if state.CycleSeq > 0 && state.Target == "" {
				return
			}
		case <-deadline:
			t.Fatal("scheduler did not emit a cycle event within 3s")
		}
	}
}
