package pubsub

import "sync"

const defaultBufferSize = 64

// Broker fans out events to keyed subscribers without blocking slow readers.
// Its zero value is ready to use with a buffer size of 64.
type Broker[T any] struct {
	mu      sync.RWMutex
	subs    map[string]chan T
	BufSize int
	closed  bool
}

func NewBroker[T any](bufSize int) *Broker[T] {
	return &Broker[T]{BufSize: bufSize}
}

func (b *Broker[T]) Subscribe(id string) chan T {
	b.mu.Lock()
	defer b.mu.Unlock()

	if b.closed {
		ch := make(chan T)
		close(ch)
		return ch
	}

	if b.subs == nil {
		b.subs = make(map[string]chan T)
	}
	if old, ok := b.subs[id]; ok {
		close(old)
	}

	buf := b.BufSize
	if buf <= 0 {
		buf = defaultBufferSize
	}
	ch := make(chan T, buf)
	b.subs[id] = ch
	return ch
}

// Unsubscribe removes and closes ch only if id still points to ch, so a
// stale reader's deferred Unsubscribe cannot clobber a newer Subscribe on id.
func (b *Broker[T]) Unsubscribe(id string, ch <-chan T) bool {
	b.mu.Lock()
	defer b.mu.Unlock()

	cur, ok := b.subs[id]
	if !ok || cur != ch {
		return false
	}
	delete(b.subs, id)
	close(cur)
	return true
}

func (b *Broker[T]) Publish(v T) {
	b.mu.RLock()
	defer b.mu.RUnlock()

	if b.closed {
		return
	}
	for _, ch := range b.subs {
		select {
		case ch <- v:
		default:
		}
	}
}

// PublishLatest delivers v to every subscriber, evicting the oldest queued
// item if a subscriber's buffer is full.
func (b *Broker[T]) PublishLatest(v T) {
	b.mu.RLock()
	defer b.mu.RUnlock()

	if b.closed {
		return
	}
	for _, ch := range b.subs {
		select {
		case ch <- v:
		default:
			select {
			case <-ch:
			default:
			}
			select {
			case ch <- v:
			default:
			}
		}
	}
}

func (b *Broker[T]) Len() int {
	b.mu.RLock()
	defer b.mu.RUnlock()
	return len(b.subs)
}

func (b *Broker[T]) Has(id string) bool {
	b.mu.RLock()
	defer b.mu.RUnlock()
	_, ok := b.subs[id]
	return ok
}

func (b *Broker[T]) Close() {
	b.mu.Lock()
	defer b.mu.Unlock()

	if b.closed {
		return
	}
	b.closed = true
	for id, ch := range b.subs {
		close(ch)
		delete(b.subs, id)
	}
}
