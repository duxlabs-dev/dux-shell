package clipboard

import (
	"context"
	"syscall"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/godbus/dbus/v5"
)

const (
	portalBusName       = "org.freedesktop.portal.Documents"
	portalObjectPath    = "/org/freedesktop/portal/documents"
	portalTransferIface = "org.freedesktop.portal.FileTransfer"
	portalBatchSize     = 16
	portalTimeout       = 2 * time.Second
)

type portalTransferClient interface {
	StartTransfer(ctx context.Context) (string, error)
	AddFiles(ctx context.Context, key string, fds []dbus.UnixFD) error
	StopTransfer(ctx context.Context, key string)
}

type dbusPortalTransfer struct {
	obj dbus.BusObject
}

func (c dbusPortalTransfer) StartTransfer(ctx context.Context) (string, error) {
	opts := map[string]dbus.Variant{
		"writable": dbus.MakeVariant(false),
		"autostop": dbus.MakeVariant(true),
	}
	var key string
	err := c.obj.CallWithContext(ctx, portalTransferIface+".StartTransfer", 0, opts).Store(&key)
	return key, err
}

func (c dbusPortalTransfer) AddFiles(ctx context.Context, key string, fds []dbus.UnixFD) error {
	return c.obj.CallWithContext(ctx, portalTransferIface+".AddFiles", 0, key, fds, map[string]dbus.Variant{}).Err
}

func (c dbusPortalTransfer) StopTransfer(ctx context.Context, key string) {
	_ = c.obj.CallWithContext(ctx, portalTransferIface+".StopTransfer", 0, key).Err
}

func (m *Manager) exportPortalFile(path string) string {
	return m.exportPortalFiles([]string{path})
}

func (m *Manager) exportPortalFiles(paths []string) string {
	if len(paths) == 0 {
		return ""
	}
	bus, err := dbus.SessionBus()
	if err != nil {
		log.Debugf("clipboard portalTransfer: session bus: %v", err)
		return ""
	}

	ctx, cancel := context.WithTimeout(context.Background(), portalTimeout)
	defer cancel()

	client := dbusPortalTransfer{obj: bus.Object(portalBusName, portalObjectPath)}
	key, err := m.exportPortalTransfer(ctx, client, paths)
	if err != nil {
		log.Debugf("clipboard portalTransfer: %v", err)
		return ""
	}
	return key
}

func (m *Manager) exportPortalTransfer(ctx context.Context, client portalTransferClient, paths []string) (string, error) {
	m.portalMu.Lock()
	prev := m.portalKey
	m.portalKey = ""
	m.portalMu.Unlock()

	if prev != "" {
		client.StopTransfer(ctx, prev)
	}

	key, err := client.StartTransfer(ctx)
	if err != nil || key == "" {
		return "", err
	}

	for i := 0; i < len(paths); i += portalBatchSize {
		end := min(i+portalBatchSize, len(paths))
		if err := sendPortalBatch(ctx, client, key, paths[i:end]); err != nil {
			client.StopTransfer(ctx, key)
			return "", err
		}
	}

	m.portalMu.Lock()
	stale := m.portalKey
	m.portalKey = key
	m.portalMu.Unlock()

	if stale != "" {
		client.StopTransfer(ctx, stale)
	}
	return key, nil
}

func sendPortalBatch(ctx context.Context, client portalTransferClient, key string, paths []string) error {
	fds := make([]dbus.UnixFD, 0, len(paths))
	defer func() {
		for _, fd := range fds {
			_ = syscall.Close(int(fd))
		}
	}()

	for _, p := range paths {
		fd, err := syscall.Open(p, syscall.O_RDONLY|syscall.O_NONBLOCK|syscall.O_CLOEXEC, 0)
		if err != nil {
			return err
		}
		fds = append(fds, dbus.UnixFD(fd))
	}
	return client.AddFiles(ctx, key, fds)
}
