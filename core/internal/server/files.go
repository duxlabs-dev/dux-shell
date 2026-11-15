package server

import (
	"strings"

	"github.com/duxlabs-dev/dux-go/files"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/pubsub"
	"github.com/duxlabs-dev/dux-shell/core/internal/utils"
)

const filesEventBuffer = 256

var filesService *files.Service
var filesEvents = filesBus{broker: pubsub.NewBroker[any](filesEventBuffer)}

type filesBus struct {
	broker *pubsub.Broker[any]
}

// A full subscriber drops the batch; the client re-pages on the seq gap.
func (b *filesBus) Publish(topic string, data any) {
	if !strings.HasPrefix(topic, "files:") {
		return
	}
	b.broker.Publish(data)
}

func (b *filesBus) Subscribe(id string) <-chan any {
	return b.broker.Subscribe(id)
}

func (b *filesBus) Unsubscribe(id string) {
	b.broker.Unsubscribe(id)
}

func InitializeFilesService() {
	filesService = files.NewService(&filesEvents, utils.XDGCacheHome(), nil)
	filesService.AttachOnOpen()
}
