package wellbeing

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"runtime/debug"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/duxlabs-dev/dux-shell/core/internal/utils"
	bolt "go.etcd.io/bbolt"
	berrors "go.etcd.io/bbolt/errors"
)

var (
	bucketDays = []byte("days")
	bucketMeta = []byte("meta")
	keyAlerted = []byte("alerted")
)

func DBPath() string {
	return filepath.Join(utils.XDGStateHome(), "dms", "wellbeing", "db")
}

func openDB(path string) (*bolt.DB, error) {
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return nil, err
	}
	db, err := tryOpenDB(path)
	if err == nil {
		return db, nil
	}
	if errors.Is(err, berrors.ErrTimeout) {
		return nil, err
	}
	log.Errorf("Wellbeing db unreadable, starting over: %v", err)
	corruptPath := path + ".corrupt"
	os.Remove(corruptPath)
	if renameErr := os.Rename(path, corruptPath); renameErr != nil {
		return nil, err
	}
	return tryOpenDB(path)
}

// bbolt reports corrupted pages by panicking (internal/common/verify.go), not
// by returning errors, so every db touchpoint recovers and converts to error.
func recoverDBPanic(err *error) {
	r := recover()
	if r == nil {
		return
	}
	*err = fmt.Errorf("wellbeing db panic: %v", r)
}

// a pgid past the mmap end faults instead of panicking; only recoverable while armed
func armDBFaultPanics() func() {
	prev := debug.SetPanicOnFault(true)
	return func() { debug.SetPanicOnFault(prev) }
}

func tryOpenDB(path string) (db *bolt.DB, err error) {
	defer func() {
		r := recover()
		if r == nil {
			return
		}
		if db != nil {
			db.Close()
		}
		db, err = nil, fmt.Errorf("wellbeing db panic: %v", r)
	}()
	defer armDBFaultPanics()()

	db, err = bolt.Open(path, 0o600, &bolt.Options{Timeout: time.Second})
	if err != nil {
		return nil, err
	}
	err = db.Update(func(tx *bolt.Tx) error {
		if _, err := tx.CreateBucketIfNotExists(bucketDays); err != nil {
			return err
		}
		_, err := tx.CreateBucketIfNotExists(bucketMeta)
		return err
	})
	if err == nil {
		err = db.View(func(tx *bolt.Tx) error {
			return tx.Bucket(bucketDays).ForEach(func(k, v []byte) error { return nil })
		})
	}
	if err != nil {
		db.Close()
		return nil, err
	}
	return db, nil
}

func (m *Manager) dbUpdate(fn func(tx *bolt.Tx) error) (err error) {
	defer recoverDBPanic(&err)
	defer armDBFaultPanics()()
	return m.db.Update(fn)
}

func (m *Manager) dbView(fn func(tx *bolt.Tx) error) (err error) {
	defer recoverDBPanic(&err)
	defer armDBFaultPanics()()
	return m.db.View(fn)
}

func readDay(b *bolt.Bucket, date string) DayUsage {
	day := DayUsage{Date: date, Apps: map[string]int64{}}
	raw := b.Get([]byte(date))
	if raw == nil {
		return day
	}
	if err := json.Unmarshal(raw, &day); err != nil || day.Apps == nil {
		day.Apps = map[string]int64{}
	}
	day.Date = date
	return day
}

func writeDay(b *bolt.Bucket, day DayUsage) error {
	raw, err := json.Marshal(day)
	if err != nil {
		return err
	}
	return b.Put([]byte(day.Date), raw)
}

func readMeta(b *bolt.Bucket, key []byte, out any) bool {
	raw := b.Get(key)
	if raw == nil {
		return false
	}
	return json.Unmarshal(raw, out) == nil
}

func writeMeta(b *bolt.Bucket, key []byte, value any) error {
	raw, err := json.Marshal(value)
	if err != nil {
		return err
	}
	return b.Put(key, raw)
}

func pruneDays(b *bolt.Bucket, oldest string) error {
	c := b.Cursor()
	var stale [][]byte
	for k, _ := c.First(); k != nil && string(k) < oldest; k, _ = c.Next() {
		stale = append(stale, append([]byte(nil), k...))
	}
	for _, k := range stale {
		if err := b.Delete(k); err != nil {
			return err
		}
	}
	return nil
}
