package clipboard

import (
	"bytes"
	"cmp"
	"encoding/binary"
	"errors"
	"fmt"
	"image"
	_ "image/gif"
	_ "image/jpeg"
	_ "image/png"
	"io"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"runtime/debug"
	"slices"
	"strings"
	"syscall"
	"time"

	"hash/fnv"

	"github.com/fsnotify/fsnotify"
	"github.com/godbus/dbus/v5"
	_ "golang.org/x/image/bmp"
	_ "golang.org/x/image/tiff"
	_ "golang.org/x/image/webp"

	bolt "go.etcd.io/bbolt"
	berrors "go.etcd.io/bbolt/errors"

	wlclient "github.com/duxlabs-dev/dux-go/wayland/client"
	"github.com/duxlabs-dev/dux-go/wayland/ext_data_control"
	"github.com/duxlabs-dev/dux-go/wlclipboard"
	clipboardstore "github.com/duxlabs-dev/dux-shell/core/internal/clipboard"
	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/duxlabs-dev/dux-shell/core/internal/proto/virtual_keyboard"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/wlcontext"
)

var errEntryNotFound = errors.New("entry not found")

// These mime types won't be stored in history
var sensitiveMimeTypes = []string{
	"x-kde-passwordManagerHint",
}

func NewManager(wlCtx wlcontext.WaylandContext, config Config) (*Manager, error) {
	display := wlCtx.Display()
	dbPath, err := clipboardstore.GetDBPath()
	if err != nil {
		return nil, fmt.Errorf("failed to get db path: %w", err)
	}

	configPath, _ := getConfigPath()

	db, err := openDB(dbPath)
	if err != nil {
		return nil, fmt.Errorf("failed to open db: %w", err)
	}

	m := &Manager{
		config:         config,
		db:             db,
		configPath:     configPath,
		display:        display,
		wlCtx:          wlCtx,
		stopChan:       make(chan struct{}),
		subscribers:    make(map[string]chan State),
		dirty:          make(chan struct{}, 1),
		offerMimeTypes: make(map[any][]string),
		dbPath:         dbPath,
	}

	if !config.Disabled {
		if err := m.setupRegistry(); err != nil {
			db.Close()
			return nil, err
		}
	}

	m.notifierWg.Add(1)
	go m.notifier()

	go m.watchConfig()

	if err := m.migrateHashes(); err != nil {
		log.Errorf("Failed to migrate hashes: %v", err)
	}

	if !config.Disabled {
		if config.ClearAtStartup {
			if err := m.clearHistoryInternal(); err != nil {
				log.Errorf("Failed to clear history at startup: %v", err)
			}
		}

		if config.AutoClearDays > 0 {
			if err := m.clearOldEntries(config.AutoClearDays); err != nil {
				log.Errorf("Failed to clear old entries: %v", err)
			}
		}
	}

	m.alive = true
	m.updateState()

	if !config.Disabled && m.dataControlMgr != nil && m.seat != nil {
		m.setupDataDeviceSync()
	}

	return m, nil
}

func openDB(path string) (*bolt.DB, error) {
	db, err := tryOpenDB(path)
	if err == nil {
		return db, nil
	}
	if errors.Is(err, berrors.ErrTimeout) {
		return nil, err
	}

	log.Errorf("Clipboard db corrupted, salvaging readable entries: %v", err)

	salvagePath := path + ".salvage"
	os.Remove(salvagePath)
	// chunked commits keep entries copied before the first unreadable page
	if salvageErr := compactInto(path, salvagePath, 64<<10); salvageErr != nil {
		log.Warnf("Clipboard db salvage stopped early: %v", salvageErr)
	}

	corruptPath := path + ".corrupt"
	os.Remove(corruptPath)
	if renameErr := os.Rename(path, corruptPath); renameErr != nil {
		os.Remove(salvagePath)
		return nil, err
	}

	os.Rename(salvagePath, path)

	db, err = tryOpenDB(path)
	if err == nil {
		return db, nil
	}

	os.Remove(path)
	return tryOpenDB(path)
}

// bbolt reports corrupted pages by panicking (internal/common/verify.go), not
// by returning errors, so every db touchpoint recovers and converts to error.
func recoverDBPanic(err *error) {
	r := recover()
	if r == nil {
		return
	}
	*err = fmt.Errorf("clipboard db panic: %v", r)
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
		db, err = nil, fmt.Errorf("clipboard db panic: %v", r)
	}()
	defer armDBFaultPanics()()

	db, err = bolt.Open(path, 0o644, &bolt.Options{
		Timeout: 1 * time.Second,
	})
	if err != nil {
		return nil, err
	}

	err = db.Update(func(tx *bolt.Tx) error {
		_, err := tx.CreateBucketIfNotExists([]byte("clipboard"))
		return err
	})
	if err != nil {
		db.Close()
		return nil, err
	}

	err = db.View(func(tx *bolt.Tx) error {
		b := tx.Bucket([]byte("clipboard"))
		if b == nil {
			return nil
		}
		return b.ForEach(func(k, v []byte) error { return nil })
	})
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

func (m *Manager) post(fn func()) {
	m.wlCtx.Post(fn)
}

func (m *Manager) setupRegistry() error {
	ctx := m.display.Context()

	registry, err := m.display.GetRegistry()
	if err != nil {
		return fmt.Errorf("failed to get registry: %w", err)
	}
	m.registry = registry

	registry.SetGlobalHandler(func(e wlclient.RegistryGlobalEvent) {
		switch e.Interface {
		case "ext_data_control_manager_v1":
			if e.Version < 1 {
				return
			}
			dataControlMgr := ext_data_control.NewExtDataControlManagerV1(ctx)
			if err := registry.Bind(e.Name, e.Interface, e.Version, dataControlMgr); err != nil {
				log.Errorf("Failed to bind ext_data_control_manager_v1: %v", err)
				return
			}
			m.dataControlMgr = dataControlMgr
			log.Info("Bound ext_data_control_manager_v1")
		case "wl_seat":
			if m.seat != nil {
				return
			}
			seat := wlclient.NewSeat(ctx)
			if err := registry.Bind(e.Name, e.Interface, e.Version, seat); err != nil {
				log.Errorf("Failed to bind wl_seat: %v", err)
				return
			}
			m.seat = seat
			m.seatName = e.Name
			log.Info("Bound wl_seat")
		case virtual_keyboard.ZwpVirtualKeyboardManagerV1InterfaceName:
			m.pasteSupported = true
		}
	})

	m.display.Roundtrip()
	m.display.Roundtrip()

	if m.dataControlMgr == nil {
		return fmt.Errorf("compositor does not support ext_data_control_manager_v1")
	}

	if m.seat == nil {
		return fmt.Errorf("no seat available")
	}

	return nil
}

func (m *Manager) setupDataDeviceSync() {
	if !m.bindDataDevice() {
		return
	}

	if err := m.display.Context().Dispatch(); err != nil {
		log.Errorf("Failed to dispatch initial events: %v", err)
		return
	}

	log.Info("Data device setup complete")
}

// Runs on the dispatcher goroutine; a disabled manager must hold no device so it receives no offers.
func (m *Manager) syncTracking() {
	if m.getConfig().Disabled {
		m.releaseDataDevice()
		return
	}
	if m.dataDevice != nil {
		return
	}
	if m.registry == nil {
		if err := m.setupRegistry(); err != nil {
			log.Errorf("Failed to enable clipboard tracking: %v", err)
			return
		}
	}
	if m.bindDataDevice() {
		log.Info("Data device setup complete")
	}
}

func (m *Manager) releaseDataDevice() {
	m.deviceBound.Store(false)

	if m.currentOffer != nil {
		m.releaseOffer(m.currentOffer)
		m.currentOffer = nil
	}

	if m.dataDevice == nil {
		return
	}
	m.dataDevice.(*ext_data_control.ExtDataControlDeviceV1).Destroy()
	m.dataDevice = nil
	m.mimeTypes = nil
}

func (m *Manager) bindDataDevice() bool {
	if m.dataControlMgr == nil || m.seat == nil {
		return false
	}

	dataMgr := m.dataControlMgr.(*ext_data_control.ExtDataControlManagerV1)

	dataDevice, err := dataMgr.GetDataDevice(m.seat)
	if err != nil {
		log.Errorf("Failed to send get_data_device request: %v", err)
		return false
	}

	dataDevice.SetDataOfferHandler(func(e ext_data_control.ExtDataControlDeviceV1DataOfferEvent) {
		if e.Id == nil {
			return
		}

		m.offerMutex.Lock()
		m.offerMimeTypes[e.Id] = make([]string, 0)
		m.offerMutex.Unlock()

		e.Id.SetOfferHandler(func(me ext_data_control.ExtDataControlOfferV1OfferEvent) {
			m.offerMutex.Lock()
			m.offerMimeTypes[e.Id] = append(m.offerMimeTypes[e.Id], me.MimeType)
			m.offerMutex.Unlock()
		})
	})

	dataDevice.SetSelectionHandler(func(e ext_data_control.ExtDataControlDeviceV1SelectionEvent) {
		// The first event replays the selection that existed before binding.
		if !m.initialized {
			m.initialized = true
			if e.Id != nil {
				m.releaseOffer(e.Id)
			}
			return
		}

		var offer any
		if e.Id != nil {
			offer = e.Id
		}

		m.ownerLock.Lock()
		wasOwner := m.isOwner
		m.ownerLock.Unlock()

		if wasOwner {
			return
		}

		prevOffer := m.currentOffer
		m.currentOffer = offer

		if prevOffer != nil && prevOffer != offer {
			m.releaseOffer(prevOffer)
		}

		if offer == nil {
			return
		}

		// An event can land between a runtime disable and the posted release.
		if m.getConfig().Disabled {
			return
		}

		m.offerMutex.RLock()
		mimes := m.offerMimeTypes[offer]
		m.offerMutex.RUnlock()

		m.mimeTypes = mimes

		if len(mimes) == 0 {
			return
		}

		if m.hasSensitiveMimeType(mimes) {
			return
		}

		preferredMime := m.selectMimeType(mimes)
		if preferredMime == "" {
			return
		}

		typedOffer := offer.(*ext_data_control.ExtDataControlOfferV1)

		r, w, err := os.Pipe()
		if err != nil {
			return
		}

		if err := typedOffer.Receive(preferredMime, int(w.Fd())); err != nil {
			r.Close()
			w.Close()
			return
		}
		w.Close()

		altMime := ""
		if m.isImageMimeType(preferredMime) && !slices.Contains(mimes, "x-special/gnome-copied-files") {
			altMime = selectAltTextMimeType(mimes)
		}
		if altMime == "" {
			go m.readAndStore(r, preferredMime, nil, "")
			return
		}

		altR, altW, err := os.Pipe()
		if err != nil {
			go m.readAndStore(r, preferredMime, nil, "")
			return
		}
		if err := typedOffer.Receive(altMime, int(altW.Fd())); err != nil {
			altR.Close()
			altW.Close()
			go m.readAndStore(r, preferredMime, nil, "")
			return
		}
		altW.Close()

		go m.readAndStore(r, preferredMime, altR, altMime)
	})

	m.initialized = false
	m.dataDevice = dataDevice
	m.deviceBound.Store(true)
	return true
}

func (m *Manager) releaseOffer(offer any) {
	if offer == nil {
		return
	}
	typedOffer, ok := offer.(*ext_data_control.ExtDataControlOfferV1)
	if !ok {
		return
	}
	m.offerMutex.Lock()
	delete(m.offerMimeTypes, offer)
	m.offerMutex.Unlock()
	typedOffer.Destroy()
}

func (m *Manager) releaseCurrentSource() {
	if m.currentSource == nil {
		return
	}
	source, ok := m.currentSource.(*ext_data_control.ExtDataControlSourceV1)
	m.currentSource = nil
	if !ok {
		return
	}
	source.Destroy()
}

func readPipeTimeout(r *os.File, maxSize int64) []byte {
	done := make(chan []byte, 1)
	go func() {
		data, _ := io.ReadAll(io.LimitReader(r, maxSize+1))
		done <- data
	}()

	select {
	case data := <-done:
		return data
	case <-time.After(500 * time.Millisecond):
		return nil
	}
}

func (m *Manager) readAndStore(r *os.File, mimeType string, altR *os.File, altMime string) {
	defer r.Close()

	cfg := m.getConfig()

	altCh := make(chan []byte, 1)
	switch altR {
	case nil:
		altCh <- nil
	default:
		go func() {
			defer altR.Close()
			altCh <- readPipeTimeout(altR, cfg.MaxEntrySize)
		}()
	}

	data := readPipeTimeout(r, cfg.MaxEntrySize)
	altData := <-altCh

	if len(bytes.TrimSpace(altData)) == 0 || int64(len(altData)) > cfg.MaxEntrySize {
		altData, altMime = nil, ""
	}

	if len(data) == 0 || int64(len(data)) > cfg.MaxEntrySize {
		return
	}
	if len(bytes.TrimSpace(data)) == 0 {
		return
	}

	if !cfg.Disabled && m.db != nil {
		m.storeClipboardEntry(data, mimeType, altData, altMime)
	}

	m.updateState()
	m.notifySubscribers()

	if len(data)+len(altData) >= largeEntryBytes {
		debug.FreeOSMemory()
	}
}

func (m *Manager) storeClipboardEntry(data []byte, mimeType string, altData []byte, altMime string) {
	if mimeType == "text/uri-list" {
		if imgData, imgMime, ok := m.tryReadImageFromURI(data); ok {
			data = imgData
			mimeType = imgMime
		}
	}

	entry := Entry{
		Data:        data,
		MimeType:    mimeType,
		Size:        len(data),
		Timestamp:   time.Now(),
		IsImage:     m.isImageMimeType(mimeType),
		AltData:     altData,
		AltMimeType: altMime,
	}

	switch {
	case entry.IsImage:
		entry.Preview = m.imagePreview(data, mimeType)
	case mimeType == "text/uri-list":
		entry.Preview, entry.IsImage = m.uriListPreview(data)
	default:
		entry.Preview = m.textPreview(data)
	}

	if err := m.storeEntry(entry); err != nil {
		log.Errorf("Failed to store clipboard entry: %v", err)
	}
}

func (m *Manager) storeEntry(entry Entry) error {
	if m.getConfig().Disabled {
		return errTrackingDisabled
	}
	if m.db == nil {
		return fmt.Errorf("database not available")
	}

	entry.Hash = computeHash(entry.Data)

	return m.dbUpdate(func(tx *bolt.Tx) error {
		b := tx.Bucket([]byte("clipboard"))
		if b == nil {
			return fmt.Errorf("clipboard bucket missing")
		}

		if err := m.deduplicateInTx(b, entry.Hash); err != nil {
			return err
		}

		id, err := b.NextSequence()
		if err != nil {
			return err
		}

		entry.ID = id

		encoded, err := encodeEntry(entry)
		if err != nil {
			return err
		}

		if err := b.Put(itob(id), encoded); err != nil {
			return err
		}

		return m.trimLengthInTx(b)
	})
}

func (m *Manager) deduplicateInTx(b *bolt.Bucket, hash uint64) error {
	c := b.Cursor()
	for k, v := c.Last(); k != nil; k, v = c.Prev() {
		if extractHash(v) != hash {
			continue
		}
		entry, err := decodeEntryMeta(v)
		if err == nil && entry.Pinned {
			continue
		}
		if err := b.Delete(k); err != nil {
			return err
		}
	}
	return nil
}

func (m *Manager) trimLengthInTx(b *bolt.Bucket) error {
	maxHistory := m.getConfig().MaxHistory
	if maxHistory < 0 {
		return nil
	}

	type row struct {
		key   []byte
		entry Entry
	}
	var rows []row
	c := b.Cursor()
	for k, v := c.First(); k != nil; k, v = c.Next() {
		entry, err := decodeEntryMeta(v)
		if err != nil || entry.Pinned {
			continue
		}
		rows = append(rows, row{slices.Clone(k), entry})
	}

	slices.SortFunc(rows, func(a, b row) int {
		return compareEntriesNewestFirst(a.entry, b.entry)
	})

	for _, r := range rows[min(maxHistory, len(rows)):] {
		if err := b.Delete(r.key); err != nil {
			return err
		}
	}
	return nil
}

func encodeEntry(e Entry) ([]byte, error) {
	buf := new(bytes.Buffer)

	binary.Write(buf, binary.BigEndian, e.ID)
	binary.Write(buf, binary.BigEndian, uint32(len(e.Data)))
	buf.Write(e.Data)
	binary.Write(buf, binary.BigEndian, uint32(len(e.MimeType)))
	buf.WriteString(e.MimeType)
	binary.Write(buf, binary.BigEndian, uint32(len(e.Preview)))
	buf.WriteString(e.Preview)
	binary.Write(buf, binary.BigEndian, int32(e.Size))
	binary.Write(buf, binary.BigEndian, e.Timestamp.UnixNano())
	if e.IsImage {
		buf.WriteByte(1)
	} else {
		buf.WriteByte(0)
	}
	binary.Write(buf, binary.BigEndian, e.Hash)
	if e.Pinned {
		buf.WriteByte(1)
	} else {
		buf.WriteByte(0)
	}
	if e.AltMimeType != "" {
		binary.Write(buf, binary.BigEndian, uint32(len(e.AltMimeType)))
		buf.WriteString(e.AltMimeType)
		binary.Write(buf, binary.BigEndian, uint32(len(e.AltData)))
		buf.Write(e.AltData)
	}

	return buf.Bytes(), nil
}

func decodeEntry(data []byte) (Entry, error) {
	return decodeEntryFields(data, true)
}

func decodeEntryMeta(data []byte) (Entry, error) {
	return decodeEntryFields(data, false)
}

func decodeEntryFields(data []byte, withData bool) (Entry, error) {
	buf := bytes.NewReader(data)
	var e Entry

	binary.Read(buf, binary.BigEndian, &e.ID)

	var dataLen uint32
	binary.Read(buf, binary.BigEndian, &dataLen)
	switch {
	case withData:
		e.Data = make([]byte, dataLen)
		buf.Read(e.Data)
	default:
		if _, err := buf.Seek(int64(dataLen), io.SeekCurrent); err != nil {
			return e, err
		}
	}

	var mimeLen uint32
	binary.Read(buf, binary.BigEndian, &mimeLen)
	mimeBytes := make([]byte, mimeLen)
	buf.Read(mimeBytes)
	e.MimeType = string(mimeBytes)

	var prevLen uint32
	binary.Read(buf, binary.BigEndian, &prevLen)
	prevBytes := make([]byte, prevLen)
	buf.Read(prevBytes)
	e.Preview = string(prevBytes)

	var size int32
	binary.Read(buf, binary.BigEndian, &size)
	e.Size = int(size)

	var timestamp int64
	binary.Read(buf, binary.BigEndian, &timestamp)
	// Rows written before the switch to nanosecond precision hold seconds;
	// no second-resolution stamp reaches 1e12 until the year 33658.
	if timestamp < 1e12 {
		e.Timestamp = time.Unix(timestamp, 0)
	} else {
		e.Timestamp = time.Unix(0, timestamp)
	}

	var isImage byte
	binary.Read(buf, binary.BigEndian, &isImage)
	e.IsImage = isImage == 1

	if buf.Len() >= 8 {
		binary.Read(buf, binary.BigEndian, &e.Hash)
	}

	if buf.Len() >= 1 {
		var pinnedByte byte
		binary.Read(buf, binary.BigEndian, &pinnedByte)
		e.Pinned = pinnedByte == 1
	}

	if buf.Len() >= 4 {
		var altMimeLen uint32
		binary.Read(buf, binary.BigEndian, &altMimeLen)
		altMimeBytes := make([]byte, altMimeLen)
		buf.Read(altMimeBytes)
		e.AltMimeType = string(altMimeBytes)

		var altDataLen uint32
		binary.Read(buf, binary.BigEndian, &altDataLen)
		if withData {
			e.AltData = make([]byte, altDataLen)
			buf.Read(e.AltData)
		}
	}

	return e, nil
}

func itob(v uint64) []byte {
	b := make([]byte, 8)
	binary.BigEndian.PutUint64(b, v)
	return b
}

func computeHash(data []byte) uint64 {
	h := fnv.New64a()
	h.Write(data)
	return h.Sum64()
}

func extractHash(data []byte) uint64 {
	buf := bytes.NewReader(data)
	if _, err := buf.Seek(8, io.SeekStart); err != nil {
		return 0
	}
	for range 3 { // data, mime type, preview
		var length uint32
		if binary.Read(buf, binary.BigEndian, &length) != nil {
			return 0
		}
		if _, err := buf.Seek(int64(length), io.SeekCurrent); err != nil {
			return 0
		}
	}
	if _, err := buf.Seek(4+8+1, io.SeekCurrent); err != nil { // size, timestamp, isImage
		return 0
	}
	var hash uint64
	if binary.Read(buf, binary.BigEndian, &hash) != nil {
		return 0
	}
	return hash
}

func (m *Manager) hasSensitiveMimeType(mimes []string) bool {
	return slices.ContainsFunc(mimes, func(mime string) bool {
		return slices.Contains(sensitiveMimeTypes, mime)
	})
}

func (m *Manager) selectMimeType(mimes []string) string {
	preferredTypes := []string{
		"text/uri-list",
		"image/png",
		"image/jpeg",
		"image/gif",
		"image/bmp",
		"image/tiff",
		"text/plain;charset=utf-8",
		"text/plain",
		"UTF8_STRING",
		"STRING",
		"TEXT",
	}

	for _, pref := range preferredTypes {
		for _, mime := range mimes {
			if mime == pref {
				return mime
			}
		}
	}

	// Skip useless MIME types when falling back
	for _, mime := range mimes {
		switch mime {
		case "application/vnd.portal.filetransfer":
			continue
		default:
			return mime
		}
	}

	return ""
}

var altTextMimeTypes = []string{
	"text/plain;charset=utf-8",
	"text/plain",
	"UTF8_STRING",
	"STRING",
	"TEXT",
}

func selectAltTextMimeType(mimes []string) string {
	for _, pref := range altTextMimeTypes {
		if slices.Contains(mimes, pref) {
			return pref
		}
	}
	return ""
}

func isTextMimeType(mime string) bool {
	if mime == "" || strings.HasPrefix(mime, "text/plain") {
		return true
	}
	return slices.Contains(altTextMimeTypes, mime)
}

func (m *Manager) isImageMimeType(mime string) bool {
	return strings.HasPrefix(mime, "image/")
}

func (m *Manager) textPreview(data []byte) string {
	text := string(data)
	text = strings.TrimSpace(text)
	text = strings.Join(strings.Fields(text), " ")

	if len(text) > 100 {
		return text[:100] + "…"
	}
	return text
}

func (m *Manager) imagePreview(data []byte, format string) string {
	config, imgFmt, err := image.DecodeConfig(bytes.NewReader(data))
	if err != nil {
		return fmt.Sprintf("[[ image %s %s ]]", sizeStr(len(data)), format)
	}
	return fmt.Sprintf("[[ image %s %s %dx%d ]]", sizeStr(len(data)), imgFmt, config.Width, config.Height)
}

// URI convention: what we store and what we offer on the clipboard are always
// percent-encoded file:// URIs; every read path decodes exactly once through
// pathFromFileURI, so encode and decode stay a true round-trip.
func encodeFileURI(path string) string {
	return (&url.URL{Scheme: "file", Path: path}).String()
}

// pathFromFileURI strips the file:// prefix and decodes once. A raw "%" that
// was never encoded (invalid escape) falls back to the raw remainder rather
// than mangling a real path.
func pathFromFileURI(uri string) string {
	path, ok := strings.CutPrefix(uri, "file://")
	if !ok {
		return ""
	}
	if decoded, err := url.PathUnescape(path); err == nil {
		return decoded
	}
	return path
}

func (m *Manager) uriListPreview(data []byte) (string, bool) {
	text := strings.TrimSpace(string(data))
	uris := strings.Split(text, "\r\n")
	if len(uris) == 0 {
		uris = strings.Split(text, "\n")
	}

	if len(uris) > 1 {
		return fmt.Sprintf("[[ %d files ]]", len(uris)), false
	}

	if len(uris) == 1 && strings.HasPrefix(uris[0], "file://") {
		filePath := pathFromFileURI(uris[0])
		info, err := os.Stat(filePath)
		if err != nil || info.IsDir() {
			return m.textPreview(data), false
		}

		cfg := m.getConfig()
		if info.Size() <= cfg.MaxEntrySize {
			if imgData, err := os.ReadFile(filePath); err == nil {
				if config, imgFmt, err := image.DecodeConfig(bytes.NewReader(imgData)); err == nil {
					return fmt.Sprintf("[[ file %s %s %dx%d ]]", filepath.Base(filePath), imgFmt, config.Width, config.Height), true
				}
			}
		}
		return fmt.Sprintf("[[ file %s ]]", filepath.Base(filePath)), false
	}

	return m.textPreview(data), false
}

func (m *Manager) tryReadImageFromURI(data []byte) ([]byte, string, bool) {
	text := strings.TrimSpace(string(data))
	uris := strings.Split(text, "\r\n")
	if len(uris) == 0 {
		uris = strings.Split(text, "\n")
	}

	if len(uris) != 1 || !strings.HasPrefix(uris[0], "file://") {
		return nil, "", false
	}

	filePath := pathFromFileURI(uris[0])
	info, err := os.Stat(filePath)
	if err != nil || info.IsDir() {
		return nil, "", false
	}

	cfg := m.getConfig()
	if info.Size() > cfg.MaxEntrySize {
		return nil, "", false
	}

	imgData, err := os.ReadFile(filePath)
	if err != nil {
		return nil, "", false
	}

	_, imgFmt, err := image.DecodeConfig(bytes.NewReader(imgData))
	if err != nil {
		return nil, "", false
	}

	return imgData, "image/" + imgFmt, true
}

func sizeStr(size int) string {
	units := []string{"B", "KiB", "MiB"}
	var i int
	fsize := float64(size)
	for fsize >= 1024 && i < len(units)-1 {
		fsize /= 1024
		i++
	}
	return fmt.Sprintf("%.0f %s", fsize, units[i])
}

func (m *Manager) updateState() {
	history := m.GetHistory()

	var current *Entry
	if len(history) > 0 {
		c := history[0]
		current = &c
	}

	newState := &State{
		Enabled: m.alive,
		History: history,
		Current: current,
	}

	m.stateMutex.Lock()
	m.state = newState
	m.stateMutex.Unlock()
}

func (m *Manager) notifier() {
	defer m.notifierWg.Done()

	for range m.dirty {
		state := m.GetState()

		if m.lastState != nil && stateEqual(m.lastState, &state) {
			continue
		}

		m.lastState = &state

		m.subMutex.RLock()
		subs := make([]chan State, 0, len(m.subscribers))
		for _, ch := range m.subscribers {
			subs = append(subs, ch)
		}
		m.subMutex.RUnlock()

		for _, ch := range subs {
			select {
			case ch <- state:
			default:
			}
		}
	}
}

func stateEqual(a, b *State) bool {
	if a == nil || b == nil {
		return false
	}
	if a.Enabled != b.Enabled {
		return false
	}
	if len(a.History) != len(b.History) {
		return false
	}
	for i := range a.History {
		if !entryStateEqual(a.History[i], b.History[i]) {
			return false
		}
	}
	return true
}

func entryStateEqual(a, b Entry) bool {
	return a.ID == b.ID &&
		a.Hash == b.Hash &&
		a.Pinned == b.Pinned &&
		a.IsImage == b.IsImage &&
		a.MimeType == b.MimeType &&
		a.Preview == b.Preview &&
		a.Size == b.Size &&
		a.Timestamp.Equal(b.Timestamp)
}

func (m *Manager) GetHistory() []Entry {
	if m.db == nil {
		return nil
	}

	cfg := m.getConfig()
	var cutoff time.Time
	if cfg.AutoClearDays > 0 {
		cutoff = time.Now().AddDate(0, 0, -cfg.AutoClearDays)
	}

	var history []Entry
	var stale []uint64

	if err := m.dbView(func(tx *bolt.Tx) error {
		b := tx.Bucket([]byte("clipboard"))
		if b == nil {
			return nil
		}
		c := b.Cursor()

		for k, v := c.Last(); k != nil; k, v = c.Prev() {
			entry, err := decodeEntryMeta(v)
			if err != nil {
				continue
			}
			if !cutoff.IsZero() && entry.Timestamp.Before(cutoff) {
				stale = append(stale, entry.ID)
				continue
			}
			history = append(history, entry)
		}
		return nil
	}); err != nil {
		log.Errorf("Failed to read clipboard history: %v", err)
	}

	if len(stale) > 0 {
		go m.deleteStaleEntries(stale)
	}

	sortEntriesNewestFirst(history)

	return history
}

// sortEntriesNewestFirst orders by timestamp, falling back to id: TouchEntry
// rewrites a row in place to keep its id stable, so bucket key order stops
// tracking recency.
func sortEntriesNewestFirst(entries []Entry) {
	slices.SortFunc(entries, compareEntriesNewestFirst)
}

func compareEntriesNewestFirst(a, b Entry) int {
	if c := b.Timestamp.Compare(a.Timestamp); c != 0 {
		return c
	}
	return cmp.Compare(b.ID, a.ID)
}

func (m *Manager) deleteStaleEntries(ids []uint64) {
	if m.db == nil {
		return
	}

	if err := m.dbUpdate(func(tx *bolt.Tx) error {
		b := tx.Bucket([]byte("clipboard"))
		if b == nil {
			return nil
		}
		for _, id := range ids {
			if err := b.Delete(itob(id)); err != nil {
				log.Errorf("Failed to delete stale entry %d: %v", id, err)
			}
		}
		return nil
	}); err != nil {
		log.Errorf("Failed to delete stale entries: %v", err)
	}
}

func (m *Manager) GetEntry(id uint64) (*Entry, error) {
	if m.db == nil {
		return nil, fmt.Errorf("database not available")
	}

	var entry Entry
	var found bool

	err := m.dbView(func(tx *bolt.Tx) error {
		b := tx.Bucket([]byte("clipboard"))
		if b == nil {
			return nil
		}
		v := b.Get(itob(id))
		if v == nil {
			return nil
		}

		var err error
		entry, err = decodeEntry(v)
		if err != nil {
			return err
		}
		found = true
		return nil
	})

	if err != nil {
		return nil, err
	}
	if !found {
		return nil, errEntryNotFound
	}

	return &entry, nil
}

func (m *Manager) DeleteEntry(id uint64) error {
	if m.db == nil {
		return fmt.Errorf("database not available")
	}

	err := m.dbUpdate(func(tx *bolt.Tx) error {
		b := tx.Bucket([]byte("clipboard"))
		if b == nil {
			return nil
		}
		return b.Delete(itob(id))
	})

	if err == nil {
		m.updateState()
		m.notifySubscribers()
	}

	return err
}

// DeleteEntries removes several entries in one transaction and reports how many
// were actually deleted. Pinned entries are skipped: a bulk delete must never be
// able to take out saved items.
func (m *Manager) DeleteEntries(ids []uint64) (int, error) {
	if m.db == nil {
		return 0, fmt.Errorf("database not available")
	}
	if len(ids) == 0 {
		return 0, nil
	}

	deleted := 0
	err := m.dbUpdate(func(tx *bolt.Tx) error {
		b := tx.Bucket([]byte("clipboard"))
		if b == nil {
			return nil
		}
		for _, id := range ids {
			key := itob(id)
			v := b.Get(key)
			if v == nil {
				continue
			}
			if entry, err := decodeEntryMeta(v); err == nil && entry.Pinned {
				continue
			}
			if err := b.Delete(key); err != nil {
				return err
			}
			deleted++
		}
		return nil
	})

	if err != nil {
		return 0, err
	}

	if deleted > 0 {
		m.updateState()
		m.notifySubscribers()
	}

	return deleted, nil
}

func (m *Manager) TouchEntry(id uint64) error {
	if m.db == nil {
		return fmt.Errorf("database not available")
	}

	entry, err := m.GetEntry(id)
	if err != nil {
		return err
	}

	// Round(0) drops the monotonic reading so the in-memory stamp compares the
	// same way as the one decoded back from the bucket.
	entry.Timestamp = time.Now().Round(0)

	// storeEntry would dedupe the row against itself and hand out a fresh
	// sequence number, invalidating the id the UI is still holding.
	err = m.dbUpdate(func(tx *bolt.Tx) error {
		b := tx.Bucket([]byte("clipboard"))
		if b == nil {
			return fmt.Errorf("clipboard bucket missing")
		}
		encoded, err := encodeEntry(*entry)
		if err != nil {
			return err
		}
		return b.Put(itob(id), encoded)
	})
	if err != nil {
		return err
	}

	m.updateState()
	m.notifySubscribers()

	return nil
}

func (m *Manager) CreateHistoryEntryFromPinned(pinnedEntry *Entry) error {
	if m.db == nil {
		return fmt.Errorf("database not available")
	}

	// Create a new unpinned entry with the same data
	newEntry := Entry{
		Data:        pinnedEntry.Data,
		MimeType:    pinnedEntry.MimeType,
		Size:        pinnedEntry.Size,
		Timestamp:   time.Now(),
		IsImage:     pinnedEntry.IsImage,
		Preview:     pinnedEntry.Preview,
		Pinned:      false,
		AltData:     pinnedEntry.AltData,
		AltMimeType: pinnedEntry.AltMimeType,
	}

	if err := m.storeEntry(newEntry); err != nil {
		return err
	}

	m.updateState()
	m.notifySubscribers()

	return nil
}

func (m *Manager) ClearHistory() {
	if m.db == nil {
		return
	}

	// Delete only non-pinned entries
	if err := m.dbUpdate(func(tx *bolt.Tx) error {
		b := tx.Bucket([]byte("clipboard"))
		if b == nil {
			return nil
		}

		var toDelete [][]byte
		c := b.Cursor()
		for k, v := c.First(); k != nil; k, v = c.Next() {
			entry, err := decodeEntryMeta(v)
			if err != nil || !entry.Pinned {
				toDelete = append(toDelete, k)
			}
		}

		for _, k := range toDelete {
			if err := b.Delete(k); err != nil {
				return err
			}
		}
		return nil
	}); err != nil {
		log.Errorf("Failed to clear clipboard history: %v", err)
		return
	}

	pinnedCount := 0
	if err := m.dbView(func(tx *bolt.Tx) error {
		b := tx.Bucket([]byte("clipboard"))
		if b != nil {
			c := b.Cursor()
			for k, v := c.First(); k != nil; k, v = c.Next() {
				entry, _ := decodeEntryMeta(v)
				if entry.Pinned {
					pinnedCount++
				}
			}
		}
		return nil
	}); err != nil {
		log.Errorf("Failed to count pinned entries: %v", err)
	}

	if pinnedCount == 0 {
		if err := m.compactDB(); err != nil {
			log.Errorf("Failed to compact database: %v", err)
		}
	}

	m.updateState()
	m.notifySubscribers()
}

func (m *Manager) compactDB() error {
	m.db.Close()

	tmpPath := m.dbPath + ".compact"
	defer os.Remove(tmpPath)

	if err := compactInto(m.dbPath, tmpPath, 0); err != nil {
		m.reopenDB()
		return err
	}

	if err := os.Rename(tmpPath, m.dbPath); err != nil {
		m.reopenDB()
		return fmt.Errorf("rename: %w", err)
	}

	m.reopenDB()
	if m.db == nil {
		return fmt.Errorf("reopen failed")
	}

	return nil
}

func compactInto(srcPath, dstPath string, txMaxSize int64) (err error) {
	defer recoverDBPanic(&err)
	defer armDBFaultPanics()()

	srcDB, err := bolt.Open(srcPath, 0o644, &bolt.Options{ReadOnly: true, Timeout: time.Second})
	if err != nil {
		return fmt.Errorf("open source: %w", err)
	}
	defer srcDB.Close()

	dstDB, err := bolt.Open(dstPath, 0o644, &bolt.Options{Timeout: time.Second})
	if err != nil {
		return fmt.Errorf("open destination: %w", err)
	}
	defer dstDB.Close()

	if err := bolt.Compact(dstDB, srcDB, txMaxSize); err != nil {
		return fmt.Errorf("compact: %w", err)
	}
	return nil
}

func (m *Manager) reopenDB() {
	db, err := openDB(m.dbPath)
	if err != nil {
		log.Errorf("Failed to reopen clipboard db: %v", err)
		m.db = nil
		return
	}
	m.db = db
}

var (
	errSelectionUnavailable = errors.New("clipboard selection unavailable: tracking disabled or no data control protocol")
	errTrackingDisabled     = errors.New("clipboard tracking disabled")
)

// A disabled manager still serves copy requests; failing here lets callers
// such as dms screenshot fall back to their own copy.
func (m *Manager) canTakeSelection() bool {
	return m.deviceBound.Load() && !m.getConfig().Disabled
}

func (m *Manager) SetClipboard(data []byte, mimeType string) error {
	if !m.canTakeSelection() {
		return errSelectionUnavailable
	}
	if int64(len(data)) > m.getConfig().MaxEntrySize {
		return fmt.Errorf("data too large")
	}

	dataCopy := make([]byte, len(data))
	copy(dataCopy, data)

	m.takeSelection(wlclipboard.ExpandOffers(dataCopy, mimeType))
	return nil
}

// SetClipboardEntry takes the selection serving the entry's primary
// representation plus its stored alternate, so history restores keep
// both the text and image sides pasteable.
func (m *Manager) SetClipboardEntry(entry *Entry) error {
	if !m.canTakeSelection() {
		return errSelectionUnavailable
	}
	if int64(len(entry.Data)) > m.getConfig().MaxEntrySize {
		return fmt.Errorf("data too large")
	}

	offers := wlclipboard.ExpandOffers(slices.Clone(entry.Data), entry.MimeType)
	if entry.AltMimeType != "" {
		offers = append(offers, wlclipboard.ExpandOffers(slices.Clone(entry.AltData), entry.AltMimeType)...)
	}

	m.takeSelection(offers)
	return nil
}

const selectionWriteTimeout = 30 * time.Second

// Runs off the shared dispatcher: a receiver that never drains its pipe
// would otherwise stall every Wayland event in the daemon.
func writeSelection(fd int, data []byte, timeout time.Duration) {
	_ = syscall.SetNonblock(fd, true)
	file := os.NewFile(uintptr(fd), "clipboard-pipe")
	defer file.Close()

	_ = file.SetWriteDeadline(time.Now().Add(timeout))
	if _, err := file.Write(data); err != nil {
		log.Errorf("Failed to write clipboard data: %v", err)
	}
}

// takeSelection makes the daemon the selection owner, serving the given
// offers until another client claims the clipboard.
func (m *Manager) takeSelection(offers []wlclipboard.Offer) {
	m.post(func() {
		if m.dataControlMgr == nil || m.dataDevice == nil {
			log.Error("Data control manager or device not initialized")
			return
		}

		dataMgr := m.dataControlMgr.(*ext_data_control.ExtDataControlManagerV1)

		source, err := dataMgr.CreateDataSource()
		if err != nil {
			log.Errorf("Failed to create data source: %v", err)
			return
		}

		offerData := make(map[string][]byte, len(offers))
		for _, offer := range offers {
			if err := source.Offer(offer.MimeType); err != nil {
				log.Errorf("Failed to offer %s: %v", offer.MimeType, err)
				return
			}
			offerData[offer.MimeType] = offer.Data
		}

		source.SetSendHandler(func(e ext_data_control.ExtDataControlSourceV1SendEvent) {
			data, ok := offerData[e.MimeType]
			if !ok {
				syscall.Close(e.Fd)
				return
			}
			go writeSelection(e.Fd, data, selectionWriteTimeout)
		})

		source.SetCancelledHandler(func(e ext_data_control.ExtDataControlSourceV1CancelledEvent) {
			m.ownerLock.Lock()
			m.isOwner = false
			m.ownerLock.Unlock()
		})

		m.releaseCurrentSource()
		m.currentSource = source

		m.ownerLock.Lock()
		m.isOwner = true
		m.ownerLock.Unlock()

		device := m.dataDevice.(*ext_data_control.ExtDataControlDeviceV1)
		if err := device.SetSelection(source); err != nil {
			log.Errorf("Failed to set selection: %v", err)
		}
	})
}

func (m *Manager) CopyText(text string) error {
	if err := m.SetClipboard([]byte(text), "text/plain;charset=utf-8"); err != nil {
		return err
	}

	entry := Entry{
		Data:      []byte(text),
		MimeType:  "text/plain;charset=utf-8",
		Size:      len(text),
		Timestamp: time.Now(),
		IsImage:   false,
		Preview:   m.textPreview([]byte(text)),
	}

	if err := m.storeEntry(entry); err != nil {
		log.Errorf("Failed to store clipboard entry: %v", err)
	}

	m.updateState()
	m.notifySubscribers()

	return nil
}

func (m *Manager) PasteText() (string, error) {
	history := m.GetHistory()
	if len(history) == 0 {
		return "", fmt.Errorf("no clipboard data available")
	}

	entry := history[0]

	fullEntry, err := m.GetEntry(entry.ID)
	if err != nil {
		return "", err
	}

	switch {
	case !fullEntry.IsImage:
		return string(fullEntry.Data), nil
	case fullEntry.AltMimeType != "":
		return string(fullEntry.AltData), nil
	default:
		return "", fmt.Errorf("clipboard contains image, not text")
	}
}

func (m *Manager) Close() {
	if !m.alive {
		return
	}

	m.alive = false
	close(m.stopChan)

	close(m.dirty)
	m.notifierWg.Wait()

	m.subMutex.Lock()
	for _, ch := range m.subscribers {
		close(ch)
	}
	m.subscribers = make(map[string]chan State)
	m.subMutex.Unlock()

	m.releaseCurrentSource()
	m.releaseDataDevice()

	if m.dataControlMgr != nil {
		mgr := m.dataControlMgr.(*ext_data_control.ExtDataControlManagerV1)
		mgr.Destroy()
	}

	if m.registry != nil {
		m.registry.Destroy()
	}

	if m.db != nil {
		m.db.Close()
	}
}

func (m *Manager) clearHistoryInternal() error {
	return m.dbUpdate(func(tx *bolt.Tx) error {
		if err := tx.DeleteBucket([]byte("clipboard")); err != nil {
			return err
		}
		_, err := tx.CreateBucket([]byte("clipboard"))
		return err
	})
}

func (m *Manager) clearOldEntries(days int) error {
	cutoff := time.Now().AddDate(0, 0, -days)

	return m.dbUpdate(func(tx *bolt.Tx) error {
		b := tx.Bucket([]byte("clipboard"))
		if b == nil {
			return nil
		}

		var toDelete [][]byte
		c := b.Cursor()
		for k, v := c.First(); k != nil; k, v = c.Next() {
			entry, err := decodeEntryMeta(v)
			if err != nil {
				continue
			}
			if entry.Pinned {
				continue
			}
			if entry.Timestamp.Before(cutoff) {
				toDelete = append(toDelete, k)
			}
		}

		for _, k := range toDelete {
			if err := b.Delete(k); err != nil {
				return err
			}
		}
		return nil
	})
}

func (m *Manager) migrateHashes() error {
	if m.db == nil {
		return nil
	}

	var needsMigration bool
	if err := m.dbView(func(tx *bolt.Tx) error {
		b := tx.Bucket([]byte("clipboard"))
		if b == nil {
			return nil
		}
		c := b.Cursor()
		for k, v := c.First(); k != nil; k, v = c.Next() {
			if extractHash(v) == 0 {
				needsMigration = true
				return nil
			}
		}
		return nil
	}); err != nil {
		return err
	}

	if !needsMigration {
		return nil
	}

	log.Info("Migrating clipboard entries to add hashes...")

	return m.dbUpdate(func(tx *bolt.Tx) error {
		b := tx.Bucket([]byte("clipboard"))
		if b == nil {
			return nil
		}

		var updates []struct {
			key   []byte
			entry Entry
		}

		c := b.Cursor()
		for k, v := c.First(); k != nil; k, v = c.Next() {
			entry, err := decodeEntry(v)
			if err != nil {
				continue
			}
			if entry.Hash != 0 {
				continue
			}
			entry.Hash = computeHash(entry.Data)
			keyCopy := make([]byte, len(k))
			copy(keyCopy, k)
			updates = append(updates, struct {
				key   []byte
				entry Entry
			}{keyCopy, entry})
		}

		for _, u := range updates {
			encoded, err := encodeEntry(u.entry)
			if err != nil {
				continue
			}
			if err := b.Put(u.key, encoded); err != nil {
				return err
			}
		}

		log.Infof("Migrated %d clipboard entries", len(updates))
		return nil
	})
}

func (m *Manager) Search(params SearchParams) SearchResult {
	if m.db == nil {
		return SearchResult{}
	}

	if params.Limit <= 0 {
		params.Limit = 50
	}
	if params.Limit > 500 {
		params.Limit = 500
	}

	query := strings.ToLower(params.Query)
	mimeFilter := strings.ToLower(params.MimeType)

	var all []Entry
	if err := m.dbView(func(tx *bolt.Tx) error {
		b := tx.Bucket([]byte("clipboard"))
		if b == nil {
			return nil
		}

		c := b.Cursor()
		for k, v := c.Last(); k != nil; k, v = c.Prev() {
			entry, err := decodeEntryMeta(v)
			if err != nil {
				continue
			}

			if params.IsImage != nil && entry.IsImage != *params.IsImage {
				continue
			}

			if mimeFilter != "" && !strings.Contains(strings.ToLower(entry.MimeType), mimeFilter) {
				continue
			}

			if params.Before != nil && entry.Timestamp.Unix() >= *params.Before {
				continue
			}

			if params.After != nil && entry.Timestamp.Unix() <= *params.After {
				continue
			}

			if query != "" && !strings.Contains(strings.ToLower(entry.Preview), query) {
				continue
			}

			all = append(all, entry)
		}
		return nil
	}); err != nil {
		log.Errorf("Search failed: %v", err)
	}

	total := len(all)

	start := min(params.Offset, total)
	end := min(start+params.Limit, total)

	return SearchResult{
		Entries: all[start:end],
		Total:   total,
		HasMore: end < total,
	}
}

func (m *Manager) SetConfig(cfg Config) error {
	if err := SaveConfig(cfg); err != nil {
		return err
	}
	m.applyConfigChange(cfg)
	return nil
}

func (m *Manager) getConfig() Config {
	m.configMutex.RLock()
	defer m.configMutex.RUnlock()
	return m.config
}

func (m *Manager) watchConfig() {
	if m.configPath == "" {
		return
	}

	watcher, err := fsnotify.NewWatcher()
	if err != nil {
		log.Warnf("Failed to create config watcher: %v", err)
		return
	}
	defer watcher.Close()

	configDir := filepath.Dir(m.configPath)
	if err := watcher.Add(configDir); err != nil {
		log.Warnf("Failed to watch config directory: %v", err)
		return
	}

	for {
		select {
		case <-m.stopChan:
			return
		case event, ok := <-watcher.Events:
			if !ok {
				return
			}
			if event.Name != m.configPath {
				continue
			}
			if event.Op&(fsnotify.Write|fsnotify.Create) == 0 {
				continue
			}
			// os.WriteFile truncates first; parsing that empty read would
			// briefly reset every setting to its default.
			newCfg, err := readConfig()
			if err != nil {
				continue
			}
			m.applyConfigChange(newCfg)
		case err, ok := <-watcher.Errors:
			if !ok {
				return
			}
			log.Warnf("Config watcher error: %v", err)
		}
	}
}

func (m *Manager) applyConfigChange(newCfg Config) {
	m.configMutex.Lock()
	oldCfg := m.config
	m.config = newCfg
	m.configMutex.Unlock()

	if newCfg.Disabled != oldCfg.Disabled {
		log.Infof("Clipboard tracking disabled=%v", newCfg.Disabled)
		m.post(m.syncTracking)
	}

	m.updateState()
	m.notifySubscribers()
}

func (m *Manager) StoreData(data []byte, mimeType string) error {
	cfg := m.getConfig()

	if cfg.Disabled {
		return errTrackingDisabled
	}

	if m.db == nil {
		return fmt.Errorf("database not available")
	}

	if len(data) == 0 {
		return nil
	}

	if int64(len(data)) > cfg.MaxEntrySize {
		return fmt.Errorf("data too large")
	}

	if len(bytes.TrimSpace(data)) == 0 {
		return nil
	}

	entry := Entry{
		Data:      data,
		MimeType:  mimeType,
		Size:      len(data),
		Timestamp: time.Now(),
		IsImage:   m.isImageMimeType(mimeType),
	}

	switch {
	case entry.IsImage:
		entry.Preview = m.imagePreview(data, mimeType)
	case mimeType == "text/uri-list":
		entry.Preview, entry.IsImage = m.uriListPreview(data)
	default:
		entry.Preview = m.textPreview(data)
	}

	if err := m.storeEntry(entry); err != nil {
		return err
	}

	m.updateState()
	m.notifySubscribers()

	return nil
}

func (m *Manager) PinEntry(id uint64) error {
	if m.db == nil {
		return fmt.Errorf("database not available")
	}

	entryToPin, err := m.GetEntry(id)
	if err != nil {
		return err
	}

	var hashExists bool
	if err := m.dbView(func(tx *bolt.Tx) error {
		b := tx.Bucket([]byte("clipboard"))
		if b == nil {
			return nil
		}
		c := b.Cursor()
		for k, v := c.First(); k != nil; k, v = c.Next() {
			entry, err := decodeEntryMeta(v)
			if err != nil || !entry.Pinned {
				continue
			}
			if entry.Hash == entryToPin.Hash {
				hashExists = true
				return nil
			}
		}
		return nil
	}); err != nil {
		return err
	}

	if hashExists {
		return nil
	}

	cfg := m.getConfig()
	pinnedCount := 0
	if err := m.dbView(func(tx *bolt.Tx) error {
		b := tx.Bucket([]byte("clipboard"))
		if b == nil {
			return nil
		}
		c := b.Cursor()
		for k, v := c.First(); k != nil; k, v = c.Next() {
			entry, err := decodeEntryMeta(v)
			if err == nil && entry.Pinned {
				pinnedCount++
			}
		}
		return nil
	}); err != nil {
		log.Errorf("Failed to count pinned entries: %v", err)
	}

	if pinnedCount >= cfg.MaxPinned {
		return fmt.Errorf("maximum pinned entries reached (%d)", cfg.MaxPinned)
	}

	err = m.dbUpdate(func(tx *bolt.Tx) error {
		b := tx.Bucket([]byte("clipboard"))
		if b == nil {
			return fmt.Errorf("entry not found")
		}
		v := b.Get(itob(id))
		if v == nil {
			return fmt.Errorf("entry not found")
		}

		entry, err := decodeEntry(v)
		if err != nil {
			return err
		}

		entry.Pinned = true
		encoded, err := encodeEntry(entry)
		if err != nil {
			return err
		}

		return b.Put(itob(id), encoded)
	})

	if err == nil {
		m.updateState()
		m.notifySubscribers()
	}

	return err
}

func (m *Manager) UnpinEntry(id uint64) error {
	if m.db == nil {
		return fmt.Errorf("database not available")
	}

	err := m.dbUpdate(func(tx *bolt.Tx) error {
		b := tx.Bucket([]byte("clipboard"))
		if b == nil {
			return fmt.Errorf("entry not found")
		}
		v := b.Get(itob(id))
		if v == nil {
			return fmt.Errorf("entry not found")
		}

		entry, err := decodeEntry(v)
		if err != nil {
			return err
		}

		if entry.Pinned {
			currentKey := itob(id)
			var keepKey []byte
			var deleteKeys [][]byte

			c := b.Cursor()
			for k, v := c.Last(); k != nil; k, v = c.Prev() {
				if bytes.Equal(k, currentKey) || extractHash(v) != entry.Hash {
					continue
				}
				duplicate, err := decodeEntryMeta(v)
				if err == nil && !duplicate.Pinned {
					key := append([]byte(nil), k...)
					if keepKey == nil {
						keepKey = key
					} else {
						deleteKeys = append(deleteKeys, key)
					}
				}
			}

			if keepKey != nil {
				for _, key := range deleteKeys {
					if err := b.Delete(key); err != nil {
						return err
					}
				}
				return b.Delete(currentKey)
			}
		}

		entry.Pinned = false
		encoded, err := encodeEntry(entry)
		if err != nil {
			return err
		}

		return b.Put(itob(id), encoded)
	})

	if err == nil {
		m.updateState()
		m.notifySubscribers()
	}

	return err
}

func (m *Manager) EditEntry(id uint64, text string) error {
	if m.db == nil {
		return fmt.Errorf("database not available")
	}

	data := []byte(text)
	mimeType := "text/plain;charset=utf-8"

	if len(bytes.TrimSpace(data)) == 0 {
		return fmt.Errorf("cannot save empty entry")
	}

	cfg := m.getConfig()
	if int64(len(data)) > cfg.MaxEntrySize {
		return fmt.Errorf("data too large")
	}

	newHash := computeHash(data)
	preview := m.textPreview(data)

	err := m.dbUpdate(func(tx *bolt.Tx) error {
		b := tx.Bucket([]byte("clipboard"))
		if b == nil {
			return fmt.Errorf("clipboard bucket missing")
		}

		oldKey := itob(id)
		v := b.Get(oldKey)
		if v == nil {
			return errEntryNotFound
		}

		existing, err := decodeEntry(v)
		if err != nil {
			return err
		}

		if existing.IsImage {
			return errors.New("cannot edit image entry")
		}

		if !isTextMimeType(existing.MimeType) {
			return errors.New("cannot edit non-text entry")
		}

		wasPinned := existing.Pinned

		if err := b.Delete(oldKey); err != nil {
			return err
		}

		if err := m.deduplicateInTx(b, newHash); err != nil {
			return err
		}

		if wasPinned {
			c := b.Cursor()
			for k, val := c.First(); k != nil; k, val = c.Next() {
				if extractHash(val) == newHash {
					meta, err := decodeEntryMeta(val)
					if err == nil && meta.Pinned {
						return nil
					}
				}
			}
		}

		newID, err := b.NextSequence()
		if err != nil {
			return err
		}

		newEntry := Entry{
			ID:        newID,
			Data:      data,
			MimeType:  mimeType,
			Preview:   preview,
			Size:      len(data),
			Timestamp: time.Now(),
			IsImage:   false,
			Hash:      newHash,
			Pinned:    wasPinned,
		}

		encoded, err := encodeEntry(newEntry)
		if err != nil {
			return err
		}

		if err := b.Put(itob(newID), encoded); err != nil {
			return err
		}

		return m.trimLengthInTx(b)
	})

	if err == nil {
		if clipErr := m.SetClipboard(data, mimeType); clipErr != nil {
			log.Errorf("Failed to set clipboard selection: %v", clipErr)
		}
		m.updateState()
		m.notifySubscribers()
	}

	return err
}

func (m *Manager) GetPinnedEntries() []Entry {
	if m.db == nil {
		return nil
	}

	var pinned []Entry
	if err := m.dbView(func(tx *bolt.Tx) error {
		b := tx.Bucket([]byte("clipboard"))
		if b == nil {
			return nil
		}

		c := b.Cursor()
		for k, v := c.Last(); k != nil; k, v = c.Prev() {
			entry, err := decodeEntryMeta(v)
			if err != nil {
				continue
			}
			if entry.Pinned {
				pinned = append(pinned, entry)
			}
		}
		return nil
	}); err != nil {
		log.Errorf("Failed to get pinned entries: %v", err)
	}

	sortEntriesNewestFirst(pinned)

	return pinned
}

func (m *Manager) GetPinnedCount() int {
	if m.db == nil {
		return 0
	}

	count := 0
	if err := m.dbView(func(tx *bolt.Tx) error {
		b := tx.Bucket([]byte("clipboard"))
		if b == nil {
			return nil
		}

		c := b.Cursor()
		for k, v := c.First(); k != nil; k, v = c.Next() {
			entry, err := decodeEntryMeta(v)
			if err == nil && entry.Pinned {
				count++
			}
		}
		return nil
	}); err != nil {
		log.Errorf("Failed to count pinned entries: %v", err)
	}

	return count
}

func (m *Manager) CopyFile(filePath string) error {
	if !m.canTakeSelection() {
		return errSelectionUnavailable
	}
	fileInfo, err := os.Stat(filePath)
	if err != nil {
		return fmt.Errorf("file not found: %w", err)
	}

	cfg := m.getConfig()
	// Files over MaxEntrySize are no longer read into memory (this used to
	// fail the copy outright): the uri-list / plain path offers below let the
	// paste target read the file itself, and the image probe size-guards
	// internally.
	var fileData []byte
	if !fileInfo.IsDir() && fileInfo.Size() <= cfg.MaxEntrySize {
		fileData, err = os.ReadFile(filePath)
		if err != nil {
			return fmt.Errorf("read file: %w", err)
		}
	}

	exportedPath, err := m.ExportFileForFlatpak(filePath)
	if err != nil {
		exportedPath = filePath
	}

	if imgData, imgMime, ok := m.tryReadImageFromURI([]byte(encodeFileURI(filePath))); ok {
		entry := Entry{
			Data:      imgData,
			MimeType:  imgMime,
			Size:      len(imgData),
			Timestamp: time.Now(),
			IsImage:   true,
			Preview:   m.imagePreview(imgData, imgMime),
		}
		if err := m.storeEntry(entry); err != nil {
			log.Errorf("Failed to store file entry: %v", err)
		}
	} else {
		entryData := fileData
		if entryData == nil {
			// Oversized: store the encoded URI instead of the body so the
			// entry can be restored through EntryToFile later.
			entryData = []byte(encodeFileURI(filePath) + "\r\n")
		}
		entry := Entry{
			Data:      entryData,
			MimeType:  "text/uri-list",
			Size:      len(entryData),
			Timestamp: time.Now(),
			IsImage:   false,
			Preview:   fmt.Sprintf("[[ file %s ]]", filepath.Base(filePath)),
		}
		if err := m.storeEntry(entry); err != nil {
			log.Errorf("Failed to store file entry: %v", err)
		}
	}

	m.updateState()
	m.notifySubscribers()

	m.takeSelection(clipboardstore.FileOffers(exportedPath, filePath, fileData))
	return nil
}

func (m *Manager) EntryToFile(entry *Entry) string {
	switch {
	case entry.MimeType == "text/uri-list":
		data := strings.TrimSpace(string(entry.Data))
		lines := strings.Split(data, "\n")
		if len(lines) == 0 {
			return ""
		}
		uri := strings.TrimSuffix(strings.TrimSpace(lines[0]), "\r")
		if strings.HasPrefix(uri, "file://") {
			return pathFromFileURI(uri)
		}
	case entry.IsImage:
		ext := ".png"
		if suffix, ok := strings.CutPrefix(entry.MimeType, "image/"); ok {
			ext = "." + suffix
		}
		cacheDir, err := os.UserCacheDir()
		if err != nil {
			return ""
		}
		clipDir := filepath.Join(cacheDir, "dms", "clipboard")
		if err := os.MkdirAll(clipDir, 0o755); err != nil {
			return ""
		}
		filePath := filepath.Join(clipDir, fmt.Sprintf("%d%s", time.Now().UnixNano(), ext))
		if os.WriteFile(filePath, entry.Data, 0o644) != nil {
			return ""
		}
		return filePath
	}
	return ""
}

func (m *Manager) dbusConnForFlatpak() (*dbus.Conn, error) {
	m.dbusConnMutex.Lock()
	defer m.dbusConnMutex.Unlock()

	if m.dbusConn != nil {
		return m.dbusConn, nil
	}

	conn, err := dbus.SessionBus()
	if err != nil {
		return nil, fmt.Errorf("connect session bus: %w", err)
	}
	if !conn.SupportsUnixFDs() {
		return nil, fmt.Errorf("D-Bus connection does not support Unix FD passing")
	}
	m.dbusConn = conn
	return conn, nil
}

func (m *Manager) ExportFileForFlatpak(filePath string) (string, error) {
	if _, err := os.Stat(filePath); err != nil {
		return "", fmt.Errorf("file not found: %w", err)
	}

	dbusConn, err := m.dbusConnForFlatpak()
	if err != nil {
		return "", err
	}

	file, err := os.Open(filePath)
	if err != nil {
		return "", fmt.Errorf("open file: %w", err)
	}
	fd := int(file.Fd())

	portal := dbusConn.Object("org.freedesktop.portal.Documents", "/org/freedesktop/portal/documents")

	var docIds []string
	var extra map[string]dbus.Variant
	flags := uint32(0)

	err = portal.Call(
		"org.freedesktop.portal.Documents.AddFull",
		0,
		[]dbus.UnixFD{dbus.UnixFD(fd)},
		flags,
		"",
		[]string{},
	).Store(&docIds, &extra)

	file.Close()

	if err != nil {
		return "", fmt.Errorf("AddFull: %w", err)
	}

	if len(docIds) == 0 {
		return "", fmt.Errorf("no doc IDs returned")
	}

	docId := docIds[0]

	for _, app := range getInstalledFlatpaks() {
		_ = portal.Call(
			"org.freedesktop.portal.Documents.GrantPermissions",
			0,
			docId,
			app,
			[]string{"read"},
		).Err
	}

	uid := os.Getuid()
	basename := filepath.Base(filePath)
	exportedPath := fmt.Sprintf("/run/user/%d/doc/%s/%s", uid, docId, basename)

	return exportedPath, nil
}

func getInstalledFlatpaks() []string {
	out, err := exec.Command("flatpak", "list", "--app", "--columns=application").Output()
	if err != nil {
		return nil
	}

	var apps []string
	for line := range strings.SplitSeq(strings.TrimSpace(string(out)), "\n") {
		if app := strings.TrimSpace(line); app != "" {
			apps = append(apps, app)
		}
	}
	return apps
}
