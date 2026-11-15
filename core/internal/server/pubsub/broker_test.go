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

	if !b.Unsubscribe("c1", ch) {
		t.Fatal("expected Unsubscribe to return true")
	}
	if b.Unsubscribe("c1", ch) {
		t.Fatal("expected second Unsubscribe to return false")
	}
	if _, ok := <-ch; ok {
		t.Fatal("expected channel to be closed after Unsubscribe")
	}
	if b.Len() != 0 {
		t.Fatalf("expected Len() == 0, got %d", b.Len())
	}
}

func TestBroker_ResubscribeSameID(t *testing.T) {
	var b Broker[int]
	ch1 := b.Subscribe("1")
	ch2 := b.Subscribe("1")

	if _, ok := <-ch1; ok {
		t.Fatal("expected superseded channel ch1 to be closed")
	}
	if b.Unsubscribe("1", ch1) {
		t.Fatal("expected stale Unsubscribe(id, ch1) to return false")
	}
	if !b.Has("1") || b.Len() != 1 {
		t.Fatal("expected newer subscription ch2 to remain registered")
	}

	b.Publish(42)
	if got, ok := <-ch2; !ok || got != 42 {
		t.Fatalf("expected ch2 to receive 42, got (%d, %v)", got, ok)
	}
	if !b.Unsubscribe("1", ch2) {
		t.Fatal("expected Unsubscribe(id, ch2) to return true")
	}
}

func TestBroker_PublishLatest(t *testing.T) {
	b := NewBroker[int](2)
	ch := b.Subscribe("c1")

	b.PublishLatest(1)
	b.PublishLatest(2)
	b.PublishLatest(3) // evicts 1, keeps 2 and 3

	if got := <-ch; got != 2 {
		t.Fatalf("expected 2, got %d", got)
	}
	if got := <-ch; got != 3 {
		t.Fatalf("expected 3, got %d", got)
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
