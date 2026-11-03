package brightness

import (
	"encoding/binary"
	"errors"
	"fmt"
	"math"
	"os"
	"strings"
	"syscall"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"golang.org/x/sys/unix"
)

const (
	I2C_SLAVE       = 0x0703
	DDCCI_ADDR      = 0x37
	DDCCI_VCP_GET   = 0x01
	DDCCI_VCP_SET   = 0x03
	VCP_BRIGHTNESS  = 0x10
	DDC_SOURCE_ADDR = 0x51
	EDID_ADDR       = 0x50
)

const (
	ddcBusLockPoll = 100 * time.Millisecond
	ddcBusLockWait = 3 * time.Second
)

var (
	errDDCDisabled   = errors.New("disabled via DMS_NO_DDC")
	errInvalidEDID   = errors.New("invalid edid")
	errDisplayAsleep = errors.New("display asleep")
	errNoMonitor     = errors.New("no monitor on bus")
	errBusReused     = errors.New("bus belongs to another adapter")
)

var ddcRereadDelays = []time.Duration{5 * time.Second, 10 * time.Second, 20 * time.Second}

func NewDDCBackend() (*DDCBackend, error) {
	return newDDCBackend(nil)
}

func newDDCBackend(onReread func()) (*DDCBackend, error) {
	if os.Getenv("DMS_NO_DDC") != "" {
		return nil, errDDCDisabled
	}

	b := &DDCBackend{
		scanInterval:    30 * time.Second,
		debounceTimers:  make(map[string]*time.Timer),
		debouncePending: make(map[string]ddcPendingSet),
		onReread:        onReread,
		stop:            make(chan struct{}),
	}

	if err := b.scanI2CDevices(); err != nil {
		return nil, err
	}

	return b, nil
}

func (b *DDCBackend) scanI2CDevices() error {
	return b.scanI2CDevicesInternal(false)
}

func (b *DDCBackend) ForceRescan() error {
	return b.scanI2CDevicesInternal(true)
}

func (b *DDCBackend) scanI2CDevicesInternal(force bool) error {
	b.scanMutex.Lock()
	defer b.scanMutex.Unlock()

	if !force && time.Since(b.lastScan) < b.scanInterval {
		return nil
	}

	activeBuses := make(map[int]bool)
	connectors := drmConnectorsByBus()

	for i := range 32 {
		busPath := fmt.Sprintf("/dev/i2c-%d", i)
		if _, err := os.Stat(busPath); os.IsNotExist(err) {
			continue
		}

		if isIgnorableI2CBus(i) {
			log.Debugf("Skipping ignorable i2c-%d", i)
			continue
		}

		activeBuses[i] = true
		id := fmt.Sprintf("ddc:i2c-%d", i)

		// Don't re-probe identified monitors: DDC traffic during a wake
		// sequence can disturb some monitors' own brightness handling.
		if known, ok := b.devices.Load(id); ok {
			if known.adapter == getI2CDeviceSysfsName(i) {
				continue
			}
			b.devices.Delete(id)
			log.Debugf("removed DDC device %s (bus number reused by another adapter)", id)
		}

		verdict := ddcBusVerdictFor(i, connectors)
		if verdict == ddcBusSkip {
			log.Debugf("i2c-%d: no monitor per DRM sysfs, not probing", i)
			continue
		}
		if ddcDisplayAsleep(i, connectors) {
			log.Debugf("i2c-%d: display asleep, not probing", i)
			continue
		}

		dev, err := b.probeDDCDevice(i, verdict == ddcBusNeedsEDIDRead)
		if err != nil || dev == nil {
			continue
		}

		dev.id = id
		dev.connector = drmConnectorPattern.ReplaceAllString(connectors[i], "")
		unread := dev.max == 0
		b.devices.Store(id, dev)
		log.Debugf("found DDC device on i2c-%d", i)
		if unread && b.onReread != nil {
			go b.rereadUntilKnown(dev)
		}
	}

	b.devices.Range(func(id string, dev *ddcDevice) bool {
		if !activeBuses[dev.bus] {
			b.devices.Delete(id)
			log.Debugf("removed DDC device %s (bus no longer exists)", id)
		}
		return true
	})

	b.lastScan = time.Now()

	return nil
}

func (b *DDCBackend) probeDDCDevice(bus int, readEDID bool) (*ddcDevice, error) {
	fd, err := openDDCBus(bus)
	if err != nil {
		return nil, err
	}
	defer syscall.Close(fd)

	if readEDID {
		edid, err := readBusEDID(fd)
		if err != nil {
			return nil, err
		}
		if isLaptopEDID(edid) {
			return nil, errors.New("laptop panel")
		}
	}

	if err := setI2CAddr(fd, DDCCI_ADDR); err != nil {
		return nil, err
	}
	if !detectX37(fd) {
		return nil, fmt.Errorf("x37 unresponsive")
	}

	dev := &ddcDevice{
		bus:     bus,
		addr:    DDCCI_ADDR,
		name:    b.getDDCName(bus),
		adapter: getI2CDeviceSysfsName(bus),
	}
	b.readInitialBrightness(fd, dev)
	return dev, nil
}

// flock on the device node is how ddc tools and other dms processes take turns on a bus.
func openDDCBus(bus int) (int, error) {
	// Without O_CLOEXEC a process spawned mid-probe inherits the fd and the flock with it.
	fd, err := syscall.Open(fmt.Sprintf("/dev/i2c-%d", bus), syscall.O_RDWR|syscall.O_CLOEXEC, 0)
	if err != nil {
		return -1, err
	}
	deadline := time.Now().Add(ddcBusLockWait)
	for {
		err = unix.Flock(fd, unix.LOCK_EX|unix.LOCK_NB)
		if err == nil {
			return fd, nil
		}
		if !errors.Is(err, unix.EWOULDBLOCK) || time.Now().After(deadline) {
			syscall.Close(fd)
			return -1, fmt.Errorf("lock i2c-%d: %w", bus, err)
		}
		time.Sleep(ddcBusLockPoll)
	}
}

func setI2CAddr(fd, addr int) error {
	if _, _, errno := syscall.Syscall(syscall.SYS_IOCTL, uintptr(fd), I2C_SLAVE, uintptr(addr)); errno != 0 {
		return errno
	}
	return nil
}

func detectX37(fd int) bool {
	if n, err := syscall.Read(fd, make([]byte, 1)); err == nil && n == 1 {
		return true
	}
	_, err := syscall.Write(fd, nil)
	return err == nil
}

func readBusEDID(fd int) ([]byte, error) {
	if err := setI2CAddr(fd, EDID_ADDR); err != nil {
		return nil, err
	}
	var err error
	consecutiveEIO := 0
	for _, size := range []int{128, 128, 256, 256} {
		edid := make([]byte, size)
		if err = readEDIDOnce(fd, edid); err == nil {
			return edid[:128], nil
		}
		switch {
		case errors.Is(err, syscall.ENXIO), errors.Is(err, syscall.EOPNOTSUPP), errors.Is(err, syscall.ETIMEDOUT):
			return nil, err
		case errors.Is(err, syscall.EIO):
			consecutiveEIO++
			if consecutiveEIO >= 2 {
				return nil, err
			}
		default:
			consecutiveEIO = 0
		}
	}
	return nil, err
}

func readEDIDOnce(fd int, edid []byte) error {
	if _, err := syscall.Write(fd, []byte{0x00}); err != nil {
		return err
	}
	n, err := syscall.Read(fd, edid)
	if err != nil {
		return err
	}
	if n < 128 || !isValidEDID(edid[:128]) {
		return errInvalidEDID
	}
	return nil
}

func (b *DDCBackend) getDDCName(bus int) string {
	sysfsPath := fmt.Sprintf("/sys/class/i2c-adapter/i2c-%d/name", bus)
	data, err := os.ReadFile(sysfsPath)
	if err != nil {
		return fmt.Sprintf("I2C-%d", bus)
	}

	name := strings.TrimSpace(string(data))
	if name == "" {
		name = fmt.Sprintf("I2C-%d", bus)
	}

	return name
}

func (b *DDCBackend) readInitialBrightness(fd int, dev *ddcDevice) {
	for attempt := 0; attempt < 3; attempt++ {
		cap, err := b.getVCPFeature(fd, VCP_BRIGHTNESS)
		if err == nil {
			dev.max = cap.max
			dev.lastBrightness = cap.current
			log.Debugf("initialized %s with brightness %d/%d", dev.name, cap.current, cap.max)
			return
		}
		if attempt < 2 {
			time.Sleep(100 * time.Millisecond)
			continue
		}
		log.Debugf("failed to read initial brightness for %s: %v", dev.name, err)
	}
}

// Bounded and spaced: extra DDC traffic can upset some monitors (#2049).
func (b *DDCBackend) rereadUntilKnown(dev *ddcDevice) {
	for _, delay := range ddcRereadDelays {
		select {
		case <-b.stop:
			return
		case <-time.After(delay):
		}
		read, retry := b.rereadBrightness(dev)
		if read {
			b.onReread()
			return
		}
		if !retry {
			return
		}
	}
	log.Debugf("giving up on reading brightness for %s", dev.id)
}

func (b *DDCBackend) rereadBrightness(dev *ddcDevice) (read, retry bool) {
	b.ioMutex.Lock()
	defer b.ioMutex.Unlock()

	if current, ok := b.devices.Load(dev.id); !ok || current != dev || dev.max > 0 {
		return false, false
	}
	switch err := b.checkBusAlive(dev); {
	case errors.Is(err, errBusReused):
		return false, false
	case err != nil:
		return false, true
	}

	fd, err := openDDCBus(dev.bus)
	if err != nil {
		log.Debugf("brightness reread skipped for %s: %v", dev.id, err)
		return false, true
	}
	defer syscall.Close(fd)

	if err := setI2CAddr(fd, dev.addr); err != nil {
		return false, false
	}

	cap, err := b.getVCPFeature(fd, VCP_BRIGHTNESS)
	if err != nil {
		log.Debugf("brightness reread failed for %s: %v", dev.id, err)
		return false, true
	}

	dev.max = cap.max
	dev.lastBrightness = cap.current
	log.Debugf("read %s brightness %d/%d", dev.id, cap.current, cap.max)
	return true, false
}

func (b *DDCBackend) GetDevices() ([]Device, error) {
	if err := b.scanI2CDevices(); err != nil {
		log.Debugf("DDC scan error: %v", err)
	}

	devices := make([]Device, 0)

	b.ioMutex.Lock()
	defer b.ioMutex.Unlock()
	b.devices.Range(func(id string, dev *ddcDevice) bool {
		devices = append(devices, Device{
			Class:          ClassDDC,
			ID:             id,
			Name:           dev.name,
			Current:        dev.lastBrightness,
			Max:            dev.max,
			CurrentPercent: ddcPercentFromRaw(dev.lastBrightness, dev.max),
			Backend:        "ddc",
		})
		return true
	})

	return devices, nil
}

// ControlledOutputs returns the output names (DP-2, ...) of monitors whose brightness is driven over DDC/CI.
func (b *DDCBackend) ControlledOutputs() []string {
	connectors := []string{}
	b.devices.Range(func(_ string, dev *ddcDevice) bool {
		if dev.connector != "" {
			connectors = append(connectors, dev.connector)
		}
		return true
	})
	return connectors
}

func (b *DDCBackend) SetBrightness(id string, value int, exponential bool, callback func()) error {
	return b.SetBrightnessWithExponent(id, value, exponential, 1.2, callback)
}

func (b *DDCBackend) SetBrightnessWithExponent(id string, value int, exponential bool, exponent float64, callback func()) error {
	_, ok := b.devices.Load(id)

	if !ok {
		if err := b.scanI2CDevicesInternal(true); err != nil {
			log.Debugf("rescan failed for %s: %v", id, err)
		}
		_, ok = b.devices.Load(id)
	}

	if !ok {
		return fmt.Errorf("device not found: %s", id)
	}

	if value < 0 {
		return fmt.Errorf("value out of range: %d", value)
	}

	b.debounceMutex.Lock()
	b.debouncePending[id] = ddcPendingSet{
		percent:  value,
		callback: callback,
	}

	if existing, exists := b.debounceTimers[id]; exists {
		if existing.Stop() {
			b.debounceWg.Done()
		}
	}

	b.debounceWg.Add(1)
	b.debounceTimers[id] = time.AfterFunc(200*time.Millisecond, func() {
		defer b.debounceWg.Done()

		b.debounceMutex.Lock()
		pending, hasPending := b.debouncePending[id]
		delete(b.debouncePending, id)
		delete(b.debounceTimers, id)
		b.debounceMutex.Unlock()

		if !hasPending {
			return
		}

		if err := b.setBrightnessImmediateWithExponent(id, pending.percent); err != nil {
			log.Debugf("Failed to set brightness for %s: %v", id, err)
		}

		if pending.callback != nil {
			pending.callback()
		}
	})
	b.debounceMutex.Unlock()

	return nil
}

func (b *DDCBackend) setBrightnessImmediateWithExponent(id string, value int) error {
	dev, ok := b.devices.Load(id)

	if !ok {
		if err := b.scanI2CDevicesInternal(true); err != nil {
			log.Debugf("rescan failed for %s: %v", id, err)
		}
		dev, ok = b.devices.Load(id)
	}

	if !ok {
		return fmt.Errorf("device not found: %s", id)
	}

	b.ioMutex.Lock()
	defer b.ioMutex.Unlock()

	busPath := fmt.Sprintf("/dev/i2c-%d", dev.bus)

	if _, err := os.Stat(busPath); os.IsNotExist(err) {
		b.devices.Delete(id)
		log.Debugf("removed stale DDC device %s (bus no longer exists)", id)
		return fmt.Errorf("device disconnected: %s", id)
	}

	switch err := b.checkBusAlive(dev); {
	case errors.Is(err, errBusReused):
		b.devices.Delete(id)
		log.Debugf("removed DDC device %s (bus number reused by another adapter)", id)
		return err
	case err != nil:
		return err
	}

	fd, err := openDDCBus(dev.bus)
	switch {
	case errors.Is(err, unix.EWOULDBLOCK):
		return err
	case err != nil:
		b.devices.Delete(id)
		log.Debugf("removed DDC device %s (open failed: %v)", id, err)
		return fmt.Errorf("open i2c device: %w", err)
	}
	defer syscall.Close(fd)

	if err := setI2CAddr(fd, dev.addr); err != nil {
		return fmt.Errorf("set i2c slave addr: %w", err)
	}

	maxValue := dev.max
	if maxValue == 0 {
		cap, err := b.getVCPFeature(fd, VCP_BRIGHTNESS)
		if err != nil {
			return fmt.Errorf("get current capability: %w", err)
		}
		maxValue = cap.max
	}
	if maxValue <= 0 {
		return fmt.Errorf("%s reported max brightness %d", id, maxValue)
	}

	raw := ddcRawFromPercent(value, maxValue)
	if err := b.setVCPFeature(fd, VCP_BRIGHTNESS, raw); err != nil {
		return fmt.Errorf("set vcp feature: %w", err)
	}

	log.Debugf("set %s to %d/%d", id, raw, maxValue)

	dev.max = maxValue
	dev.lastBrightness = raw
	b.devices.Store(id, dev)

	return nil
}

// Known devices are keyed by bus number, which the kernel hands to the next adapter once one goes away.
func (b *DDCBackend) checkBusAlive(dev *ddcDevice) error {
	if isIgnorableI2CBus(dev.bus) || getI2CDeviceSysfsName(dev.bus) != dev.adapter {
		return errBusReused
	}
	connectors := drmConnectorsByBus()
	if ddcBusVerdictFor(dev.bus, connectors) == ddcBusSkip {
		return errNoMonitor
	}
	if ddcDisplayAsleep(dev.bus, connectors) {
		return errDisplayAsleep
	}
	return nil
}

func ddcRawFromPercent(percent, maxValue int) int {
	percent = min(max(percent, 0), 100)
	return int(math.Round(float64(percent*maxValue) / 100))
}

func ddcPercentFromRaw(raw, maxValue int) int {
	if maxValue <= 0 {
		return 0
	}
	return min(int(math.Round(float64(raw*100)/float64(maxValue))), 100)
}

func (b *DDCBackend) getVCPFeature(fd int, vcp byte) (*ddcCapability, error) {
	data := []byte{
		DDCCI_VCP_GET,
		vcp,
	}

	payload := []byte{
		DDC_SOURCE_ADDR,
		byte(len(data)) | 0x80,
	}
	payload = append(payload, data...)
	payload = append(payload, ddcciChecksum(payload))

	n, err := syscall.Write(fd, payload)
	if err != nil || n != len(payload) {
		return nil, fmt.Errorf("write i2c: %w", err)
	}

	time.Sleep(50 * time.Millisecond)

	response := make([]byte, 12)
	n, err = syscall.Read(fd, response)
	if err != nil || n < 8 {
		return nil, fmt.Errorf("read i2c: %w", err)
	}

	if response[0] != 0x6E || response[2] != 0x02 {
		return nil, fmt.Errorf("invalid ddc response")
	}

	resultCode := response[3]
	if resultCode != 0x00 {
		return nil, fmt.Errorf("vcp feature not supported")
	}

	responseVCP := response[4]
	if responseVCP != vcp {
		return nil, fmt.Errorf("vcp mismatch: wanted 0x%02x, got 0x%02x", vcp, responseVCP)
	}

	maxHigh := response[6]
	maxLow := response[7]
	currentHigh := response[8]
	currentLow := response[9]

	max := int(binary.BigEndian.Uint16([]byte{maxHigh, maxLow}))
	current := int(binary.BigEndian.Uint16([]byte{currentHigh, currentLow}))

	return &ddcCapability{
		vcp:     vcp,
		max:     max,
		current: current,
	}, nil
}

func ddcciChecksum(payload []byte) byte {
	sum := byte(0x6E)
	for _, b := range payload {
		sum ^= b
	}
	return sum
}

func (b *DDCBackend) setVCPFeature(fd int, vcp byte, value int) error {
	data := []byte{
		DDCCI_VCP_SET,
		vcp,
		byte(value >> 8),
		byte(value & 0xFF),
	}

	payload := []byte{
		DDC_SOURCE_ADDR,
		byte(len(data)) | 0x80,
	}
	payload = append(payload, data...)
	payload = append(payload, ddcciChecksum(payload))

	if _, _, errno := syscall.Syscall(syscall.SYS_IOCTL, uintptr(fd), I2C_SLAVE, uintptr(DDCCI_ADDR)); errno != 0 {
		return fmt.Errorf("set i2c slave for write: %w", errno)
	}

	n, err := syscall.Write(fd, payload)
	if err != nil || n != len(payload) {
		return fmt.Errorf("write i2c: wrote %d/%d: %w", n, len(payload), err)
	}

	time.Sleep(50 * time.Millisecond)

	return nil
}

func (b *DDCBackend) percentToValue(percent int, max int, exponential bool) int {
	const minValue = 1

	if percent == 0 {
		return minValue
	}

	usableRange := max - minValue
	var value int

	if exponential {
		const exponent = 2.0
		normalizedPercent := float64(percent) / 100.0
		hardwarePercent := math.Pow(normalizedPercent, 1.0/exponent)
		value = minValue + int(math.Round(hardwarePercent*float64(usableRange)))
	} else {
		value = minValue + ((percent - 1) * usableRange / 99)
	}

	if value < minValue {
		value = minValue
	}
	if value > max {
		value = max
	}

	return value
}

func (b *DDCBackend) valueToPercent(value int, max int, exponential bool) int {
	const minValue = 1

	if max == 0 {
		return 0
	}

	if value <= minValue {
		return 1
	}

	usableRange := max - minValue
	if usableRange == 0 {
		return 100
	}

	var percent int

	if exponential {
		const exponent = 2.0
		linearPercent := 1 + ((value - minValue) * 99 / usableRange)
		normalizedLinear := float64(linearPercent) / 100.0
		expPercent := math.Pow(normalizedLinear, exponent)
		percent = int(math.Round(expPercent * 100.0))
	} else {
		percent = 1 + ((value - minValue) * 99 / usableRange)
	}

	if percent > 100 {
		percent = 100
	}
	if percent < 1 {
		percent = 1
	}

	return percent
}

func (b *DDCBackend) WaitPending() {
	done := make(chan struct{})
	go func() {
		b.debounceWg.Wait()
		close(done)
	}()

	select {
	case <-done:
	case <-time.After(5 * time.Second):
		log.Debug("WaitPending timed out waiting for DDC writes")
	}
}

func (b *DDCBackend) Close() {
	if b.stop == nil {
		return
	}
	b.closeOnce.Do(func() { close(b.stop) })
}
