package network

import (
	"context"
	"errors"
	"maps"
	"time"

	"github.com/godbus/dbus/v5"
)

const openConnectHelperAttemptTTL = 5 * time.Minute
const openConnectHelperAttemptLimit = 8
const openConnectHelperRetiredPathLimit = 64

type openConnectHelperAttemptKey struct {
	uuid       string
	activePath dbus.ObjectPath
}

type openConnectHelperAttempt struct {
	settingsPath dbus.ObjectPath
	ctx          context.Context
	cancel       context.CancelFunc
	timer        *time.Timer
	done         chan struct{}
	result       *openConnectHelperResult
	metadata     map[string]string
	err          error
	saveStarted  bool
}

type openConnectHelperRequest struct {
	settingsPath dbus.ObjectPath
	activePath   dbus.ObjectPath
	ctx          context.Context
	cancel       context.CancelFunc
	retired      map[dbus.ObjectPath]bool
	present      map[dbus.ObjectPath]bool
	staleAttempt *openConnectHelperAttempt
	attempt      *openConnectHelperAttempt
	ownsAttempt  bool
}

type openConnectHelperSnapshot struct {
	requests map[*openConnectHelperRequest]struct{}
	attempts map[openConnectHelperAttemptKey]*openConnectHelperAttempt
}

type openConnectHelperRunner func(context.Context, string, string, string, map[string]string, map[string]string, bool) (*openConnectHelperResult, error)

func (b *NetworkManagerBackend) reopenOpenConnectHelperAttempts() {
	b.openConnectHelperMu.Lock()
	b.openConnectHelperClosed = false
	b.openConnectHelperMu.Unlock()
}

func (b *NetworkManagerBackend) completedOpenConnectHelperAttemptLocked(settingsPath dbus.ObjectPath) *openConnectHelperAttempt {
	for _, attempt := range b.openConnectHelperAttempts {
		if attempt.settingsPath != settingsPath {
			continue
		}
		select {
		case <-attempt.done:
			return attempt
		default:
		}
	}
	return nil
}

func (b *NetworkManagerBackend) beginOpenConnectHelperRequest(settingsPath dbus.ObjectPath, requestNew bool) (*openConnectHelperRequest, error) {
	b.openConnectHelperMu.Lock()
	defer b.openConnectHelperMu.Unlock()
	if b.openConnectHelperClosed || len(b.openConnectHelperRequests)+len(b.openConnectHelperAttempts) >= openConnectHelperAttemptLimit {
		return nil, errors.New("OpenConnect authentication is unavailable")
	}
	ctx, cancel := context.WithTimeout(context.Background(), b.openConnectHelperAttemptDuration())
	request := &openConnectHelperRequest{settingsPath: settingsPath, ctx: ctx, cancel: cancel}
	if requestNew {
		request.staleAttempt = b.completedOpenConnectHelperAttemptLocked(settingsPath)
	}
	if b.openConnectHelperRequests == nil {
		b.openConnectHelperRequests = make(map[*openConnectHelperRequest]struct{})
	}
	b.openConnectHelperRequests[request] = struct{}{}
	return request, nil
}

func (b *NetworkManagerBackend) endOpenConnectHelperRequest(request *openConnectHelperRequest) {
	b.openConnectHelperMu.Lock()
	defer b.openConnectHelperMu.Unlock()
	delete(b.openConnectHelperRequests, request)
	request.retired = nil
	request.present = nil
	request.staleAttempt = nil
	request.cancel()
}

func (b *NetworkManagerBackend) resolveOpenConnectHelperRequestLocked(request *openConnectHelperRequest, path dbus.ObjectPath) error {
	_, registered := b.openConnectHelperRequests[request]
	invalid := !registered || b.openConnectHelperClosed || request.ctx.Err() != nil || request.retired[path] || (request.present != nil && !request.present[path])
	request.retired = nil
	request.present = nil
	if invalid {
		return errOpenConnectHelperCancelled
	}
	request.activePath = path
	return nil
}

func (b *NetworkManagerBackend) openConnectAttemptLocked(key openConnectHelperAttemptKey, settingsPath dbus.ObjectPath, stale *openConnectHelperAttempt) (*openConnectHelperAttempt, bool, error) {
	if b.openConnectHelperClosed {
		return nil, false, errors.New("OpenConnect secret agent is closed")
	}
	if b.openConnectHelperAttempts == nil {
		b.openConnectHelperAttempts = make(map[openConnectHelperAttemptKey]*openConnectHelperAttempt)
	}
	if stale != nil && b.openConnectHelperAttempts[key] == stale {
		b.cancelOpenConnectHelperAttemptLocked(key, stale)
	}
	if attempt := b.openConnectHelperAttempts[key]; attempt != nil {
		return attempt, false, nil
	}
	for existingKey, attempt := range b.openConnectHelperAttempts {
		if existingKey.uuid == key.uuid || attempt.settingsPath == settingsPath {
			return nil, false, errors.New("OpenConnect profile already has an active authentication attempt")
		}
	}
	if len(b.openConnectHelperRequests)+len(b.openConnectHelperAttempts) >= openConnectHelperAttemptLimit {
		return nil, false, errors.New("too many OpenConnect authentication attempts")
	}
	ctx, cancel := context.WithCancel(context.Background())
	attempt := &openConnectHelperAttempt{settingsPath: settingsPath, ctx: ctx, cancel: cancel, done: make(chan struct{})}
	attempt.timer = time.AfterFunc(b.openConnectHelperAttemptDuration(), func() {
		b.openConnectHelperMu.Lock()
		defer b.openConnectHelperMu.Unlock()
		if b.openConnectHelperAttempts[key] == attempt {
			b.cancelOpenConnectHelperAttemptLocked(key, attempt)
		}
	})
	b.openConnectHelperAttempts[key] = attempt
	return attempt, true, nil
}

func (b *NetworkManagerBackend) openConnectHelperAttemptDuration() time.Duration {
	if b.openConnectHelperAttemptTimeout > 0 {
		return b.openConnectHelperAttemptTimeout
	}
	return openConnectHelperAttemptTTL
}

func (b *NetworkManagerBackend) cancelOpenConnectHelperAttemptLocked(key openConnectHelperAttemptKey, attempt *openConnectHelperAttempt) {
	attempt.cancel()
	if attempt.timer != nil {
		attempt.timer.Stop()
	}
	select {
	case <-attempt.done:
	default:
		attempt.err = errOpenConnectHelperCancelled
		close(attempt.done)
	}
	attempt.result = nil
	attempt.metadata = nil
	delete(b.openConnectHelperAttempts, key)
}

func (b *NetworkManagerBackend) ownsOpenConnectHelperAttempt(key openConnectHelperAttemptKey, attempt *openConnectHelperAttempt) bool {
	b.openConnectHelperMu.Lock()
	defer b.openConnectHelperMu.Unlock()
	return b.openConnectHelperAttempts[key] == attempt
}

func (b *NetworkManagerBackend) runOpenConnectHelperAttempt(key openConnectHelperAttemptKey, attempt *openConnectHelperAttempt, name string, data, metadata map[string]string, requestNew bool) {
	runner := b.openConnectHelperRunner
	if runner == nil {
		runner = runOpenConnectAuthHelper
	}
	finder := b.openConnectHelperFinder
	if finder == nil {
		finder = findOpenConnectAuthHelper
	}
	if attempt.ctx.Err() != nil {
		return
	}
	path, err := finder()
	var result *openConnectHelperResult
	if attempt.ctx.Err() != nil {
		err = attempt.ctx.Err()
	}
	if err == nil {
		result, err = runner(attempt.ctx, path, key.uuid, name, cloneOpenConnectStrings(data), cloneOpenConnectStrings(metadata), requestNew)
	}
	if err == nil {
		if result == nil || len(result.Secrets) != 4 || result.Secrets["cookie"] == "" || !openConnectHelperGateway(result.Secrets["gateway"]) {
			err = errOpenConnectHelperMalformed
		} else {
			result = &openConnectHelperResult{Secrets: map[string]string{
				"cookie": result.Secrets["cookie"], "gateway": result.Secrets["gateway"],
				"gwcert": result.Secrets["gwcert"], "resolve": result.Secrets["resolve"],
			}, Metadata: openConnectHelperMetadata(result.Metadata)}
		}
	}

	b.openConnectHelperMu.Lock()
	defer b.openConnectHelperMu.Unlock()
	if b.openConnectHelperAttempts[key] != attempt {
		return
	}
	attempt.result = result
	attempt.err = err
	if err == nil {
		attempt.metadata = cloneOpenConnectStrings(metadata)
		maps.Copy(attempt.metadata, result.Metadata)
	}
	close(attempt.done)
}

func (b *NetworkManagerBackend) openConnectHelperResult(ctx context.Context, key openConnectHelperAttemptKey, attempt *openConnectHelperAttempt) (*openConnectHelperResult, error) {
	select {
	case <-ctx.Done():
		return nil, ctx.Err()
	case <-attempt.done:
	}
	b.openConnectHelperMu.Lock()
	defer b.openConnectHelperMu.Unlock()
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if b.openConnectHelperAttempts[key] != attempt {
		return nil, errOpenConnectHelperCancelled
	}
	if attempt.err != nil {
		return nil, attempt.err
	}
	if attempt.result == nil {
		return nil, errOpenConnectHelperCancelled
	}
	return &openConnectHelperResult{Secrets: cloneOpenConnectStrings(attempt.result.Secrets), Metadata: cloneOpenConnectStrings(attempt.result.Metadata)}, nil
}

func (b *NetworkManagerBackend) lookupOpenConnectHelperAttemptLocked(key openConnectHelperAttemptKey, stale *openConnectHelperAttempt) (*openConnectHelperResult, bool) {
	attempt := b.openConnectHelperAttempts[key]
	if attempt == nil {
		return nil, false
	}
	select {
	case <-attempt.done:
		if attempt == stale {
			b.cancelOpenConnectHelperAttemptLocked(key, attempt)
			return nil, false
		}
		if attempt.err == nil && attempt.result != nil {
			return &openConnectHelperResult{Secrets: cloneOpenConnectStrings(attempt.result.Secrets), Metadata: cloneOpenConnectStrings(attempt.result.Metadata)}, true
		}
	default:
	}
	return nil, false
}

func (b *NetworkManagerBackend) finishOpenConnectHelperSuccess(activePath dbus.ObjectPath) {
	if !activePath.IsValid() || activePath == "/" {
		return
	}
	var work []struct {
		key      openConnectHelperAttemptKey
		attempt  *openConnectHelperAttempt
		metadata map[string]string
	}
	b.openConnectHelperMu.Lock()
	b.retireOpenConnectHelperRequestsLocked(activePath)
	for key, attempt := range b.openConnectHelperAttempts {
		if key.activePath != activePath || attempt.saveStarted {
			continue
		}
		select {
		case <-attempt.done:
			if attempt.err != nil || attempt.metadata == nil {
				b.cancelOpenConnectHelperAttemptLocked(key, attempt)
				continue
			}
			attempt.saveStarted = true
			attempt.result = nil // Do not retain cookies after activation succeeds.
			work = append(work, struct {
				key      openConnectHelperAttemptKey
				attempt  *openConnectHelperAttempt
				metadata map[string]string
			}{key, attempt, cloneOpenConnectStrings(attempt.metadata)})
		default:
			b.cancelOpenConnectHelperAttemptLocked(key, attempt)
		}
	}
	b.openConnectHelperMu.Unlock()
	for _, item := range work {
		go b.saveOpenConnectHelperMetadata(item.key, item.attempt, item.metadata)
	}
}

func (b *NetworkManagerBackend) cancelOpenConnectHelperAttempts(settingsPath dbus.ObjectPath) {
	b.openConnectHelperMu.Lock()
	defer b.openConnectHelperMu.Unlock()
	for request := range b.openConnectHelperRequests {
		if request.settingsPath == settingsPath {
			request.cancel()
		}
	}
	for key, attempt := range b.openConnectHelperAttempts {
		if attempt.settingsPath == settingsPath {
			b.cancelOpenConnectHelperAttemptLocked(key, attempt)
		}
	}
}

func (b *NetworkManagerBackend) retireOpenConnectHelperRequestsLocked(activePath dbus.ObjectPath) {
	for request := range b.openConnectHelperRequests {
		if request.activePath != "" {
			if request.activePath == activePath {
				request.cancel()
			}
			continue
		}
		if request.retired == nil {
			request.retired = make(map[dbus.ObjectPath]bool)
		}
		if len(request.retired) >= openConnectHelperRetiredPathLimit && !request.retired[activePath] {
			request.cancel()
			continue
		}
		request.retired[activePath] = true
	}
}

func (b *NetworkManagerBackend) clearOpenConnectHelperAttempt(activePath dbus.ObjectPath) {
	if !activePath.IsValid() || activePath == "/" {
		return
	}
	b.openConnectHelperMu.Lock()
	defer b.openConnectHelperMu.Unlock()
	b.retireOpenConnectHelperRequestsLocked(activePath)
	for key, attempt := range b.openConnectHelperAttempts {
		if key.activePath == activePath {
			b.cancelOpenConnectHelperAttemptLocked(key, attempt)
		}
	}
}

func (b *NetworkManagerBackend) cancelAllOpenConnectHelperAttempts() {
	b.openConnectHelperMu.Lock()
	defer b.openConnectHelperMu.Unlock()
	b.openConnectHelperClosed = true
	for request := range b.openConnectHelperRequests {
		request.cancel()
	}
	for key, attempt := range b.openConnectHelperAttempts {
		b.cancelOpenConnectHelperAttemptLocked(key, attempt)
	}
}

func (b *NetworkManagerBackend) snapshotOpenConnectHelperAttempts() openConnectHelperSnapshot {
	b.openConnectHelperMu.Lock()
	defer b.openConnectHelperMu.Unlock()
	return openConnectHelperSnapshot{requests: maps.Clone(b.openConnectHelperRequests), attempts: maps.Clone(b.openConnectHelperAttempts)}
}

func (b *NetworkManagerBackend) cleanupOpenConnectHelperAttempts() {
	snapshot := b.snapshotOpenConnectHelperAttempts()
	if len(snapshot.requests) == 0 && len(snapshot.attempts) == 0 {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	active, err := b.openConnectActivePaths(ctx)
	if err == nil {
		b.reconcileOpenConnectHelperSnapshot(snapshot, active)
	}
}

func (b *NetworkManagerBackend) reconcileOpenConnectHelperSnapshot(snapshot openConnectHelperSnapshot, active []dbus.ObjectPath) {
	present := make(map[dbus.ObjectPath]bool, len(active))
	for _, path := range active {
		present[path] = true
	}
	b.openConnectHelperMu.Lock()
	defer b.openConnectHelperMu.Unlock()
	for request := range snapshot.requests {
		_, owned := b.openConnectHelperRequests[request]
		if request.activePath != "" {
			if !present[request.activePath] {
				if owned {
					request.cancel()
				}
				// The captured request may have installed an attempt while Get was in flight.
				for key, attempt := range b.openConnectHelperAttempts {
					if request.ownsAttempt && attempt == request.attempt && key.activePath == request.activePath {
						b.cancelOpenConnectHelperAttemptLocked(key, attempt)
					}
				}
			}
			continue
		}
		if !owned {
			continue
		}
		if len(present) > openConnectHelperRetiredPathLimit {
			request.cancel()
			continue
		}
		if request.present == nil {
			request.present = maps.Clone(present)
			continue
		}
		for path := range request.present {
			if !present[path] {
				delete(request.present, path)
			}
		}
	}
	for key, attempt := range snapshot.attempts {
		if !present[key.activePath] && b.openConnectHelperAttempts[key] == attempt {
			b.cancelOpenConnectHelperAttemptLocked(key, attempt)
		}
	}
}
