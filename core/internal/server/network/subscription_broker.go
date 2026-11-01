package network

import (
	"context"
	"fmt"

	"github.com/duxlabs-dev/dux-go/syncmap"
	"github.com/duxlabs-dev/dux-shell/core/internal/errdefs"
	"github.com/duxlabs-dev/dux-shell/core/internal/log"
)

type SubscriptionBroker struct {
	pending            syncmap.Map[string, chan PromptReply]
	requests           syncmap.Map[string, PromptRequest]
	pathSettingToToken syncmap.Map[string, string]
	broadcastPrompt    func(CredentialPrompt)
}

func NewSubscriptionBroker(broadcastPrompt func(CredentialPrompt)) PromptBroker {
	return &SubscriptionBroker{
		broadcastPrompt: broadcastPrompt,
	}
}

func (b *SubscriptionBroker) Ask(ctx context.Context, req PromptRequest) (string, error) {
	pathSettingKey := fmt.Sprintf("%s:%s", req.ConnectionPath, req.SettingName)

	if existingToken, alreadyPending := b.pathSettingToToken.Load(pathSettingKey); alreadyPending {
		log.Infof("[SubscriptionBroker] Duplicate prompt for %s, returning existing token", pathSettingKey)
		return existingToken, nil
	}

	token, err := generateToken()
	if err != nil {
		return "", err
	}

	replyChan := make(chan PromptReply, 1)
	b.pending.Store(token, replyChan)
	b.requests.Store(token, req)
	b.pathSettingToToken.Store(pathSettingKey, token)

	if b.broadcastPrompt != nil {
		prompt := CredentialPrompt{
			Token:          token,
			Name:           req.Name,
			SSID:           req.SSID,
			ConnType:       req.ConnType,
			VpnService:     req.VpnService,
			Setting:        req.SettingName,
			Fields:         req.Fields,
			FieldsInfo:     req.FieldsInfo,
			Hints:          req.Hints,
			Reason:         req.Reason,
			ConnectionId:   req.ConnectionId,
			ConnectionUuid: req.ConnectionUuid,
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
		log.Warnf("[SubscriptionBroker] Resolve: unknown or expired token: %s", token)
		return fmt.Errorf("unknown or expired token: %s", token)
	}

	select {
	case replyChan <- reply:
		return nil
	default:
		log.Warnf("[SubscriptionBroker] Resolve: failed to deliver reply for token %s (channel full or closed)", token)
		return fmt.Errorf("failed to deliver reply for token: %s", token)
	}
}

func (b *SubscriptionBroker) cleanup(token string) {
	if req, exists := b.requests.Load(token); exists {
		pathSettingKey := fmt.Sprintf("%s:%s", req.ConnectionPath, req.SettingName)
		b.pathSettingToToken.Delete(pathSettingKey)
	}

	b.pending.Delete(token)
	b.requests.Delete(token)
}

func (b *SubscriptionBroker) Cancel(path string, setting string) error {
	pathSettingKey := fmt.Sprintf("%s:%s", path, setting)

	token, exists := b.pathSettingToToken.Load(pathSettingKey)
	if !exists {
		log.Infof("[SubscriptionBroker] Cancel: no pending prompt for %s", pathSettingKey)
		return nil
	}

	log.Infof("[SubscriptionBroker] Cancelling prompt for %s (token=%s)", pathSettingKey, token)

	reply := PromptReply{
		Cancel: true,
	}

	return b.Resolve(token, reply)
}
