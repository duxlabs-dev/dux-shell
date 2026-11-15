//go:build linux

package rfkill

import (
	"encoding/binary"
	"errors"
	"fmt"
	"os"
	"sync"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/duxlabs-dev/dux-shell/core/internal/server/pubsub"
	"golang.org/x/sys/unix"
)

const (
	rfkillDevicePath = "/dev/rfkill"
	rfkillEventSize  = 8

	rfkillTypeAll       = 0
	rfkillTypeWLAN      = 1
	rfkillTypeBluetooth = 2
	rfkillTypeUWB       = 3
	rfkillTypeWiMAX     = 4
	rfkillTypeWWAN      = 5
	rfkillTypeNFC       = 8

	rfkillOpAdd       = 0
	rfkillOpDel       = 1
	rfkillOpChange    = 2
	rfkillOpChangeAll = 3
)

type rfkillDevice struct {
	typ  uint8
	soft bool
	hard bool
}

type Manager struct {
	fd          int
	closePipeR  *os.File
	closePipeW  *os.File
	devices     map[uint32]rfkillDevice
	state       State
	stateMutex  sync.RWMutex
	subscribers pubsub.Broker[State]
	closeOnce   sync.Once
}

func InitializeManager() (*Manager, error) {
	fd, err := unix.Open(rfkillDevicePath, unix.O_RDONLY|unix.O_NONBLOCK|unix.O_CLOEXEC, 0)
	if err != nil {
		return nil, fmt.Errorf("failed to open %s: %w", rfkillDevicePath, err)
	}

	pipeR, pipeW, err := os.Pipe()
	if err != nil {
		unix.Close(fd)
		return nil, fmt.Errorf("failed to create close pipe: %w", err)
	}

	devices := make(map[uint32]rfkillDevice)
	if err := drainEvents(fd, devices); err != nil {
		unix.Close(fd)
		pipeR.Close()
		pipeW.Close()
		return nil, err
	}

	m := &Manager{
		fd:          fd,
		closePipeR:  pipeR,
		closePipeW:  pipeW,
		devices:     devices,
		state:       computeState(devices),
		subscribers: pubsub.Broker[State]{BufSize: 16},
	}

	go m.monitor()
	return m, nil
}

func (m *Manager) GetState() State {
	m.stateMutex.RLock()
	defer m.stateMutex.RUnlock()
	return m.state
}

func (m *Manager) SetAirplaneMode(enabled bool) error {
	f, err := os.OpenFile(rfkillDevicePath, os.O_WRONLY, 0)
	if err != nil {
		return fmt.Errorf("failed to open %s: %w", rfkillDevicePath, err)
	}
	defer f.Close()

	event := buildChangeAllEvent(enabled)
	if _, err := f.Write(event[:]); err != nil {
		return fmt.Errorf("failed to write rfkill event: %w", err)
	}
	return nil
}

func buildChangeAllEvent(blocked bool) [rfkillEventSize]byte {
	var event [rfkillEventSize]byte
	event[4] = rfkillTypeAll
	event[5] = rfkillOpChangeAll
	if blocked {
		event[6] = 1
	}
	return event
}

func (m *Manager) Subscribe(id string) chan State {
	return m.subscribers.Subscribe(id)
}

func (m *Manager) Unsubscribe(id string, ch chan State) {
	m.subscribers.Unsubscribe(id, ch)
}

func (m *Manager) Close() {
	m.closeOnce.Do(func() {
		_, _ = m.closePipeW.Write([]byte{1})
		m.closePipeW.Close()
		m.closePipeR.Close()
		unix.Close(m.fd)
		m.subscribers.Close()
	})
}

func (m *Manager) monitor() {
	pollFds := []unix.PollFd{
		{Fd: int32(m.fd), Events: unix.POLLIN},
		{Fd: int32(m.closePipeR.Fd()), Events: unix.POLLIN},
	}

	for {
		n, err := unix.Poll(pollFds, -1)
		if err != nil {
			if errors.Is(err, unix.EINTR) {
				continue
			}
			log.Debugf("rfkill poll stopped: %v", err)
			return
		}
		if n <= 0 {
			continue
		}
		if pollFds[1].Revents&(unix.POLLIN|unix.POLLHUP|unix.POLLERR) != 0 {
			return
		}
		if pollFds[0].Revents&(unix.POLLERR|unix.POLLHUP|unix.POLLNVAL) != 0 {
			return
		}
		if pollFds[0].Revents&unix.POLLIN == 0 {
			continue
		}

		m.stateMutex.Lock()
		prev := m.state
		readErr := drainEvents(m.fd, m.devices)
		next := computeState(m.devices)
		m.state = next
		m.stateMutex.Unlock()

		if readErr != nil {
			log.Debugf("rfkill read stopped: %v", readErr)
			return
		}
		if next != prev {
			m.notifySubscribers(next)
		}
	}
}

func (m *Manager) notifySubscribers(state State) {
	m.subscribers.PublishLatest(state)
}

func drainEvents(fd int, devices map[uint32]rfkillDevice) error {
	var buf [rfkillEventSize]byte
	for {
		n, err := unix.Read(fd, buf[:])
		if err != nil {
			if errors.Is(err, unix.EAGAIN) || errors.Is(err, unix.EWOULDBLOCK) {
				return nil
			}
			if errors.Is(err, unix.EINTR) {
				continue
			}
			return err
		}
		if n < rfkillEventSize {
			return nil
		}
		idx := binary.LittleEndian.Uint32(buf[0:4])
		applyEvent(devices, idx, buf[4], buf[5], buf[6], buf[7])
	}
}

func applyEvent(devices map[uint32]rfkillDevice, idx uint32, typ, op, soft, hard uint8) {
	switch op {
	case rfkillOpAdd, rfkillOpChange:
		devices[idx] = rfkillDevice{typ: typ, soft: soft != 0, hard: hard != 0}
	case rfkillOpDel:
		delete(devices, idx)
	case rfkillOpChangeAll:
		for k, d := range devices {
			if typ == rfkillTypeAll || d.typ == typ {
				d.soft = soft != 0
				devices[k] = d
			}
		}
	}
}

func isWirelessType(typ uint8) bool {
	switch typ {
	case rfkillTypeWLAN, rfkillTypeBluetooth, rfkillTypeUWB, rfkillTypeWiMAX, rfkillTypeWWAN, rfkillTypeNFC:
		return true
	default:
		return false
	}
}

func computeState(devices map[uint32]rfkillDevice) State {
	hasWireless := false
	allBlocked := true
	for _, dev := range devices {
		if !isWirelessType(dev.typ) {
			continue
		}
		hasWireless = true
		if !dev.soft && !dev.hard {
			allBlocked = false
			break
		}
	}
	return State{
		Available:    hasWireless,
		AirplaneMode: hasWireless && allBlocked,
	}
}
