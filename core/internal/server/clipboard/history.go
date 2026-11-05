package clipboard

import (
	"bytes"
	"cmp"
	"encoding/binary"
	"fmt"
	"math"
	"slices"
	"strings"
	"sync"
	"time"

	bolt "go.etcd.io/bbolt"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
)

var bucketName = []byte("clipboard")

const longTextThreshold = 200

type entryMeta struct {
	id      uint64
	hash    uint64
	ts      int64
	size    int32
	isImage bool
	pinned  bool
	mime    string
	altMime string
	preview string
}

func (e *entryMeta) entry() Entry {
	return Entry{
		ID:          e.id,
		MimeType:    e.mime,
		Preview:     e.preview,
		Size:        int(e.size),
		Timestamp:   time.Unix(0, e.ts),
		IsImage:     e.isImage,
		Hash:        e.hash,
		Pinned:      e.pinned,
		AltMimeType: e.altMime,
	}
}

func compareMetaOldestFirst(a, b entryMeta) int {
	if c := cmp.Compare(a.ts, b.ts); c != 0 {
		return c
	}
	return cmp.Compare(a.id, b.id)
}

// both slices are ordered oldest first
type historyIndex struct {
	mu       sync.RWMutex
	loaded   bool
	recent   []entryMeta
	pinned   []entryMeta
	revision uint64
	mimes    map[string]string
}

func (h *historyIndex) intern(s string) string {
	if s == "" {
		return ""
	}
	if v, ok := h.mimes[s]; ok {
		return v
	}
	if h.mimes == nil {
		h.mimes = make(map[string]string)
	}
	h.mimes[s] = s
	return s
}

func (h *historyIndex) meta(e Entry) entryMeta {
	return entryMeta{
		id:      e.ID,
		hash:    e.Hash,
		ts:      e.Timestamp.UnixNano(),
		size:    int32(e.Size),
		isImage: e.IsImage,
		pinned:  e.Pinned,
		mime:    h.intern(e.MimeType),
		altMime: h.intern(e.AltMimeType),
		preview: e.Preview,
	}
}

func (h *historyIndex) list(pinned bool) *[]entryMeta {
	if pinned {
		return &h.pinned
	}
	return &h.recent
}

func (h *historyIndex) insert(e entryMeta) {
	l := h.list(e.pinned)
	pos, _ := slices.BinarySearchFunc(*l, e, compareMetaOldestFirst)
	*l = slices.Insert(*l, pos, e)
}

func (h *historyIndex) remove(id uint64) {
	for _, l := range []*[]entryMeta{&h.recent, &h.pinned} {
		for i := len(*l) - 1; i >= 0; i-- {
			if (*l)[i].id != id {
				continue
			}
			*l = slices.Delete(*l, i, i+1)
			return
		}
	}
}

func (h *historyIndex) removeWhere(pred func(*entryMeta) bool) []uint64 {
	var ids []uint64
	for _, l := range []*[]entryMeta{&h.recent, &h.pinned} {
		*l = slices.DeleteFunc(*l, func(e entryMeta) bool {
			if !pred(&e) {
				return false
			}
			ids = append(ids, e.id)
			return true
		})
	}
	return ids
}

func (h *historyIndex) trimRecent(keep int) []uint64 {
	drop := len(h.recent) - max(keep, 0)
	if drop <= 0 {
		return nil
	}
	ids := make([]uint64, drop)
	for i := range drop {
		ids[i] = h.recent[i].id
	}
	clear(h.recent[:drop])
	h.recent = h.recent[drop:]
	return ids
}

func (h *historyIndex) hasPinnedHash(hash uint64) bool {
	return slices.ContainsFunc(h.pinned, func(e entryMeta) bool { return e.hash == hash })
}

func (h *historyIndex) newest() *entryMeta {
	var newest *entryMeta
	for _, l := range [][]entryMeta{h.recent, h.pinned} {
		if len(l) == 0 {
			continue
		}
		last := &l[len(l)-1]
		if newest == nil || compareMetaOldestFirst(*last, *newest) > 0 {
			newest = last
		}
	}
	return newest
}

func (h *historyIndex) eachNewest(pinned *bool, fn func(*entryMeta) bool) {
	var a, b []entryMeta
	switch {
	case pinned == nil:
		a, b = h.recent, h.pinned
	case *pinned:
		a = h.pinned
	default:
		a = h.recent
	}

	i, j := len(a)-1, len(b)-1
	for i >= 0 || j >= 0 {
		var e *entryMeta
		switch {
		case j < 0 || (i >= 0 && compareMetaOldestFirst(a[i], b[j]) > 0):
			e = &a[i]
			i--
		default:
			e = &b[j]
			j--
		}
		if !fn(e) {
			return
		}
	}
}

func (h *historyIndex) load(b *bolt.Bucket) error {
	h.recent, h.pinned = nil, nil
	err := b.ForEach(func(k, v []byte) error {
		e, err := decodeEntryMeta(v)
		if err != nil {
			return nil
		}
		meta := h.meta(e)
		l := h.list(meta.pinned)
		*l = append(*l, meta)
		return nil
	})
	h.sort()
	return err
}

func (h *historyIndex) sort() {
	slices.SortFunc(h.recent, compareMetaOldestFirst)
	slices.SortFunc(h.pinned, compareMetaOldestFirst)
}

type historyWriter struct {
	b     *bolt.Bucket
	h     *historyIndex
	dirty bool
}

func (w *historyWriter) get(id uint64) (Entry, error) {
	v := w.b.Get(itob(id))
	if v == nil {
		return Entry{}, errEntryNotFound
	}
	return decodeEntry(v)
}

func (w *historyWriter) put(e Entry) error {
	encoded, err := encodeEntry(e)
	if err != nil {
		return err
	}
	if err := w.b.Put(itob(e.ID), encoded); err != nil {
		return err
	}
	w.dirty = true
	w.h.remove(e.ID)
	w.h.insert(w.h.meta(e))
	return nil
}

// appendUnordered skips the sorted insert; call h.sort before relying on order
func (w *historyWriter) appendUnordered(e Entry) error {
	encoded, err := encodeEntry(e)
	if err != nil {
		return err
	}
	if err := w.b.Put(itob(e.ID), encoded); err != nil {
		return err
	}
	w.dirty = true
	meta := w.h.meta(e)
	l := w.h.list(meta.pinned)
	*l = append(*l, meta)
	return nil
}

func (w *historyWriter) delete(id uint64) error {
	if err := w.b.Delete(itob(id)); err != nil {
		return err
	}
	w.dirty = true
	w.h.remove(id)
	return nil
}

func (w *historyWriter) deleteIDs(ids []uint64) error {
	for _, id := range ids {
		w.dirty = true
		if err := w.b.Delete(itob(id)); err != nil {
			return err
		}
	}
	return nil
}

func (w *historyWriter) deleteWhere(pred func(*entryMeta) bool) (int, error) {
	ids := w.h.removeWhere(pred)
	return len(ids), w.deleteIDs(ids)
}

func (w *historyWriter) deleteUnpinnedWithHash(hash uint64) error {
	_, err := w.deleteWhere(func(e *entryMeta) bool { return !e.pinned && e.hash == hash })
	return err
}

func (w *historyWriter) trim(cfg Config) error {
	if cfg.AutoClearDays > 0 {
		cutoff := time.Now().AddDate(0, 0, -cfg.AutoClearDays).UnixNano()
		expired, _ := slices.BinarySearchFunc(w.h.recent, cutoff, func(e entryMeta, t int64) int {
			return cmp.Compare(e.ts, t)
		})
		if err := w.deleteIDs(w.h.trimRecent(len(w.h.recent) - expired)); err != nil {
			return err
		}
	}
	if cfg.MaxHistory < 0 {
		return nil
	}
	return w.deleteIDs(w.h.trimRecent(cfg.MaxHistory))
}

func (m *Manager) loadHistoryLocked() {
	h := &m.history
	h.loaded = true
	h.revision++
	h.recent, h.pinned = nil, nil
	if m.db == nil {
		return
	}
	if err := m.dbView(func(tx *bolt.Tx) error {
		b := tx.Bucket(bucketName)
		if b == nil {
			return nil
		}
		return h.load(b)
	}); err != nil {
		log.Errorf("Failed to load clipboard history: %v", err)
	}
}

func (m *Manager) reloadHistory() {
	m.history.mu.Lock()
	defer m.history.mu.Unlock()
	m.loadHistoryLocked()
}

func (m *Manager) readHistory(fn func(h *historyIndex)) {
	h := &m.history
	h.mu.RLock()
	if h.loaded {
		defer h.mu.RUnlock()
		fn(h)
		return
	}
	h.mu.RUnlock()

	h.mu.Lock()
	defer h.mu.Unlock()
	if !h.loaded {
		m.loadHistoryLocked()
	}
	fn(h)
}

// fn must not call readHistory: the index lock is held for the whole transaction
func (m *Manager) writeHistory(fn func(w *historyWriter) error) error {
	if m.db == nil {
		return fmt.Errorf("database not available")
	}

	h := &m.history
	h.mu.Lock()
	defer h.mu.Unlock()
	if !h.loaded {
		m.loadHistoryLocked()
	}

	w := &historyWriter{h: h}
	err := m.dbUpdate(func(tx *bolt.Tx) error {
		w.b = tx.Bucket(bucketName)
		if w.b == nil {
			return fmt.Errorf("clipboard bucket missing")
		}
		return fn(w)
	})
	switch {
	case err != nil && w.dirty:
		m.loadHistoryLocked()
	case err == nil && w.dirty:
		h.revision++
	}
	return err
}

// b may be nil, then only previews are searched
type entryMatcher func(e *entryMeta, b *bolt.Bucket) bool

func (p SearchParams) matcher(autoClearDays int) entryMatcher {
	terms := strings.Fields(strings.ToLower(p.Query))
	mimeFilter := strings.ToLower(p.MimeType)
	cutoff := int64(math.MinInt64)
	if autoClearDays > 0 {
		cutoff = time.Now().AddDate(0, 0, -autoClearDays).UnixNano()
	}

	return func(e *entryMeta, b *bolt.Bucket) bool {
		switch {
		case !e.pinned && e.ts < cutoff:
			return false
		case p.IsImage != nil && e.isImage != *p.IsImage:
			return false
		case p.Before != nil && e.ts/int64(time.Second) >= *p.Before:
			return false
		case p.After != nil && e.ts/int64(time.Second) <= *p.After:
			return false
		case !matchesType(e, p.Type):
			return false
		case mimeFilter != "" && !containsFold(e.mime, mimeFilter):
			return false
		}
		var data []byte
		for _, term := range terms {
			if containsFold(e.preview, term) {
				continue
			}
			if data == nil && b != nil && hasMoreThanPreview(e) {
				data = rowData(b, e.id)
			}
			if !containsFoldLong(data, term) {
				return false
			}
		}
		return true
	}
}

func hasMoreThanPreview(e *entryMeta) bool {
	return !e.isImage && (int(e.size) > len(e.preview) || strings.HasSuffix(e.preview, "…"))
}

// the slice points into the bbolt mmap and is only valid inside the transaction
func rowData(b *bolt.Bucket, id uint64) []byte {
	v := b.Get(itob(id))
	if len(v) < 12 {
		return nil
	}
	size := int(binary.BigEndian.Uint32(v[8:12]))
	return v[12:min(12+size, len(v))]
}

func matchesType(e *entryMeta, kind string) bool {
	switch kind {
	case "image":
		return e.isImage
	case "text":
		return !e.isImage && e.size <= longTextThreshold
	case "long_text":
		return !e.isImage && e.size > longTextThreshold
	default:
		return true
	}
}

func containsFold[T string | []byte](s T, needle string) bool {
	if !isASCII(needle) {
		return strings.Contains(strings.ToLower(string(s)), needle)
	}
	if needle == "" {
		return true
	}

	first := needle[0]
	for i := 0; i+len(needle) <= len(s); i++ {
		if asciiLower(s[i]) == first && asciiLowerEqual(s[i+1:i+len(needle)], needle[1:]) {
			return true
		}
	}
	return false
}

func containsFoldLong(s []byte, needle string) bool {
	if needle == "" || !isASCII(needle) {
		return containsFold(s, needle)
	}

	first, upper := needle[0], needle[0]
	if 'a' <= first && first <= 'z' {
		upper -= 'a' - 'A'
	}
	last := len(s) - len(needle)
	for i := 0; i <= last; i++ {
		window := s[i : last+1]
		j := bytes.IndexByte(window, first)
		if upper != first {
			bound := window
			if j >= 0 {
				bound = window[:j]
			}
			if k := bytes.IndexByte(bound, upper); k >= 0 {
				j = k
			}
		}
		if j < 0 {
			return false
		}
		i += j
		if asciiLowerEqual(s[i+1:i+len(needle)], needle[1:]) {
			return true
		}
	}
	return false
}

func asciiLower(c byte) byte {
	if 'A' <= c && c <= 'Z' {
		return c + 'a' - 'A'
	}
	return c
}

func asciiLowerEqual[T string | []byte](s T, lower string) bool {
	for i := 0; i < len(lower); i++ {
		if asciiLower(s[i]) != lower[i] {
			return false
		}
	}
	return true
}

func isASCII(s string) bool {
	for i := 0; i < len(s); i++ {
		if s[i] >= 0x80 {
			return false
		}
	}
	return true
}
