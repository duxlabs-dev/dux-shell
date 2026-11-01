package brightness

import (
	"fmt"
	"math"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
)

func NewSysfsBackend() (*SysfsBackend, error) {
	b := &SysfsBackend{
		basePath: "/sys/class",
		classes:  []string{"backlight", "leds"},
	}

	if err := b.scanDevices(); err != nil {
		return nil, err
	}

	return b, nil
}

func (b *SysfsBackend) scanDevices() error {
	for _, class := range b.classes {
		classPath := filepath.Join(b.basePath, class)
		entries, err := os.ReadDir(classPath)
		if err != nil {
			if os.IsNotExist(err) {
				continue
			}
			return fmt.Errorf("read %s: %w", classPath, err)
		}

		for _, entry := range entries {
			devicePath := filepath.Join(classPath, entry.Name())

			stat, err := os.Stat(devicePath)
			if err != nil || !stat.IsDir() {
				continue
			}
			maxPath := filepath.Join(devicePath, "max_brightness")

			maxData, err := os.ReadFile(maxPath)
			if err != nil {
				log.Debugf("skip %s/%s: no max_brightness", class, entry.Name())
				continue
			}

			maxBrightness, err := strconv.Atoi(strings.TrimSpace(string(maxData)))
			if err != nil || maxBrightness <= 0 {
				log.Debugf("skip %s/%s: invalid max_brightness", class, entry.Name())
				continue
			}

			deviceClass := ClassBacklight
			minValue := 1
			if class == "leds" {
				deviceClass = ClassLED
				minValue = 0
			}

			deviceID := fmt.Sprintf("%s:%s", class, entry.Name())
			b.deviceCache.Store(deviceID, &sysfsDevice{
				class:         deviceClass,
				id:            deviceID,
				name:          entry.Name(),
				maxBrightness: maxBrightness,
				minValue:      minValue,
			})

			log.Debugf("found %s device: %s (max=%d)", class, entry.Name(), maxBrightness)
		}
	}

	return nil
}

func shouldSuppressDevice(name string) bool {
	if strings.HasSuffix(name, "::lan") {
		return true
	}

	keyboardLEDs := []string{
		"::scrolllock",
		"::capslock",
		"::numlock",
		"::kana",
		"::compose",
	}

	for _, suffix := range keyboardLEDs {
		if strings.HasSuffix(name, suffix) {
			return true
		}
	}

	return false
}

func (b *SysfsBackend) Rescan() error {
	return b.scanDevices()
}

func (b *SysfsBackend) GetDevices() ([]Device, error) {
	devices := make([]Device, 0)

	b.deviceCache.Range(func(key string, dev *sysfsDevice) bool {
		if shouldSuppressDevice(dev.name) {
			return true
		}

		parts := strings.SplitN(dev.id, ":", 2)
		if len(parts) != 2 {
			return true
		}

		class := parts[0]
		name := parts[1]

		devicePath := filepath.Join(b.basePath, class, name)
		brightnessPath := filepath.Join(devicePath, "brightness")

		brightnessData, err := os.ReadFile(brightnessPath)
		if err != nil {
			log.Debugf("failed to read brightness for %s: %v", dev.id, err)
			return true
		}

		current, err := strconv.Atoi(strings.TrimSpace(string(brightnessData)))
		if err != nil {
			log.Debugf("failed to parse brightness for %s: %v", dev.id, err)
			return true
		}

		percent := b.ValueToPercent(current, dev, false)

		devices = append(devices, Device{
			Class:          dev.class,
			ID:             dev.id,
			Name:           dev.name,
			Current:        current,
			Max:            dev.maxBrightness,
			CurrentPercent: percent,
			Backend:        "sysfs",
		})
		return true
	})

	return devices, nil
}

func (b *SysfsBackend) GetDevice(id string) (*sysfsDevice, error) {
	dev, ok := b.deviceCache.Load(id)
	if !ok {
		return nil, fmt.Errorf("device not found: %s", id)
	}

	return dev, nil
}

func (b *SysfsBackend) SetBrightness(id string, percent int, exponential bool) error {
	return b.SetBrightnessWithExponent(id, percent, exponential, 1.2)
}

func (b *SysfsBackend) SetBrightnessWithExponent(id string, percent int, exponential bool, exponent float64) error {
	dev, err := b.GetDevice(id)
	if err != nil {
		return err
	}

	if percent < 0 {
		return fmt.Errorf("percent out of range: %d", percent)
	}

	value := b.PercentToValueWithExponent(percent, dev, exponential, exponent)

	parts := strings.SplitN(id, ":", 2)
	if len(parts) != 2 {
		return fmt.Errorf("invalid device id: %s", id)
	}

	class := parts[0]
	name := parts[1]

	devicePath := filepath.Join(b.basePath, class, name)
	brightnessPath := filepath.Join(devicePath, "brightness")

	data := fmt.Appendf(nil, "%d", value)
	if err := os.WriteFile(brightnessPath, data, 0o644); err != nil {
		return fmt.Errorf("write brightness: %w", err)
	}

	log.Debugf("set %s to %d%% (%d/%d) via direct sysfs", id, percent, value, dev.maxBrightness)

	return nil
}

func (b *SysfsBackend) PercentToValue(percent int, dev *sysfsDevice, exponential bool) int {
	return b.PercentToValueWithExponent(percent, dev, exponential, 1.2)
}

func (b *SysfsBackend) PercentToValueWithExponent(percent int, dev *sysfsDevice, exponential bool, exponent float64) int {
	if percent == 0 {
		return dev.minValue
	}

	usableRange := dev.maxBrightness - dev.minValue
	var value int

	if exponential {
		normalizedPercent := float64(percent-1) / 99.0
		hardwarePercent := math.Pow(normalizedPercent, exponent)
		value = dev.minValue + int(math.Round(hardwarePercent*float64(usableRange)))
	} else {
		value = dev.minValue + ((percent - 1) * usableRange / 99)
	}

	if value < dev.minValue {
		value = dev.minValue
	}
	if value > dev.maxBrightness {
		value = dev.maxBrightness
	}

	return value
}

func (b *SysfsBackend) ValueToPercent(value int, dev *sysfsDevice, exponential bool) int {
	return b.ValueToPercentWithExponent(value, dev, exponential, 1.2)
}

func (b *SysfsBackend) ValueToPercentWithExponent(value int, dev *sysfsDevice, exponential bool, exponent float64) int {
	if value <= dev.minValue {
		if dev.minValue == 0 && value == 0 {
			return 0
		}
		return 1
	}

	usableRange := dev.maxBrightness - dev.minValue
	if usableRange == 0 {
		return 100
	}

	var percent int

	if exponential {
		hardwarePercent := float64(value-dev.minValue) / float64(usableRange)
		normalizedPercent := math.Pow(hardwarePercent, 1.0/exponent)
		percent = 1 + int(math.Round(normalizedPercent*99.0))
	} else {
		percent = 1 + int(math.Round(float64(value-dev.minValue)*99.0/float64(usableRange)))
	}

	if percent > 100 {
		percent = 100
	}
	if percent < 1 {
		percent = 1
	}

	return percent
}
