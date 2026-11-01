package bluez

import (
	"context"
	"fmt"

	"github.com/duxlabs-dev/dux-go/syncmap"
	"github.com/duxlabs-dev/dux-shell/core/internal/errdefs"
)

type SubscriptionBroker struct {
	pending         syncmap.Map[string, chan PromptReply]
	requests        syncmap.Map[string, PromptRequest]
	broadcastPrompt func(PairingPrompt)
}

func NewSubscriptionBroker(broadcastPrompt func(PairingPrompt)) PromptBroker {
	return &SubscriptionBroker{
		broadcastPrompt: broadcastPrompt,
	}
}

func (b *SubscriptionBroker) Ask(ctx context.Context, req PromptRequest) (string, error) {
	token, err := generateToken()
	if err != nil {
		return "", err
	}

	replyChan := make(chan PromptReply, 1)
	b.pending.Store(token, replyChan)
	b.requests.Store(token, req)

	if b.broadcastPrompt != nil {
		prompt := PairingPrompt{
			Token:       token,
			DevicePath:  req.DevicePath,
			DeviceName:  req.DeviceName,
			DeviceAddr:  req.DeviceAddr,
			RequestType: req.RequestType,
			Fields:      req.Fields,
			Hints:       req.Hints,
			Passkey:     req.Passkey,
		}
		b.broadcastPrompt(prompt)
	}

	return token, nil
}

func (b *SubscriptionBroker) Wait(ctx context.Context, token string) (PromptReply, error) {
	replyChan, exists := b.pending.Load(token)
	if !exists {
		return PromptReply{}, fmt.Errorf("unknown token: %s", token)
	}

	select {
	case <-ctx.Done():
		b.cleanup(token)
		return PromptReply{}, errdefs.ErrSecretPromptTimeout
	case reply := <-replyChan:
		b.cleanup(token)
		if reply.Cancel {
			return reply, errdefs.ErrSecretPromptCancelled
		}
		return reply, nil
	}
}

func (b *SubscriptionBroker) Resolve(token string, reply PromptReply) error {
	replyChan, exists := b.pending.Load(token)
	if !exists {
		return fmt.Errorf("unknown or expired token: %s", token)
	}

	select {
	case replyChan <- reply:
		return nil
	default:
		return fmt.Errorf("failed to deliver reply for token: %s", token)
	}
}

func (b *SubscriptionBroker) cleanup(token string) {
	b.pending.Delete(token)
	b.requests.Delete(token)
}
