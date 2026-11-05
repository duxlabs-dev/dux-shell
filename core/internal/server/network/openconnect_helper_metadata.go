package network

import (
	"context"
	"errors"
	"maps"
	"strings"
	"time"

	"github.com/AvengeMedia/DankMaterialShell/core/internal/log"
	"github.com/godbus/dbus/v5"
)

type openConnectMetadataSaver func(context.Context, openConnectHelperAttemptKey, *openConnectHelperAttempt, dbus.ObjectPath, map[string]string) error

// Local metadata errors contain only fixed messages, never profile values.
type openConnectMetadataError string

func (err openConnectMetadataError) Error() string { return string(err) }

func safeOpenConnectMetadataError(err error) string {
	for _, cause := range []error{context.Canceled, context.DeadlineExceeded} {
		if errors.Is(err, cause) {
			return cause.Error()
		}
	}
	var local openConnectMetadataError
	if errors.As(err, &local) {
		return local.Error()
	}
	var busError dbus.Error
	var busErrorPtr *dbus.Error
	if errors.As(err, &busErrorPtr) && busErrorPtr != nil {
		busError = *busErrorPtr
	} else {
		errors.As(err, &busError)
	}
	// D-Bus error bodies can echo settings or secrets; retain only the error name.
	name := busError.Name
	if len(name) > 255 || !strings.HasPrefix(name, "org.freedesktop.") {
		return "unexpected profile response"
	}
	for _, c := range name {
		if !((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '.') {
			return "unexpected profile response"
		}
	}
	return name
}

func cloneOpenConnectStrings(values map[string]string) map[string]string {
	if len(values) == 0 {
		return map[string]string{}
	}
	out := make(map[string]string, len(values))
	maps.Copy(out, values)
	return out
}

func openConnectHelperMetadata(values map[string]string) map[string]string {
	out := make(map[string]string)
	for key, value := range values {
		if value, ok := normalizeOpenConnectHelperMetadata(key, value); ok {
			out[key] = value
		}
	}
	return out
}

func readOpenConnectDataAndSecrets(conn map[string]nmVariantMap) (map[string]string, map[string]string) {
	vpn := conn["vpn"]
	data := map[string]string{}
	if value, ok := vpn["data"]; ok {
		if decoded, ok := value.Value().(map[string]string); ok {
			data = cloneOpenConnectStrings(decoded)
		}
	}
	secrets := map[string]string{}
	if value, ok := vpn["secrets"]; ok {
		if decoded, ok := value.Value().(map[string]string); ok {
			secrets = openConnectHelperMetadata(decoded)
		}
	}
	return data, secrets
}

func (b *NetworkManagerBackend) saveOpenConnectHelperMetadata(key openConnectHelperAttemptKey, attempt *openConnectHelperAttempt, metadata map[string]string) {
	if !b.ownsOpenConnectHelperAttempt(key, attempt) {
		return
	}
	saver := b.openConnectMetadataSaver
	if saver == nil {
		saver = b.persistOpenConnectHelperMetadata
	}
	ctx, cancel := context.WithTimeout(attempt.ctx, 30*time.Second)
	defer cancel()
	if err := saver(ctx, key, attempt, attempt.settingsPath, metadata); err != nil {
		log.Warnf("[OpenConnect] Could not save authentication preferences: %s", safeOpenConnectMetadataError(err))
	}
	b.openConnectHelperMu.Lock()
	defer b.openConnectHelperMu.Unlock()
	if b.openConnectHelperAttempts[key] == attempt {
		b.cancelOpenConnectHelperAttemptLocked(key, attempt)
	}
}

func (b *NetworkManagerBackend) connectionVersionID(ctx context.Context, connObj dbus.BusObject) (uint64, error) {
	var value dbus.Variant
	if err := connObj.CallWithContext(ctx, "org.freedesktop.DBus.Properties.Get", 0,
		dbusNMSettingsConnectionInterface, "VersionId").Store(&value); err != nil {
		return 0, err
	}
	version, ok := value.Value().(uint64)
	if !ok || version == 0 {
		return 0, openConnectMetadataError("invalid NetworkManager connection version")
	}
	return version, nil
}

func (b *NetworkManagerBackend) beginOpenConnectSecretRead(uuid string, path dbus.ObjectPath) func() {
	key := openConnectSecretRead{uuid: uuid, path: path}
	if uuid == "" || !path.IsValid() || path == "/" {
		return func() {}
	}
	b.openConnectSecretReadMu.Lock()
	if b.openConnectSecretReads == nil {
		b.openConnectSecretReads = make(map[openConnectSecretRead]uint)
	}
	b.openConnectSecretReads[key]++
	b.openConnectSecretReadMu.Unlock()
	return func() {
		b.openConnectSecretReadMu.Lock()
		defer b.openConnectSecretReadMu.Unlock()
		b.openConnectSecretReads[key]--
		if b.openConnectSecretReads[key] == 0 {
			delete(b.openConnectSecretReads, key)
		}
	}
}

func (b *NetworkManagerBackend) persistOpenConnectHelperMetadata(ctx context.Context, key openConnectHelperAttemptKey, attempt *openConnectHelperAttempt, settingsPath dbus.ObjectPath, metadata map[string]string) error {
	if b.dbusConn == nil || !b.ownsOpenConnectHelperAttempt(key, attempt) {
		return openConnectMetadataError("OpenConnect profile is unavailable")
	}
	connObj := b.dbusConn.Object("org.freedesktop.NetworkManager", settingsPath)
	version, err := b.connectionVersionID(ctx, connObj)
	if err != nil {
		return err
	}
	var before map[string]map[string]dbus.Variant
	if err := connObj.CallWithContext(ctx, "org.freedesktop.NetworkManager.Settings.Connection.GetSettings", 0).Store(&before); err != nil {
		return err
	}
	if before["vpn"] == nil {
		return openConnectMetadataError("OpenConnect VPN settings are missing")
	}
	storedBySetting := make(map[string]map[string]map[string]dbus.Variant)
	for _, setting := range []string{"vpn", "802-11-wireless-security", "802-1x"} {
		if before[setting] == nil {
			continue
		}
		var stored map[string]map[string]dbus.Variant
		if setting == "vpn" {
			endRead := b.beginOpenConnectSecretRead(key.uuid, settingsPath)
			err := connObj.CallWithContext(ctx, "org.freedesktop.NetworkManager.Settings.Connection.GetSecrets", 0, setting).Store(&stored)
			endRead()
			if err != nil {
				return err
			}
		} else if err := connObj.CallWithContext(ctx, "org.freedesktop.NetworkManager.Settings.Connection.GetSecrets", 0, setting).Store(&stored); err != nil {
			return err
		}
		storedBySetting[setting] = stored
		// NM processes a successful GetSecrets as one settings update, even
		// when our scoped agent reply is empty. Account for that one revision
		// without accepting unrelated concurrent edits (including secret-only
		// edits, which GetSettings cannot expose).
		if version == ^uint64(0) {
			return openConnectMetadataError("NetworkManager connection version overflow")
		}
		version++
	}
	currentVersion, err := b.connectionVersionID(ctx, connObj)
	if err != nil {
		return err
	}
	if currentVersion != version {
		return openConnectMetadataError("OpenConnect profile changed while reading secrets")
	}
	var fresh map[string]map[string]dbus.Variant
	if err := connObj.CallWithContext(ctx, "org.freedesktop.NetworkManager.Settings.Connection.GetSettings", 0).Store(&fresh); err != nil {
		return err
	}
	if !b.ownsOpenConnectHelperAttempt(key, attempt) {
		return openConnectMetadataError("OpenConnect profile changed")
	}
	freshVPN := fresh["vpn"]
	if freshVPN == nil {
		return openConnectMetadataError("OpenConnect VPN settings are missing")
	}
	freshData, ok := freshVPN["data"].Value().(map[string]string)
	if !ok {
		return openConnectMetadataError("OpenConnect VPN data is missing")
	}
	for setting, stored := range storedBySetting {
		section := fresh[setting]
		if section == nil {
			return openConnectMetadataError("OpenConnect profile settings changed")
		}
		for field, value := range stored[setting] {
			if _, exists := section[field]; !exists {
				section[field] = value
			}
		}
	}
	mergedData := cloneOpenConnectStrings(freshData)
	for _, field := range []string{"cookie", "gateway", "gwcert", "resolve"} {
		mergedData[field+"-flags"] = "2"
	}
	storedSecrets := map[string]string{}
	if storedVPN := storedBySetting["vpn"]["vpn"]; storedVPN != nil {
		if value, ok := storedVPN["secrets"]; ok {
			if decoded, ok := value.Value().(map[string]string); ok {
				storedSecrets = cloneOpenConnectStrings(decoded)
			}
		}
	}
	for _, field := range []string{"cookie", "gateway", "gwcert", "resolve"} {
		delete(storedSecrets, field)
	}
	metadata = openConnectHelperMetadata(metadata)
	maps.Copy(storedSecrets, metadata)
	for field := range storedSecrets {
		if openConnectHelperMetadataKey(field) {
			mergedData[field+"-flags"] = "0"
		}
	}
	freshVPN["data"] = dbus.MakeVariant(mergedData)
	freshVPN["secrets"] = dbus.MakeVariant(storedSecrets)
	if err := normalizeLegacyIPv6Settings(fresh["ipv6"]); err != nil {
		return err
	}
	if !b.ownsOpenConnectHelperAttempt(key, attempt) {
		return openConnectMetadataError("OpenConnect authentication was superseded")
	}
	var result map[string]dbus.Variant
	return connObj.CallWithContext(ctx, "org.freedesktop.NetworkManager.Settings.Connection.Update2", 0,
		fresh, uint32(0x1), map[string]dbus.Variant{"version-id": dbus.MakeVariant(version)}).Store(&result)
}
