package server

import (
	"strings"

	"github.com/duxlabs-dev/dux-go/files"
	"github.com/duxlabs-dev/dux-go/syncmap"
	"github.com/duxlabs-dev/dux-shell/core/internal/utils"
)

const filesEventBuffer = 256

var filesService *files.Service
var filesEvents filesBus

type filesBus struct {
	subscribers syncmap.Map[string, chan any]
}

// A full subscriber drops the batch; the client re-pages on the seq gap.
func (b *filesBus) Publish(topic string, data any) {
	if !strings.HasPrefix(topic, "files:") {
		return
	}
	b.subscribers.Range(func(_ string, ch chan any) bool {
		select {
		case ch <- data:
		default:
		}
		return true
	})
}

func (b *filesBus) Subscribe(id string) <-chan any {
	ch := make(chan any, filesEventBuffer)
	b.subscribers.Store(id, ch)
	return ch
}

// The channel is never closed: a concurrent Publish may still send on it.
func (b *filesBus) Unsubscribe(id string) {
	b.subscribers.Delete(id)
}

func InitializeFilesService() {
	filesService = files.NewService(&filesEvents, utils.XDGCacheHome(), nil)
	filesService.AttachOnOpen()
}
