package pubsub

import (
	"sync"
	"testing"
)

func TestBroker_SubscribePublishUnsubscribe(t *testing.T) {
	b := NewBroker[int](2)
	if b.Len() != 0 {
		t.Fatalf("expected Len() == 0, got %d", b.Len())
	}

	ch := b.Subscribe("c1")
	if b.Len() != 1 {
		t.Fatalf("expected Len() == 1, got %d", b.Len())
	}

	b.Publish(1)
	b.Publish(2)
	b.Publish(3) // dropped because buffer is 2

	if got := <-ch; got != 1 {
		t.Fatalf("expected 1, got %d", got)
	}
	if got := <-ch; got != 2 {
		t.Fatalf("expected 2, got %d", got)
	}
	select {
	case v := <-ch:
		t.Fatalf("expected empty channel, got %d", v)
	default:
	}

	if !b.Unsubscribe("c1") {
		t.Fatal("expected Unsubscribe to return true")
	}
	if b.Unsubscribe("c1") {
		t.Fatal("expected second Unsubscribe to return false")
	}
	if _, ok := <-ch; ok {
		t.Fatal("expected channel to be closed after Unsubscribe")
	}
	if b.Len() != 0 {
		t.Fatalf("expected Len() == 0, got %d", b.Len())
	}
}

func TestBroker_CloseAndConcurrentPublish(t *testing.T) {
	var b Broker[int]
	ch := b.Subscribe("c1")

	var wg sync.WaitGroup
	for range 4 {
		wg.Go(func() {
			for i := range 200 {
				b.Publish(i)
			}
		})
	}
	b.Close()
	wg.Wait()

	// Drain any values published before Close, then verify closed.
	for range ch {
	}

	closedCh := b.Subscribe("c2")
	if _, ok := <-closedCh; ok {
		t.Fatal("expected Subscribe on closed broker to return closed channel")
	}
}
