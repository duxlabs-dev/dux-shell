package pubsub

import "time"

type DebouncedConfig[T any] struct {
	MinGap   time.Duration
	Stop     <-chan struct{}
	Dirty    <-chan struct{}
	Snapshot func() T
	Changed  func(prev, cur *T) bool
	Broker   *Broker[T]
}

// RunDebouncedNotifier coalesces dirty signals over cfg.MinGap, snapshots state,
// and publishes to cfg.Broker whenever state changes.
func RunDebouncedNotifier[T any](cfg DebouncedConfig[T]) {
	timer := time.NewTimer(cfg.MinGap)
	timer.Stop()
	var pending bool
	var last *T

	for {
		select {
		case <-cfg.Stop:
			timer.Stop()
			return
		case <-cfg.Dirty:
			if pending {
				continue
			}
			pending = true
			timer.Reset(cfg.MinGap)
		case <-timer.C:
			if !pending {
				continue
			}

			current := cfg.Snapshot()
			if last != nil && cfg.Changed != nil && !cfg.Changed(last, &current) {
				pending = false
				continue
			}

			cfg.Broker.Publish(current)
			stateCopy := current
			last = &stateCopy
			pending = false
		}
	}
}
