package wellbeing

import (
	"maps"
	"slices"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	bolt "go.etcd.io/bbolt"
)

func NewManager() (*Manager, error) {
	return newManager(DBPath(), time.Now)
}

func newManager(path string, now func() time.Time) (*Manager, error) {
	db, err := openDB(path)
	if err != nil {
		return nil, err
	}
	m := &Manager{
		db:       db,
		now:      now,
		wake:     make(chan struct{}, 1),
		stopChan: make(chan struct{}),
		limits:   Limits{Apps: map[string]int64{}},
	}
	m.cur = segment{Since: now().Unix()}
	err = m.dbView(func(tx *bolt.Tx) error {
		readMeta(tx.Bucket(bucketMeta), keyAlerted, &m.alerted)
		return nil
	})
	if err != nil {
		db.Close()
		return nil, err
	}
	m.wg.Go(m.run)
	return m, nil
}

func (m *Manager) Close() {
	close(m.stopChan)
	m.wg.Wait()
	m.subscribers.Range(func(key string, ch chan State) bool {
		close(ch)
		m.subscribers.Delete(key)
		return true
	})
	m.db.Close()
}

func (m *Manager) Subscribe(id string) chan State {
	ch := make(chan State, 64)
	m.subscribers.Store(id, ch)
	return ch
}

// The shell is the only source of focus and idle state, so when its last
// subscription drops the open segment ends instead of counting forever.
func (m *Manager) Unsubscribe(id string) {
	ch, ok := m.subscribers.LoadAndDelete(id)
	if !ok {
		return
	}
	close(ch)
	if m.subscriberCount() > 0 {
		return
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	m.setSegmentLocked("", false)
}

func (m *Manager) subscriberCount() int {
	count := 0
	m.subscribers.Range(func(string, chan State) bool {
		count++
		return true
	})
	return count
}

// Snapshot opens every subscription; Resync asks the shell to push its state again.
func (m *Manager) Snapshot() State {
	state := m.GetState()
	state.Resync = true
	return state
}

func (m *Manager) GetState() State {
	m.mu.Lock()
	defer m.mu.Unlock()
	return State{Today: m.summaryLocked(1)[0]}
}

func (m *Manager) Summary(days int) []DayUsage {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.summaryLocked(days)
}

func (m *Manager) SetState(appID string, active bool, seq int64) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if seq != 0 && seq <= m.seq {
		return
	}
	if seq != 0 {
		m.seq = seq
	}
	m.setSegmentLocked(appID, active)
}

func (m *Manager) setSegmentLocked(appID string, active bool) {
	if m.cur.AppID == appID && m.cur.Active == active {
		return
	}
	now := m.now()
	m.creditLocked(now)
	m.cur = segment{AppID: appID, Active: active, Since: now.Unix()}
	select {
	case m.wake <- struct{}{}:
	default:
	}
}

func (m *Manager) SetLimits(limits Limits) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if limits.Apps == nil {
		limits.Apps = map[string]int64{}
	}
	previous, hadLimits := m.limits, m.limitsSet
	m.limits, m.limitsSet = limits, true
	if !hadLimits {
		return
	}
	var keep []string
	for _, key := range m.alerted.Keys {
		if limitFor(key, previous) == limitFor(key, limits) {
			keep = append(keep, key)
		}
	}
	if len(keep) == len(m.alerted.Keys) {
		return
	}
	m.alerted.Keys = keep
	m.writeAlertedLocked()
}

func limitFor(key string, limits Limits) int64 {
	if key == "daily" {
		return limits.Daily
	}
	return limits.Apps[key[len("app:"):]]
}

func (m *Manager) Clear() {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.cur.Since = m.now().Unix()
	m.alerted = alertRecord{}
	err := m.dbUpdate(func(tx *bolt.Tx) error {
		if err := tx.DeleteBucket(bucketDays); err != nil {
			return err
		}
		if _, err := tx.CreateBucket(bucketDays); err != nil {
			return err
		}
		return tx.Bucket(bucketMeta).Delete(keyAlerted)
	})
	if err != nil {
		log.Warnf("Wellbeing: clear failed: %v", err)
	}
	m.publish(State{Today: m.summaryLocked(1)[0]})
}

func (m *Manager) Flush() {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.creditLocked(m.now())
}

func (m *Manager) run() {
	timer := time.NewTimer(flushInterval)
	timer.Stop()
	running := false
	for {
		m.mu.Lock()
		active := m.cur.Active
		m.mu.Unlock()
		switch {
		case active && !running:
			timer.Reset(flushInterval)
			running = true
		case !active && running:
			timer.Stop()
			running = false
		}
		select {
		case <-m.stopChan:
			timer.Stop()
			m.Flush()
			return
		case <-m.wake:
		case <-timer.C:
			running = false
			m.Flush()
		}
	}
}

// splitCredit hands out the segment's seconds per local calendar day.
func splitCredit(seg segment, now time.Time, fn func(date string, seconds int64)) {
	if !seg.Active {
		return
	}
	gap := now.Unix() - seg.Since
	if gap <= 0 || gap > int64(maxCreditGap/time.Second) {
		return
	}
	cursor := time.Unix(seg.Since, 0).In(now.Location())
	for {
		dayEnd := time.Date(cursor.Year(), cursor.Month(), cursor.Day()+1, 0, 0, 0, 0, cursor.Location())
		if !dayEnd.Before(now) {
			fn(cursor.Format(dateLayout), now.Unix()-cursor.Unix())
			return
		}
		fn(cursor.Format(dateLayout), dayEnd.Unix()-cursor.Unix())
		cursor = dayEnd
	}
}

func (m *Manager) creditLocked(now time.Time) {
	seg := m.cur
	m.cur.Since = now.Unix()
	var today DayUsage
	err := m.dbUpdate(func(tx *bolt.Tx) error {
		days := tx.Bucket(bucketDays)
		var err error
		splitCredit(seg, now, func(date string, seconds int64) {
			if err != nil {
				return
			}
			day := readDay(days, date)
			day.Active += seconds
			if seg.AppID != "" {
				day.Apps[seg.AppID] += seconds
			}
			err = writeDay(days, day)
			today = day
		})
		if err != nil || today.Date == "" {
			return err
		}
		return pruneDays(days, now.AddDate(0, 0, -retentionDays).Format(dateLayout))
	})
	if err != nil {
		log.Warnf("Wellbeing: credit failed: %v", err)
		return
	}
	if today.Date == "" {
		return
	}
	events := m.crossedLimitsLocked(today)
	if len(events) == 0 {
		m.publish(State{Today: today})
		return
	}
	for i := range events {
		m.publish(State{Today: today, Limit: &events[i]})
	}
}

func (m *Manager) crossedLimitsLocked(today DayUsage) []LimitEvent {
	if m.alerted.Date != today.Date {
		m.alerted = alertRecord{Date: today.Date}
	}
	var events []LimitEvent
	if m.limits.Daily > 0 && today.Active >= m.limits.Daily && !slices.Contains(m.alerted.Keys, "daily") {
		m.alerted.Keys = append(m.alerted.Keys, "daily")
		events = append(events, LimitEvent{Kind: "daily", Used: today.Active, Limit: m.limits.Daily})
	}
	for _, appID := range slices.Sorted(maps.Keys(m.limits.Apps)) {
		limit := m.limits.Apps[appID]
		used := today.Apps[appID]
		key := "app:" + appID
		if limit <= 0 || used < limit || slices.Contains(m.alerted.Keys, key) {
			continue
		}
		m.alerted.Keys = append(m.alerted.Keys, key)
		events = append(events, LimitEvent{Kind: "app", AppID: appID, Used: used, Limit: limit})
	}
	if len(events) > 0 {
		m.writeAlertedLocked()
	}
	return events
}

func (m *Manager) writeAlertedLocked() {
	err := m.dbUpdate(func(tx *bolt.Tx) error {
		return writeMeta(tx.Bucket(bucketMeta), keyAlerted, m.alerted)
	})
	if err != nil {
		log.Warnf("Wellbeing: alert record write failed: %v", err)
	}
}

func (m *Manager) summaryLocked(days int) []DayUsage {
	now := m.now()
	days = max(1, days)
	result := make([]DayUsage, days)
	index := map[string]int{}
	for i := range days {
		date := now.AddDate(0, 0, i-days+1).Format(dateLayout)
		result[i] = DayUsage{Date: date, Apps: map[string]int64{}}
		index[date] = i
	}
	err := m.dbView(func(tx *bolt.Tx) error {
		bucket := tx.Bucket(bucketDays)
		for date, i := range index {
			result[i] = readDay(bucket, date)
		}
		return nil
	})
	if err != nil {
		log.Warnf("Wellbeing: summary read failed: %v", err)
	}
	splitCredit(m.cur, now, func(date string, seconds int64) {
		i, ok := index[date]
		if !ok {
			return
		}
		result[i].Active += seconds
		if m.cur.AppID != "" {
			result[i].Apps[m.cur.AppID] += seconds
		}
	})
	return result
}

func (m *Manager) publish(state State) {
	m.subscribers.Range(func(key string, ch chan State) bool {
		select {
		case ch <- state:
		default:
			log.Warn("Wellbeing: subscriber channel full, dropping update")
		}
		return true
	})
}
