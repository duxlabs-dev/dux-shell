package network

import (
	"context"
	"errors"
	"fmt"

	"github.com/godbus/dbus/v5"
)

type openConnectActiveResolver func(context.Context, string, dbus.ObjectPath) (dbus.ObjectPath, error)

func isOpenConnectHelperEligible(service string, data map[string]string) bool {
	return service == openConnectHelperService && openConnectPasswordProtocol(data["protocol"]) == "anyconnect" && supportsOpenConnectPasswordAuth(data)
}

func (b *NetworkManagerBackend) openConnectActivePaths(ctx context.Context) ([]dbus.ObjectPath, error) {
	if b.openConnectActivePathsReader != nil {
		return b.openConnectActivePathsReader(ctx)
	}
	if b.dbusConn == nil {
		return nil, errors.New("OpenConnect activation is not available")
	}
	var value dbus.Variant
	if err := b.dbusConn.Object("org.freedesktop.NetworkManager", "/org/freedesktop/NetworkManager").CallWithContext(ctx,
		"org.freedesktop.DBus.Properties.Get", 0, "org.freedesktop.NetworkManager", "ActiveConnections").Store(&value); err != nil {
		return nil, err
	}
	paths, ok := value.Value().([]dbus.ObjectPath)
	if !ok {
		return nil, errors.New("invalid active connections")
	}
	return paths, nil
}

func (b *NetworkManagerBackend) resolveOpenConnectHelperActive(ctx context.Context, uuid string, settingsPath dbus.ObjectPath) (dbus.ObjectPath, error) {
	if b.openConnectActiveResolver != nil {
		return b.openConnectActiveResolver(ctx, uuid, settingsPath)
	}
	if uuid == "" || !settingsPath.IsValid() || settingsPath == "/" {
		return "", errors.New("OpenConnect activation is not available")
	}
	active, err := b.openConnectActivePaths(ctx)
	if err != nil {
		return "", fmt.Errorf("failed to inspect active connections: %w", err)
	}
	var matches []dbus.ObjectPath
	for _, path := range active {
		if err := ctx.Err(); err != nil {
			return "", err
		}
		if !path.IsValid() || path == "/" {
			continue
		}
		var properties map[string]dbus.Variant
		if err := b.dbusConn.Object("org.freedesktop.NetworkManager", path).CallWithContext(ctx,
			"org.freedesktop.DBus.Properties.GetAll", 0, dbusNMActiveConnInterface,
		).Store(&properties); err != nil {
			continue
		}
		candidateUUID, _ := properties["Uuid"].Value().(string)
		connection, _ := properties["Connection"].Value().(dbus.ObjectPath)
		state, _ := properties["State"].Value().(uint32)
		if candidateUUID == uuid && connection == settingsPath && state == 1 {
			matches = append(matches, path)
		}
	}
	if len(matches) != 1 {
		return "", errors.New("OpenConnect activation could not be identified")
	}
	return matches[0], nil
}

func (b *NetworkManagerBackend) getOpenConnectHelperSecrets(conn map[string]nmVariantMap, settingsPath dbus.ObjectPath, name, uuid string, flags uint32) (nmSettingMap, *dbus.Error, bool) {
	data, metadata := readOpenConnectDataAndSecrets(conn)
	if !isOpenConnectHelperEligible(openConnectHelperService, data) {
		return nil, nil, false
	}
	for _, key := range []string{"cookie-flags", "gateway-flags", "gwcert-flags", "resolve-flags"} {
		if data[key] != "2" {
			return nil, dbus.MakeFailedError(errors.New("this profile must be connected once from DMS before external activation")), true
		}
	}
	requestNew := flags&nmSecretAgentFlagRequestNew != 0
	request, err := b.beginOpenConnectHelperRequest(settingsPath, requestNew)
	if err != nil {
		return nil, dbus.MakeFailedError(err), true
	}
	defer b.endOpenConnectHelperRequest(request)
	activePath, resolveErr := b.resolveOpenConnectHelperActive(request.ctx, uuid, settingsPath)
	key := openConnectHelperAttemptKey{uuid: uuid, activePath: activePath}
	b.openConnectHelperMu.Lock()
	if err := b.resolveOpenConnectHelperRequestLocked(request, activePath); err != nil {
		b.openConnectHelperMu.Unlock()
		return nil, dbus.NewError("org.freedesktop.NetworkManager.SecretAgent.Error.UserCanceled", nil), true
	}
	if resolveErr != nil || !activePath.IsValid() || activePath == "/" {
		b.openConnectHelperMu.Unlock()
		return nil, dbus.NewError("org.freedesktop.NetworkManager.SecretAgent.Error.NoSecrets", nil), true
	}
	if flags&nmSecretAgentFlagAllowInteraction == 0 {
		result, ok := b.lookupOpenConnectHelperAttemptLocked(key, request.staleAttempt)
		b.openConnectHelperMu.Unlock()
		if ok {
			return buildOpenConnectSecretsResult("vpn", result.Secrets), nil, true
		}
		return nil, dbus.NewError("org.freedesktop.NetworkManager.SecretAgent.Error.NoSecrets", nil), true
	}
	attempt, start, err := b.openConnectAttemptLocked(key, settingsPath, request.staleAttempt)
	request.attempt = attempt
	request.ownsAttempt = start
	b.openConnectHelperMu.Unlock()
	if err != nil {
		return nil, dbus.MakeFailedError(errors.New("OpenConnect authentication is unavailable")), true
	}
	if start {
		go b.runOpenConnectHelperAttempt(key, attempt, name, data, metadata, requestNew)
	}
	result, err := b.openConnectHelperResult(request.ctx, key, attempt)
	if err != nil {
		if errors.Is(err, errOpenConnectHelperCancelled) || errors.Is(err, context.Canceled) {
			return nil, dbus.NewError("org.freedesktop.NetworkManager.SecretAgent.Error.UserCanceled", nil), true
		}
		return nil, dbus.MakeFailedError(errors.New("OpenConnect authentication failed")), true
	}
	return buildOpenConnectSecretsResult("vpn", result.Secrets), nil, true
}

func buildOpenConnectSecretsResult(setting string, secrets map[string]string) nmSettingMap {
	return buildOpenConnectSecretsResponse(setting, secrets["cookie"], secrets["gateway"], secrets["gwcert"], secrets["resolve"])
}
