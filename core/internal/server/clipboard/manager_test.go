package clipboard

import (
	"bytes"
	"encoding/json"
	"fmt"
	"image"
	"image/png"
	"net"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	bolt "go.etcd.io/bbolt"

	"github.com/duxlabs-dev/dux-go/ipc"
	wlclient "github.com/duxlabs-dev/dux-go/wayland/client"
	"github.com/duxlabs-dev/dux-go/wayland/ext_data_control"
	mocks_wlcontext "github.com/duxlabs-dev/dux-shell/core/internal/mocks/wlcontext"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/models"
)

type clipboardTestConn struct {
	net.Conn
	writeBuf *bytes.Buffer
}

func newClipboardTestConn() *clipboardTestConn {
	return &clipboardTestConn{writeBuf: &bytes.Buffer{}}
}

func (c *clipboardTestConn) Write(b []byte) (int, error) {
	return c.writeBuf.Write(b)
}

func (c *clipboardTestConn) SetWriteDeadline(t time.Time) error { return nil }

func newTestManagerWithDB(t *testing.T) *Manager {
	t.Helper()

	db, err := openDB(filepath.Join(t.TempDir(), "clipboard.db"))
	require.NoError(t, err)

	t.Cleanup(func() {
		db.Close()
	})

	mockCtx := mocks_wlcontext.NewMockWaylandContext(t)
	mockCtx.EXPECT().Post(mock.AnythingOfType("func()")).Return().Maybe()

	m := &Manager{
		config:         DefaultConfig(),
		db:             db,
		wlCtx:          mockCtx,
		dataControlMgr: &ext_data_control.ExtDataControlManagerV1{},
		dataDevice:     &ext_data_control.ExtDataControlDeviceV1{},
	}
	m.deviceBound.Store(true)
	return m
}

func TestEncodeDecodeEntry_Roundtrip(t *testing.T) {
	original := Entry{
		ID:        12345,
		Data:      []byte("hello world"),
		MimeType:  "text/plain;charset=utf-8",
		Preview:   "hello world",
		Size:      11,
		Timestamp: time.Now().Truncate(time.Second),
		IsImage:   false,
	}

	encoded, err := encodeEntry(original)
	assert.NoError(t, err)

	decoded, err := decodeEntry(encoded)
	assert.NoError(t, err)

	assert.Equal(t, original.ID, decoded.ID)
	assert.Equal(t, original.Data, decoded.Data)
	assert.Equal(t, original.MimeType, decoded.MimeType)
	assert.Equal(t, original.Preview, decoded.Preview)
	assert.Equal(t, original.Size, decoded.Size)
	assert.Equal(t, original.Timestamp.Unix(), decoded.Timestamp.Unix())
	assert.Equal(t, original.IsImage, decoded.IsImage)
}

func TestEncodeDecodeEntry_AltRepresentation(t *testing.T) {
	original := Entry{
		ID:          555,
		Data:        []byte{0x42, 0x4D, 0x01, 0x02},
		MimeType:    "image/bmp",
		Preview:     "[[ image 4 B bmp 85x19 ]]",
		Size:        4,
		Timestamp:   time.Now().Truncate(time.Second),
		IsImage:     true,
		Hash:        computeHash([]byte{0x42, 0x4D, 0x01, 0x02}),
		Pinned:      true,
		AltData:     []byte("real text from OneNote"),
		AltMimeType: "text/plain;charset=utf-8",
	}

	encoded, err := encodeEntry(original)
	assert.NoError(t, err)

	decoded, err := decodeEntry(encoded)
	assert.NoError(t, err)
	assert.Equal(t, original.Data, decoded.Data)
	assert.Equal(t, original.MimeType, decoded.MimeType)
	assert.True(t, decoded.Pinned)
	assert.Equal(t, original.AltData, decoded.AltData)
	assert.Equal(t, original.AltMimeType, decoded.AltMimeType)

	meta, err := decodeEntryMeta(encoded)
	assert.NoError(t, err)
	assert.Empty(t, meta.Data)
	assert.Equal(t, original.AltMimeType, meta.AltMimeType)

	assert.Equal(t, original.Hash, extractHash(encoded))
}

func TestSelectAltTextMimeType(t *testing.T) {
	tests := []struct {
		mimes    []string
		expected string
	}{
		{[]string{"image/bmp", "TEXT", "text/html", "text/plain", "text/plain;charset=utf-8", "UTF8_STRING"}, "text/plain;charset=utf-8"},
		{[]string{"image/png", "UTF8_STRING"}, "UTF8_STRING"},
		{[]string{"image/png", "text/html"}, ""},
	}

	for _, tt := range tests {
		assert.Equal(t, tt.expected, selectAltTextMimeType(tt.mimes))
	}
}

func TestStateEqual_BothNil(t *testing.T) {
	assert.False(t, stateEqual(nil, nil))
}

func TestStateEqual_OneNil(t *testing.T) {
	s := &State{Enabled: true}
	assert.False(t, stateEqual(s, nil))
	assert.False(t, stateEqual(nil, s))
}

func TestStateEqual_EnabledDiffers(t *testing.T) {
	a := &State{Enabled: true, History: []Entry{}}
	b := &State{Enabled: false, History: []Entry{}}
	assert.False(t, stateEqual(a, b))
}

func TestStateEqual_HistoryLengthDiffers(t *testing.T) {
	a := &State{Enabled: true, History: []Entry{{ID: 1}}}
	b := &State{Enabled: true, History: []Entry{}}
	assert.False(t, stateEqual(a, b))
}

func TestStateEqual_BothEqual(t *testing.T) {
	ts := time.Now().Truncate(time.Second)
	entry := Entry{
		ID:        1,
		Hash:      100,
		MimeType:  "image/png",
		Preview:   "[[ image 1 KiB png 32x32 ]]",
		Size:      1024,
		Timestamp: ts,
		IsImage:   true,
		Pinned:    true,
	}
	a := &State{Enabled: true, History: []Entry{entry}}
	b := &State{Enabled: true, History: []Entry{entry}}
	assert.True(t, stateEqual(a, b))
}

func TestStateEqual_SameLengthDifferentIDs(t *testing.T) {
	ts := time.Now().Truncate(time.Second)
	a := &State{Enabled: true, History: []Entry{{ID: 1, Hash: 100, Timestamp: ts}}}
	b := &State{Enabled: true, History: []Entry{{ID: 2, Hash: 100, Timestamp: ts}}}

	assert.False(t, stateEqual(a, b))
}

func TestStateEqual_MetadataDiffers(t *testing.T) {
	ts := time.Now().Truncate(time.Second)
	base := Entry{
		ID:        1,
		Hash:      100,
		MimeType:  "image/png",
		Preview:   "[[ image 1 KiB png 32x32 ]]",
		Size:      1024,
		Timestamp: ts,
		IsImage:   true,
		Pinned:    false,
	}

	tests := []struct {
		name   string
		mutate func(*Entry)
	}{
		{name: "hash", mutate: func(e *Entry) { e.Hash = 101 }},
		{name: "pinned", mutate: func(e *Entry) { e.Pinned = true }},
		{name: "is image", mutate: func(e *Entry) { e.IsImage = false }},
		{name: "mime type", mutate: func(e *Entry) { e.MimeType = "image/jpeg" }},
		{name: "preview", mutate: func(e *Entry) { e.Preview = "[[ image 2 KiB jpeg 64x64 ]]" }},
		{name: "size", mutate: func(e *Entry) { e.Size = 2048 }},
		{name: "timestamp", mutate: func(e *Entry) { e.Timestamp = ts.Add(time.Second) }},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			changed := base
			tt.mutate(&changed)

			a := &State{Enabled: true, History: []Entry{base}}
			b := &State{Enabled: true, History: []Entry{changed}}

			assert.False(t, stateEqual(a, b))
		})
	}
}

func TestHandleGetEntry_ReturnsExistingEntry(t *testing.T) {
	m := newTestManagerWithDB(t)
	err := m.storeEntry(Entry{
		Data:      []byte("hello world"),
		MimeType:  "text/plain;charset=utf-8",
		Preview:   "hello world",
		Size:      len("hello world"),
		Timestamp: time.Now().Truncate(time.Second),
		IsImage:   false,
	})
	require.NoError(t, err)

	history := m.GetHistory()
	require.Len(t, history, 1)

	mc := newClipboardTestConn()
	conn := ipc.NewConnWriter(mc)
	handleGetEntry(conn, ipc.Request{
		ID:     1,
		Params: map[string]any{"id": float64(history[0].ID)},
	}, m)

	var resp ipc.Response[Entry]
	require.NoError(t, json.NewDecoder(mc.writeBuf).Decode(&resp))
	assert.Empty(t, resp.Error)
	require.NotNil(t, resp.Result)
	assert.Equal(t, history[0].ID, resp.Result.ID)
	assert.Equal(t, []byte("hello world"), resp.Result.Data)
}

func TestHandleGetEntry_MissingIDReturnsNullResult(t *testing.T) {
	m := newTestManagerWithDB(t)
	mc := newClipboardTestConn()
	conn := ipc.NewConnWriter(mc)

	handleGetEntry(conn, ipc.Request{
		ID:     1,
		Params: map[string]any{"id": float64(999)},
	}, m)

	var resp ipc.Response[any]
	require.NoError(t, json.NewDecoder(mc.writeBuf).Decode(&resp))
	assert.Empty(t, resp.Error)
	assert.Nil(t, resp.Result)
}

func storeTestEntry(t *testing.T, m *Manager, text string) uint64 {
	t.Helper()

	require.NoError(t, m.storeEntry(Entry{
		Data:      []byte(text),
		MimeType:  "text/plain;charset=utf-8",
		Preview:   text,
		Size:      len(text),
		Timestamp: time.Now().Truncate(time.Second),
		IsImage:   false,
	}))

	for _, entry := range m.GetHistory() {
		if entry.Preview == text {
			return entry.ID
		}
	}

	t.Fatalf("stored entry %q not found in history", text)
	return 0
}

func TestDeleteEntries_DeletesRequestedKeepsRest(t *testing.T) {
	m := newTestManagerWithDB(t)

	first := storeTestEntry(t, m, "first")
	second := storeTestEntry(t, m, "second")
	third := storeTestEntry(t, m, "third")

	deleted, err := m.DeleteEntries([]uint64{first, third})
	require.NoError(t, err)
	assert.Equal(t, 2, deleted)

	history := m.GetHistory()
	require.Len(t, history, 1)
	assert.Equal(t, second, history[0].ID)
}

func TestDeleteEntries_SkipsPinnedEntries(t *testing.T) {
	m := newTestManagerWithDB(t)

	unpinned := storeTestEntry(t, m, "unpinned")
	pinned := storeTestEntry(t, m, "pinned")
	require.NoError(t, m.PinEntry(pinned))

	deleted, err := m.DeleteEntries([]uint64{unpinned, pinned})
	require.NoError(t, err)
	assert.Equal(t, 1, deleted)

	history := m.GetHistory()
	require.Len(t, history, 1)
	assert.True(t, history[0].Pinned)
}

func TestDeleteEntries_IgnoresUnknownIDs(t *testing.T) {
	m := newTestManagerWithDB(t)

	only := storeTestEntry(t, m, "only")

	deleted, err := m.DeleteEntries([]uint64{only, only + 1000})
	require.NoError(t, err)
	assert.Equal(t, 1, deleted)
	assert.Empty(t, m.GetHistory())
}

func TestHandleDeleteEntries_ReportsDeletedCount(t *testing.T) {
	m := newTestManagerWithDB(t)

	first := storeTestEntry(t, m, "first")
	second := storeTestEntry(t, m, "second")

	mc := newClipboardTestConn()
	conn := ipc.NewConnWriter(mc)
	handleDeleteEntries(conn, ipc.Request{
		ID:     1,
		Params: map[string]any{"ids": []any{float64(first), float64(second)}},
	}, m)

	var resp ipc.Response[map[string]int]
	require.NoError(t, json.NewDecoder(mc.writeBuf).Decode(&resp))
	assert.Empty(t, resp.Error)
	require.NotNil(t, resp.Result)
	assert.Equal(t, 2, (*resp.Result)["deleted"])
	assert.Empty(t, m.GetHistory())
}

func TestHandleDeleteEntries_RejectsBadParams(t *testing.T) {
	tests := []struct {
		name   string
		params map[string]any
	}{
		{"missing ids", map[string]any{}},
		{"ids not an array", map[string]any{"ids": float64(1)}},
		{"negative id", map[string]any{"ids": []any{float64(-1)}}},
		{"id of the wrong type", map[string]any{"ids": []any{"1"}}},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			m := newTestManagerWithDB(t)
			kept := storeTestEntry(t, m, "kept")

			mc := newClipboardTestConn()
			conn := ipc.NewConnWriter(mc)
			handleDeleteEntries(conn, ipc.Request{ID: 1, Params: tt.params}, m)

			var resp ipc.Response[any]
			require.NoError(t, json.NewDecoder(mc.writeBuf).Decode(&resp))
			assert.NotEmpty(t, resp.Error)

			history := m.GetHistory()
			require.Len(t, history, 1)
			assert.Equal(t, kept, history[0].ID)
		})
	}
}

func TestUnpinEntry_KeepsTopUnpinnedDuplicate(t *testing.T) {
	m := newTestManagerWithDB(t)

	require.NoError(t, m.storeEntry(Entry{
		Data:      []byte("saved content"),
		MimeType:  "text/plain;charset=utf-8",
		Preview:   "saved content",
		Size:      len("saved content"),
		Timestamp: time.Now().Add(-time.Minute).Truncate(time.Second),
		IsImage:   false,
	}))

	history := m.GetHistory()
	require.Len(t, history, 1)
	pinnedID := history[0].ID
	require.NoError(t, m.PinEntry(pinnedID))

	pinnedEntry, err := m.GetEntry(pinnedID)
	require.NoError(t, err)
	require.True(t, pinnedEntry.Pinned)

	// Bypass storeEntry to simulate legacy duplicate ordinary history entries.
	insertLegacyUnpinnedDuplicate := func(timestamp time.Time) Entry {
		duplicate := Entry{
			Data:      pinnedEntry.Data,
			MimeType:  pinnedEntry.MimeType,
			Preview:   pinnedEntry.Preview,
			Size:      pinnedEntry.Size,
			Timestamp: timestamp,
			IsImage:   pinnedEntry.IsImage,
			Pinned:    false,
		}
		duplicate.Hash = computeHash(duplicate.Data)

		require.NoError(t, m.db.Update(func(tx *bolt.Tx) error {
			b := tx.Bucket([]byte("clipboard"))
			id, err := b.NextSequence()
			if err != nil {
				return err
			}
			duplicate.ID = id

			encoded, err := encodeEntry(duplicate)
			if err != nil {
				return err
			}
			return b.Put(itob(id), encoded)
		}))

		return duplicate
	}

	olderHistoryDuplicate := insertLegacyUnpinnedDuplicate(time.Now().Add(time.Hour))
	topHistoryDuplicate := insertLegacyUnpinnedDuplicate(time.Now().Add(-time.Hour))
	require.Greater(t, topHistoryDuplicate.ID, olderHistoryDuplicate.ID)
	require.True(t, olderHistoryDuplicate.Timestamp.After(topHistoryDuplicate.Timestamp))

	history = m.GetHistory()
	require.Len(t, history, 3)
	// GetHistory sorts by timestamp, so the newer row leads even though its
	// id is lower.
	require.Equal(t, olderHistoryDuplicate.ID, history[0].ID)
	require.NoError(t, m.UnpinEntry(pinnedID))

	history = m.GetHistory()
	require.Len(t, history, 1)
	assert.False(t, history[0].Pinned)
	assert.Equal(t, pinnedEntry.Hash, history[0].Hash)
	assert.Equal(t, topHistoryDuplicate.ID, history[0].ID)
}

func TestCreateHistoryEntryFromPinned_KeepsLatestUnpinnedDuplicate(t *testing.T) {
	m := newTestManagerWithDB(t)

	require.NoError(t, m.storeEntry(Entry{
		Data:      []byte("saved content"),
		MimeType:  "text/plain;charset=utf-8",
		Preview:   "saved content",
		Size:      len("saved content"),
		Timestamp: time.Now().Add(-time.Minute).Truncate(time.Second),
		IsImage:   false,
	}))

	history := m.GetHistory()
	require.Len(t, history, 1)
	pinnedID := history[0].ID
	require.NoError(t, m.PinEntry(pinnedID))

	pinnedEntry, err := m.GetEntry(pinnedID)
	require.NoError(t, err)
	require.True(t, pinnedEntry.Pinned)
	require.NoError(t, m.CreateHistoryEntryFromPinned(pinnedEntry))
	firstDuplicate := m.GetHistory()[0]
	require.NotEqual(t, pinnedID, firstDuplicate.ID)
	require.NoError(t, m.CreateHistoryEntryFromPinned(pinnedEntry))
	latestDuplicate := m.GetHistory()[0]

	history = m.GetHistory()
	require.Len(t, history, 2)
	assert.Equal(t, latestDuplicate.ID, history[0].ID)
	assert.False(t, history[0].Pinned)
	assert.Equal(t, pinnedID, history[1].ID)
	assert.True(t, history[1].Pinned)
	assert.NotEqual(t, firstDuplicate.ID, latestDuplicate.ID)
}

func TestEditEntry_UnpinnedEntry(t *testing.T) {
	m := newTestManagerWithDB(t)

	id := storeTestEntry(t, m, "original unpinned")
	require.NoError(t, m.EditEntry(id, "edited unpinned"))

	history := m.GetHistory()
	require.Len(t, history, 1)
	assert.Equal(t, "edited unpinned", history[0].Preview)
	assert.False(t, history[0].Pinned)
	assert.NotEqual(t, id, history[0].ID)

	// Old entry should not exist
	oldEntry, err := m.GetEntry(id)
	assert.ErrorIs(t, err, errEntryNotFound)
	assert.Nil(t, oldEntry)
}

func TestEditEntry_PinnedEntryRemainsPinned(t *testing.T) {
	m := newTestManagerWithDB(t)

	id := storeTestEntry(t, m, "original pinned")
	require.NoError(t, m.PinEntry(id))
	assert.Equal(t, 1, m.GetPinnedCount())

	require.NoError(t, m.EditEntry(id, "edited pinned"))

	history := m.GetHistory()
	require.Len(t, history, 1)
	assert.Equal(t, "edited pinned", history[0].Preview)
	assert.True(t, history[0].Pinned)

	pinnedEntries := m.GetPinnedEntries()
	require.Len(t, pinnedEntries, 1)
	assert.Equal(t, "edited pinned", pinnedEntries[0].Preview)
	assert.Equal(t, 1, m.GetPinnedCount())

	// Old pinned entry should be deleted
	oldEntry, err := m.GetEntry(id)
	assert.ErrorIs(t, err, errEntryNotFound)
	assert.Nil(t, oldEntry)
}

func TestEditEntry_NotFound(t *testing.T) {
	m := newTestManagerWithDB(t)

	err := m.EditEntry(99999, "new text")
	assert.ErrorIs(t, err, errEntryNotFound)
}

func TestEditEntry_ImageReturnsError(t *testing.T) {
	m := newTestManagerWithDB(t)

	imgEntry := Entry{
		Data:      []byte{0x89, 0x50, 0x4E, 0x47},
		MimeType:  "image/png",
		Preview:   "[[ image ]]",
		Size:      4,
		Timestamp: time.Now().Truncate(time.Second),
		IsImage:   true,
	}
	require.NoError(t, m.storeEntry(imgEntry))
	history := m.GetHistory()
	require.Len(t, history, 1)
	id := history[0].ID

	err := m.EditEntry(id, "replacement text")
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "cannot edit image entry")
}

func TestEditEntry_NonTextReturnsError(t *testing.T) {
	m := newTestManagerWithDB(t)

	uriEntry := Entry{
		Data:      []byte("file:///path/to/file\n"),
		MimeType:  "text/uri-list",
		Preview:   "file:///path/to/file",
		Size:      21,
		Timestamp: time.Now().Truncate(time.Second),
		IsImage:   false,
	}
	require.NoError(t, m.storeEntry(uriEntry))
	history := m.GetHistory()
	require.Len(t, history, 1)
	id := history[0].ID

	err := m.EditEntry(id, "replacement text")
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "cannot edit non-text entry")
}

func TestEditEntry_AltTextMimeTypesAllowed(t *testing.T) {
	m := newTestManagerWithDB(t)
	entry := Entry{
		Data:      []byte("old text"),
		MimeType:  "UTF8_STRING",
		Preview:   "old text",
		Size:      8,
		Timestamp: time.Now().Truncate(time.Second),
		IsImage:   false,
	}
	require.NoError(t, m.storeEntry(entry))
	history := m.GetHistory()
	require.Len(t, history, 1)

	assert.NoError(t, m.EditEntry(history[0].ID, "replacement text"))
}

func TestEditEntry_EmptyOrWhitespaceReturnsError(t *testing.T) {
	m := newTestManagerWithDB(t)
	id := storeTestEntry(t, m, "keep me")

	err := m.EditEntry(id, "   ")
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "cannot save empty entry")

	history := m.GetHistory()
	require.Len(t, history, 1)
	assert.Equal(t, "keep me", history[0].Preview)
}

func TestEditEntry_DataTooLargeReturnsError(t *testing.T) {
	m := newTestManagerWithDB(t)
	m.config.MaxEntrySize = 10
	id := storeTestEntry(t, m, "small")

	err := m.EditEntry(id, "this text exceeds the 10-byte limit")
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "data too large")

	history := m.GetHistory()
	require.Len(t, history, 1)
	assert.Equal(t, "small", history[0].Preview)
}

func TestHandleEditEntry_SuccessAndValidation(t *testing.T) {
	m := newTestManagerWithDB(t)
	id := storeTestEntry(t, m, "before edit")

	mc := newClipboardTestConn()
	conn := ipc.NewConnWriter(mc)
	handleEditEntry(conn, ipc.Request{
		ID: 1,
		Params: map[string]any{
			"id":   float64(id),
			"text": "after edit",
		},
	}, m)

	var resp ipc.Response[models.SuccessResult]
	require.NoError(t, json.NewDecoder(mc.writeBuf).Decode(&resp))
	assert.Empty(t, resp.Error)
	require.NotNil(t, resp.Result)
	assert.True(t, resp.Result.Success)

	history := m.GetHistory()
	require.Len(t, history, 1)
	assert.Equal(t, "after edit", history[0].Preview)
}

func TestManager_ConcurrentSubscriberAccess(t *testing.T) {
	m := &Manager{
		subscribers: make(map[string]chan State),
		dirty:       make(chan struct{}, 1),
	}

	var wg sync.WaitGroup
	const goroutines = 20

	for i := range goroutines {
		wg.Add(1)
		go func(id int) {
			defer wg.Done()
			subID := string(rune('a' + id))
			ch := m.Subscribe(subID)
			assert.NotNil(t, ch)
			m.Unsubscribe(subID)
		}(i)
	}

	wg.Wait()
}

func TestManager_ConcurrentGetState(t *testing.T) {
	m := &Manager{
		state: &State{
			Enabled: true,
			History: []Entry{{ID: 1}, {ID: 2}},
		},
	}

	var wg sync.WaitGroup
	const goroutines = 50
	const iterations = 100

	for range goroutines / 2 {
		wg.Go(func() {
			for range iterations {
				s := m.GetState()
				_ = s.Enabled
				_ = len(s.History)
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
					Enabled: j%2 == 0,
					History: []Entry{{ID: uint64(j)}},
				}
				m.stateMutex.Unlock()
			}
		}(i)
	}

	wg.Wait()
}

func TestManager_ConcurrentConfigAccess(t *testing.T) {
	m := &Manager{
		config: DefaultConfig(),
	}

	var wg sync.WaitGroup
	const goroutines = 30
	const iterations = 100

	for range goroutines / 2 {
		wg.Go(func() {
			for range iterations {
				cfg := m.getConfig()
				_ = cfg.MaxHistory
				_ = cfg.MaxEntrySize
			}
		})
	}

	for i := range goroutines / 2 {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			for j := range iterations {
				m.configMutex.Lock()
				m.config.MaxHistory = 50 + j
				m.config.MaxEntrySize = int64(1024 * j)
				m.configMutex.Unlock()
			}
		}(i)
	}

	wg.Wait()
}

func TestManager_NotifySubscribersNonBlocking(t *testing.T) {
	m := &Manager{
		dirty: make(chan struct{}, 1),
	}

	for range 10 {
		m.notifySubscribers()
	}

	assert.Len(t, m.dirty, 1)
}

func TestSizeStr(t *testing.T) {
	tests := []struct {
		input    int
		expected string
	}{
		{100, "100 B"},
		{2048, "2 KiB"},
		{5242880, "5 MiB"},
	}

	for _, tt := range tests {
		result := sizeStr(tt.input)
		assert.Equal(t, tt.expected, result)
	}
}

func TestSelectMimeType(t *testing.T) {
	m := &Manager{}

	tests := []struct {
		mimes    []string
		expected string
	}{
		{[]string{"text/html", "text/plain"}, "text/plain"},
		{[]string{"text/plain", "image/png"}, "image/png"},
		{[]string{"application/octet-stream"}, "application/octet-stream"},
		{[]string{}, ""},
	}

	for _, tt := range tests {
		result := m.selectMimeType(tt.mimes)
		assert.Equal(t, tt.expected, result)
	}
}

func TestTextPreview(t *testing.T) {
	m := &Manager{}

	short := m.textPreview([]byte("hello world"))
	assert.Equal(t, "hello world", short)

	withWhitespace := m.textPreview([]byte("  hello   world  "))
	assert.Equal(t, "hello world", withWhitespace)

	longText := make([]byte, 200)
	for i := range longText {
		longText[i] = 'a'
	}
	preview := m.textPreview(longText)
	assert.True(t, len(preview) > 100)
	assert.Contains(t, preview, "…")
}

// zero padding in a fresh db, never a valid page
const corruptRootPgid = 7

func corruptInlineBucketRoot(t *testing.T, path string, rootPgid byte) {
	t.Helper()

	f, err := os.OpenFile(path, os.O_RDWR, 0o644)
	require.NoError(t, err)
	defer f.Close()

	// flips the inline bucket root pgid to an unwritten page, per issue #3232
	_, err = f.WriteAt([]byte{rootPgid}, int64(4*os.Getpagesize()+32+9))
	require.NoError(t, err)
}

// bbolt maps to the next power of two, so the root stays mapped but past EOF: fault, not panic
func dropPage(t *testing.T, path string, pgid byte) {
	t.Helper()

	require.NoError(t, os.Truncate(path, int64(pgid)*int64(os.Getpagesize())))
}

func newCorruptDB(t *testing.T, pastEOF bool) string {
	t.Helper()

	path := filepath.Join(t.TempDir(), "db")

	db, err := openDB(path)
	require.NoError(t, err)
	require.NoError(t, db.Close())

	corruptInlineBucketRoot(t, path, corruptRootPgid)
	if pastEOF {
		dropPage(t, path, corruptRootPgid)
	}

	return path
}

var corruptDBCases = []struct {
	name    string
	pastEOF bool
}{
	{"root page unwritten", false},
	{"root page past end of file", true},
}

func TestOpenDB_HealsCorruptedBucketPage(t *testing.T) {
	for _, tt := range corruptDBCases {
		t.Run(tt.name, func(t *testing.T) {
			path := newCorruptDB(t, tt.pastEOF)

			db, err := openDB(path)
			require.NoError(t, err)
			defer db.Close()

			m := &Manager{config: DefaultConfig(), db: db, dbPath: path}
			require.NoError(t, m.storeEntry(Entry{Data: []byte("x"), MimeType: "text/plain"}))
			assert.Len(t, m.GetHistory(), 1)
		})
	}
}

func TestOpenDB_HealsGarbageFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "db")
	require.NoError(t, os.WriteFile(path, bytes.Repeat([]byte{0xAB}, 64<<10), 0o644))

	db, err := openDB(path)
	require.NoError(t, err)
	defer db.Close()

	_, err = os.Stat(path + ".corrupt")
	require.NoError(t, err)
}

func TestOpenDB_LockedByAnotherProcessKeepsHistory(t *testing.T) {
	path := filepath.Join(t.TempDir(), "db")
	holder, err := openDB(path)
	require.NoError(t, err)
	m := &Manager{config: DefaultConfig(), db: holder, dbPath: path}
	require.NoError(t, m.storeEntry(Entry{Data: []byte("x"), MimeType: "text/plain"}))

	_, err = openDB(path)
	require.Error(t, err)
	require.NoError(t, holder.Close())

	reopened, err := openDB(path)
	require.NoError(t, err)
	defer reopened.Close()
	m = &Manager{config: DefaultConfig(), db: reopened, dbPath: path}
	assert.Len(t, m.GetHistory(), 1)
}

func TestStoreEntry_CorruptDBReturnsErrorNotPanic(t *testing.T) {
	for _, tt := range corruptDBCases {
		t.Run(tt.name, func(t *testing.T) {
			path := newCorruptDB(t, tt.pastEOF)

			db, err := bolt.Open(path, 0o644, &bolt.Options{Timeout: time.Second})
			require.NoError(t, err)
			defer db.Close()

			m := &Manager{config: DefaultConfig(), db: db, dbPath: path}
			assert.Error(t, m.storeEntry(Entry{Data: []byte("x"), MimeType: "text/plain"}))
			assert.Empty(t, m.GetHistory())
		})
	}
}

// The URI convention only holds if encode and decode are exact inverses for
// the path shapes users actually have.
func TestFileURIRoundTrip(t *testing.T) {
	paths := []struct{ name, path string }{
		{"space", "/home/user/My File.txt"},
		{"literal percent-20", "/home/user/report%20final.fbx"},
		{"hash", "/home/user/notes #1/draft.txt"},
		{"cjk", "/home/user/文档/吉祥物 男女(2).fbx"},
		{"bare percent", "/home/user/100%.done"},
	}
	for _, tc := range paths {
		t.Run(tc.name, func(t *testing.T) {
			assert.Equal(t, tc.path, pathFromFileURI(encodeFileURI(tc.path)))
		})
	}
}

// Oversized files are stored as a URI with no body. Storing that URI
// unencoded makes EntryToFile decode a path that was never encoded, so a
// literal "%20" in the name resolves to a different, missing file.
func TestCopyFile_OversizedEntryRoundTrips(t *testing.T) {
	m := newTestManagerWithDB(t)
	m.config.MaxEntrySize = 8 // force the nil fileData branch

	path := filepath.Join(t.TempDir(), "report%20final.fbx")
	require.NoError(t, os.WriteFile(path, []byte("fbx-bytes"), 0o644))

	require.NoError(t, m.CopyFile(path))

	history := m.GetHistory()
	require.Len(t, history, 1)
	require.Equal(t, "text/uri-list", history[0].MimeType)
	// GetHistory only carries metadata; the stored body lives in GetEntry.
	entry, err := m.GetEntry(history[0].ID)
	require.NoError(t, err)
	assert.Equal(t, path, m.EntryToFile(entry))
}

// A directory's stat size is tiny, so it passes the MaxEntrySize check and
// must not reach os.ReadFile, which fails with EISDIR.
func TestCopyFile_DirectoryStoresURI(t *testing.T) {
	m := newTestManagerWithDB(t)

	dir := filepath.Join(t.TempDir(), "My Folder")
	require.NoError(t, os.Mkdir(dir, 0o755))

	require.NoError(t, m.CopyFile(dir))

	history := m.GetHistory()
	require.Len(t, history, 1)
	require.Equal(t, "text/uri-list", history[0].MimeType)
	entry, err := m.GetEntry(history[0].ID)
	require.NoError(t, err)
	assert.Equal(t, dir, m.EntryToFile(entry))
}

// CopyFile hands the image probe a URI the probe then decodes; it must be an
// encoded one, or a name containing literal %20 probes the wrong path and the
// copy silently downgrades to a plain uri-list entry.
func TestCopyFile_EncodedImageNameStaysImage(t *testing.T) {
	m := newTestManagerWithDB(t)

	path := filepath.Join(t.TempDir(), "抓拍%20name.png")
	var buf bytes.Buffer
	require.NoError(t, png.Encode(&buf, image.NewRGBA(image.Rect(0, 0, 4, 4))))
	require.NoError(t, os.WriteFile(path, buf.Bytes(), 0o644))

	require.NoError(t, m.CopyFile(path))

	history := m.GetHistory()
	require.Len(t, history, 1)
	require.True(t, history[0].IsImage)
	assert.Equal(t, "image/png", history[0].MimeType)
}

// The preview chain stats the path, so it must decode the encoded URIs
// file managers hand us while keeping a literal "%20" in the name intact.
func TestURIListPreview_DecodesEncodedURI(t *testing.T) {
	m := newTestManagerWithDB(t)

	path := filepath.Join(t.TempDir(), "report%20final.fbx")
	require.NoError(t, os.WriteFile(path, []byte("fbx-bytes"), 0o644))

	preview, isImage := m.uriListPreview([]byte(encodeFileURI(path) + "\r\n"))
	assert.Equal(t, "[[ file report%20final.fbx ]]", preview)
	assert.False(t, isImage)
}

// History restore runs handleCopyEntry -> EntryToFile -> CopyFile; the exact
// path must survive the whole chain, literal %20 included.
func TestHandleCopyEntry_OversizedFileEntryRestoresExactPath(t *testing.T) {
	m := newTestManagerWithDB(t)
	m.config.MaxEntrySize = 8

	path := filepath.Join(t.TempDir(), "report%20final.fbx")
	require.NoError(t, os.WriteFile(path, []byte("0123456789abcdef"), 0o644))
	require.NoError(t, m.CopyFile(path))

	history := m.GetHistory()
	require.Len(t, history, 1)

	mc := newClipboardTestConn()
	handleCopyEntry(ipc.NewConnWriter(mc), ipc.Request{
		ID:     1,
		Params: map[string]any{"id": float64(history[0].ID)},
	}, m)

	var resp ipc.Response[map[string]any]
	require.NoError(t, json.NewDecoder(mc.writeBuf).Decode(&resp))
	require.Empty(t, resp.Error)
	require.NotNil(t, resp.Result)
	assert.Equal(t, path, (*resp.Result)["filePath"])
}

// A manager built with tracking disabled never binds data control but still
// serves clipboard.copyFile; answering success there made dms screenshot skip
// its local copy and leave the clipboard empty.
func TestCopyFile_DisabledTrackingRefusesCopy(t *testing.T) {
	t.Setenv("XDG_CACHE_HOME", t.TempDir())
	t.Setenv("XDG_CONFIG_HOME", t.TempDir())

	mockCtx := mocks_wlcontext.NewMockWaylandContext(t)
	mockCtx.EXPECT().Display().Return(nil).Maybe()
	mockCtx.EXPECT().Post(mock.AnythingOfType("func()")).Run(func(fn func()) { fn() }).Maybe()

	cfg := DefaultConfig()
	cfg.Disabled = true
	m, err := NewManager(mockCtx, cfg)
	require.NoError(t, err)
	t.Cleanup(m.Close)

	path := filepath.Join(t.TempDir(), "shot.png")
	require.NoError(t, os.WriteFile(path, []byte("png-bytes"), 0o644))

	require.ErrorIs(t, m.CopyFile(path), errSelectionUnavailable)
	assert.Empty(t, m.GetHistory())
}

func TestApplyConfigChange_DisableReleasesDataDevice(t *testing.T) {
	sock := filepath.Join(t.TempDir(), "wayland-test")
	ln, err := net.Listen("unix", sock)
	require.NoError(t, err)
	t.Cleanup(func() { ln.Close() })

	display, err := wlclient.Connect(sock)
	require.NoError(t, err)
	t.Cleanup(func() { display.Context().Close() })

	m := newTestManagerWithDB(t)
	mockCtx := mocks_wlcontext.NewMockWaylandContext(t)
	mockCtx.EXPECT().Post(mock.AnythingOfType("func()")).Run(func(fn func()) { fn() })
	m.wlCtx = mockCtx
	device := ext_data_control.NewExtDataControlDeviceV1(display.Context())
	m.dataDevice = device

	cfg := DefaultConfig()
	cfg.Disabled = true
	m.applyConfigChange(cfg)

	assert.True(t, device.IsZombie())
	assert.Nil(t, m.dataDevice)
	require.ErrorIs(t, m.CopyText("secret"), errSelectionUnavailable)
	assert.Empty(t, m.GetHistory())
}

func TestTouchEntry_SurvivesTrimWhenHistoryFull(t *testing.T) {
	m := newTestManagerWithDB(t)
	m.config.MaxHistory = 3

	for i := range 3 {
		require.NoError(t, m.storeEntry(Entry{
			Data:      []byte(fmt.Sprintf("entry-%d", i)),
			MimeType:  "text/plain",
			Timestamp: time.Now(),
		}))
	}

	oldest := m.GetHistory()[2]
	require.NoError(t, m.TouchEntry(oldest.ID))

	// A new copy trims the bucket back to MaxHistory.
	require.NoError(t, m.storeEntry(Entry{
		Data:      []byte("newcomer"),
		MimeType:  "text/plain",
		Timestamp: time.Now(),
	}))

	history := m.GetHistory()
	require.Len(t, history, 3)
	ids := make([]uint64, len(history))
	for i, e := range history {
		ids[i] = e.ID
	}
	assert.Contains(t, ids, oldest.ID, "the touched row must survive trimming")
	assert.Equal(t, oldest.ID, history[1].ID, "the touched row ranks second, behind the newer copy")
}

func TestGetHistory_SameSecondOrdersByID(t *testing.T) {
	m := newTestManagerWithDB(t)
	m.config.MaxHistory = 10

	stamp := time.Now()
	for i := range 3 {
		require.NoError(t, m.storeEntry(Entry{
			Data:      []byte(fmt.Sprintf("same-second-%d", i)),
			MimeType:  "text/plain",
			Timestamp: stamp,
		}))
	}

	// Touching the oldest row rewrites it in place, so the bucket now yields
	// it first even though every row shares a timestamp.
	oldest := m.GetHistory()[2]
	require.NoError(t, m.TouchEntry(oldest.ID))

	history := m.GetHistory()
	require.Len(t, history, 3)
	assert.Equal(t, oldest.ID, history[0].ID, "the touched row must lead: its timestamp is newer")
	assert.Greater(t, history[1].ID, history[2].ID, "rows still tied on timestamp break on newest id")
}
