package clipboard

import (
	"bytes"
	"encoding/binary"
	"fmt"
	"image"
	_ "image/gif"
	_ "image/jpeg"
	_ "image/png"
	"os"
	"path/filepath"
	"strings"
	"time"

	_ "golang.org/x/image/bmp"
	_ "golang.org/x/image/tiff"
	"hash/fnv"

	bolt "go.etcd.io/bbolt"
)

type StoreConfig struct {
	MaxHistory   int
	MaxEntrySize int64
}

func DefaultStoreConfig() StoreConfig {
	return StoreConfig{
		MaxHistory:   100,
		MaxEntrySize: 5 * 1024 * 1024,
	}
}

type Entry struct {
	ID        uint64
	Data      []byte
	MimeType  string
	Preview   string
	Size      int
	Timestamp time.Time
	IsImage   bool
	Hash      uint64
}

func Store(data []byte, mimeType string) error {
	return StoreWithConfig(data, mimeType, DefaultStoreConfig())
}

func StoreWithConfig(data []byte, mimeType string, cfg StoreConfig) (err error) {
	defer func() {
		r := recover()
		if r == nil {
			return
		}
		err = fmt.Errorf("clipboard db panic: %v", r)
	}()

	if len(data) == 0 {
		return nil
	}
	if int64(len(data)) > cfg.MaxEntrySize {
		return fmt.Errorf("data too large: %d > %d", len(data), cfg.MaxEntrySize)
	}

	dbPath, err := GetDBPath()
	if err != nil {
		return fmt.Errorf("get db path: %w", err)
	}

	db, err := bolt.Open(dbPath, 0o644, &bolt.Options{Timeout: 1 * time.Second})
	if err != nil {
		return fmt.Errorf("open db: %w", err)
	}
	defer db.Close()

	entry := Entry{
		Data:      data,
		MimeType:  mimeType,
		Size:      len(data),
		Timestamp: time.Now(),
		IsImage:   IsImageMimeType(mimeType),
		Hash:      computeHash(data),
	}

	switch {
	case entry.IsImage:
		entry.Preview = imagePreview(data, mimeType)
	default:
		entry.Preview = textPreview(data)
	}

	return db.Update(func(tx *bolt.Tx) error {
		b, err := tx.CreateBucketIfNotExists([]byte("clipboard"))
		if err != nil {
			return err
		}

		if err := deduplicateInTx(b, entry.Hash); err != nil {
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

		return trimLengthInTx(b, cfg.MaxHistory)
	})
}

func GetDBPath() (string, error) {
	cacheDir, err := os.UserCacheDir()
	if err != nil {
		homeDir, err := os.UserHomeDir()
		if err != nil {
			return "", err
		}
		cacheDir = filepath.Join(homeDir, ".cache")
	}

	newDir := filepath.Join(cacheDir, "dms", "clipboard")
	newPath := filepath.Join(newDir, "db")

	if _, err := os.Stat(newPath); err == nil {
		return newPath, nil
	}

	oldDir := filepath.Join(cacheDir, "dms-clipboard")
	oldPath := filepath.Join(oldDir, "db")

	if _, err := os.Stat(oldPath); err == nil {
		if err := os.MkdirAll(newDir, 0o700); err != nil {
			return "", err
		}
		if err := os.Rename(oldPath, newPath); err != nil {
			return "", err
		}
		os.Remove(oldDir)
		return newPath, nil
	}

	if err := os.MkdirAll(newDir, 0o700); err != nil {
		return "", err
	}
	return newPath, nil
}

func deduplicateInTx(b *bolt.Bucket, hash uint64) error {
	c := b.Cursor()
	for k, v := c.Last(); k != nil; k, v = c.Prev() {
		if extractHash(v) != hash {
			continue
		}
		if err := b.Delete(k); err != nil {
			return err
		}
	}
	return nil
}

func trimLengthInTx(b *bolt.Bucket, maxHistory int) error {
	c := b.Cursor()
	var count int
	for k, _ := c.Last(); k != nil; k, _ = c.Prev() {
		if count < maxHistory {
			count++
			continue
		}
		if err := b.Delete(k); err != nil {
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
	binary.Write(buf, binary.BigEndian, e.Timestamp.Unix())
	if e.IsImage {
		buf.WriteByte(1)
	} else {
		buf.WriteByte(0)
	}
	binary.Write(buf, binary.BigEndian, e.Hash)

	return buf.Bytes(), nil
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
	if len(data) < 8 {
		return 0
	}
	return binary.BigEndian.Uint64(data[len(data)-8:])
}

func textPreview(data []byte) string {
	text := string(data)
	text = strings.TrimSpace(text)
	text = strings.Join(strings.Fields(text), " ")

	if len(text) > 100 {
		return text[:100] + "…"
	}
	return text
}

func imagePreview(data []byte, format string) string {
	config, imgFmt, err := image.DecodeConfig(bytes.NewReader(data))
	if err != nil {
		return fmt.Sprintf("[[ image %s %s ]]", sizeStr(len(data)), format)
	}
	return fmt.Sprintf("[[ image %s %s %dx%d ]]", sizeStr(len(data)), imgFmt, config.Width, config.Height)
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
