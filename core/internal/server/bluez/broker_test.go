package bluez

import (
	"context"
	"testing"
)

func TestSubscriptionBrokerAskWait(t *testing.T) {
	promptReceived := false
	broker := NewSubscriptionBroker(func(p PairingPrompt) {
		promptReceived = true
		if p.Token == "" {
			t.Error("expected token to be non-empty")
		}
		if p.DeviceName != "TestDevice" {
			t.Errorf("expected DeviceName=TestDevice, got %s", p.DeviceName)
		}
	})

	ctx := context.Background()
	req := PromptRequest{
		DevicePath:  "/org/bluez/test",
		DeviceName:  "TestDevice",
		DeviceAddr:  "AA:BB:CC:DD:EE:FF",
		RequestType: "pin",
		Fields:      []string{"pin"},
	}

	token, err := broker.Ask(ctx, req)
	if err != nil {
		t.Fatalf("Ask failed: %v", err)
	}

	if token == "" {
		t.Fatal("expected non-empty token")
	}

	if !promptReceived {
		t.Fatal("expected prompt broadcast to be called")
	}

	broker.Resolve(token, PromptReply{
		Secrets: map[string]string{"pin": "1234"},
		Accept:  true,
	})

	reply, err := broker.Wait(ctx, token)
	if err != nil {
		t.Fatalf("Wait failed: %v", err)
	}

	if reply.Secrets["pin"] != "1234" {
		t.Errorf("expected pin=1234, got %s", reply.Secrets["pin"])
	}

	if !reply.Accept {
		t.Error("expected Accept=true")
	}
}

func TestSubscriptionBrokerTimeout(t *testing.T) {
	broker := NewSubscriptionBroker(nil)

	ctx, cancel := context.WithCancel(context.Background())
	cancel()

	req := PromptRequest{
		DevicePath:  "/org/bluez/test",
		DeviceName:  "TestDevice",
		RequestType: "passkey",
		Fields:      []string{"passkey"},
	}

	token, err := broker.Ask(ctx, req)
	if err != nil {
		t.Fatalf("Ask failed: %v", err)
	}

	_, err = broker.Wait(ctx, token)
	if err == nil {
		t.Fatal("expected timeout error")
	}
}

func TestSubscriptionBrokerCancel(t *testing.T) {
	broker := NewSubscriptionBroker(nil)

	ctx := context.Background()
	req := PromptRequest{
		DevicePath:  "/org/bluez/test",
		DeviceName:  "TestDevice",
		RequestType: "confirm",
		Fields:      []string{"decision"},
	}

	token, err := broker.Ask(ctx, req)
	if err != nil {
		t.Fatalf("Ask failed: %v", err)
	}

	broker.Resolve(token, PromptReply{
		Cancel: true,
	})

	_, err = broker.Wait(ctx, token)
	if err == nil {
		t.Fatal("expected cancelled error")
	}
}

func TestSubscriptionBrokerUnknownToken(t *testing.T) {
	broker := NewSubscriptionBroker(nil)

	ctx := context.Background()
	_, err := broker.Wait(ctx, "invalid-token")
	if err == nil {
		t.Fatal("expected error for unknown token")
	}
}

func TestSubscriptionBrokerResolveUnknownToken(t *testing.T) {
	broker := NewSubscriptionBroker(nil)

	err := broker.Resolve("unknown-token", PromptReply{
		Secrets: map[string]string{"test": "value"},
	})
	if err == nil {
		t.Fatal("expected error for unknown token")
	}
}
