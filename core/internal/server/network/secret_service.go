package network

import (
	"context"
	"fmt"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/godbus/dbus/v5"
)

const (
	secretServiceBusName        = "org.freedesktop.secrets"
	secretServicePath           = "/org/freedesktop/secrets"
	secretServiceIface          = "org.freedesktop.Secret.Service"
	secretServiceSessionIface   = "org.freedesktop.Secret.Session"
	secretCollectionIface       = "org.freedesktop.Secret.Collection"
	secretItemIface             = "org.freedesktop.Secret.Item"
	secretPromptIface           = "org.freedesktop.Secret.Prompt"
	secretDefaultCollectionPath = "/org/freedesktop/secrets/aliases/default"
	nmSecretXdgSchema           = "org.freedesktop.NetworkManager.Connection"
)

type secretServiceSession struct {
	conn        *dbus.Conn
	svc         dbus.BusObject
	sessionPath dbus.ObjectPath
}

func openSecretService() (*secretServiceSession, error) {
	c, err := dbus.SessionBus()
	if err != nil {
		return nil, err
	}

	svc := c.Object(secretServiceBusName, dbus.ObjectPath(secretServicePath))

	var sessionPath dbus.ObjectPath
	call := svc.Call(secretServiceIface+".OpenSession", 0, "plain", dbus.MakeVariant(""))
	if call.Err != nil {
		return nil, call.Err
	}
	if err := call.Store(new(dbus.Variant), &sessionPath); err != nil {
		return nil, err
	}

	return &secretServiceSession{
		conn:        c,
		svc:         svc,
		sessionPath: sessionPath,
	}, nil
}

func (s *secretServiceSession) unlock(items []dbus.ObjectPath) error {
	var prompt dbus.ObjectPath
	var unlocked []dbus.ObjectPath
	call := s.svc.Call(secretServiceIface+".Unlock", 0, items)
	if call.Err != nil {
		return call.Err
	}
	if err := call.Store(&unlocked, &prompt); err != nil {
		return err
	}
	if prompt == "/" {
		return nil
	}

	if err := s.conn.AddMatchSignal(
		dbus.WithMatchInterface(secretPromptIface),
		dbus.WithMatchObjectPath(prompt),
	); err != nil {
		return err
	}
	defer s.conn.RemoveMatchSignal(
		dbus.WithMatchInterface(secretPromptIface),
		dbus.WithMatchObjectPath(prompt),
	)

	ctx, cancel := context.WithTimeout(context.Background(), 120*time.Second)
	defer cancel()

	ch := make(chan *dbus.Signal, 10)
	s.conn.Signal(ch)

	go func() {
		defer s.conn.RemoveSignal(ch)
		for {
			select {
			case v := <-ch:
				if v.Path == prompt && v.Name == secretPromptIface+".Completed" {
					if len(v.Body) < 2 {
						log.Debugf("[SecretAgent] Unlock prompt Completed signal has %d body element(s), expected >= 2", len(v.Body))
					} else {
						if dismissed, ok := v.Body[0].(bool); ok && dismissed {
							log.Debugf("[SecretAgent] Unlock prompt dismissed by user")
						}
					}
					cancel()
					return
				}
			case <-ctx.Done():
				return
			}
		}
	}()

	promptObj := s.conn.Object(secretServiceBusName, prompt)
	if err := promptObj.Call(secretPromptIface+".Prompt", 0, "").Store(); err != nil {
		cancel()
		return err
	}

	<-ctx.Done()
	if ctx.Err() == context.DeadlineExceeded {
		promptObj.Call(secretPromptIface+".Dismiss", 0)
		return fmt.Errorf("timed out waiting for unlock prompt")
	}
	return nil
}

func (s *secretServiceSession) lookup(connUuid, settingName, settingKey string) string {
	attrs := map[string]string{
		"connection-uuid": connUuid,
		"setting-name":    settingName,
		"setting-key":     settingKey,
	}

	var unlocked []dbus.ObjectPath
	var locked []dbus.ObjectPath
	call := s.svc.Call(secretServiceIface+".SearchItems", 0, attrs)
	if call.Err != nil {
		log.Debugf("[SecretAgent] Secret service SearchItems failed: %v", call.Err)
		return ""
	}
	if err := call.Store(&unlocked, &locked); err != nil {
		log.Debugf("[SecretAgent] Failed to store SearchItems result: %v", err)
		return ""
	}

	if len(unlocked) == 0 && len(locked) > 0 {
		log.Debugf("[SecretAgent] Attempting to unlock %d locked item(s) for %s", len(locked), connUuid)
		if err := s.unlock(locked); err != nil {
			log.Debugf("[SecretAgent] Failed to unlock items: %v", err)
			return ""
		}
		unlocked = locked
	}

	if len(unlocked) == 0 {
		log.Debugf("[SecretAgent] No secret service items found for %s", connUuid)
		return ""
	}

	item := s.conn.Object(secretServiceBusName, unlocked[0])
	var secret struct {
		Session     dbus.ObjectPath
		Parameters  []byte
		Value       []byte
		ContentType string
	}
	call = item.Call(secretItemIface+".GetSecret", 0, s.sessionPath)
	if call.Err != nil {
		log.Debugf("[SecretAgent] Secret service GetSecret failed: %v", call.Err)
		return ""
	}
	if err := call.Store(&secret); err != nil {
		log.Debugf("[SecretAgent] Failed to store GetSecret result: %v", err)
		return ""
	}

	secretValue := string(secret.Value)
	if secretValue == "" {
		log.Debugf("[SecretAgent] Secret service returned empty value for %s/%s", connUuid, settingKey)
		return ""
	}

	log.Infof("[SecretAgent] Retrieved secret from secret service for %s/%s", connUuid, settingKey)
	return secretValue
}

func (s *secretServiceSession) store(connUuid, settingName, settingKey, label, value string) error {
	coll := s.conn.Object(secretServiceBusName, dbus.ObjectPath(secretDefaultCollectionPath))

	if err := s.unlock([]dbus.ObjectPath{dbus.ObjectPath(secretDefaultCollectionPath)}); err != nil {
		return fmt.Errorf("failed to unlock default collection: %w", err)
	}

	props := map[string]dbus.Variant{
		"org.freedesktop.Secret.Item.Label": dbus.MakeVariant(label),
		"org.freedesktop.Secret.Item.Attributes": dbus.MakeVariant(map[string]string{
			"xdg:schema":      nmSecretXdgSchema,
			"connection-uuid": connUuid,
			"setting-name":    settingName,
			"setting-key":     settingKey,
		}),
	}
	secret := struct {
		Session     dbus.ObjectPath
		Parameters  []byte
		Value       []byte
		ContentType string
	}{s.sessionPath, []byte{}, []byte(value), "text/plain"}

	var itemPath, promptPath dbus.ObjectPath
	call := coll.Call(secretCollectionIface+".CreateItem", 0, props, secret, true)
	if call.Err != nil {
		return call.Err
	}
	if err := call.Store(&itemPath, &promptPath); err != nil {
		return err
	}
	if itemPath == "/" {
		return fmt.Errorf("collection requires a prompt to create item")
	}
	return nil
}

func (s *secretServiceSession) deleteAll(connUuid string) {
	attrs := map[string]string{"connection-uuid": connUuid}

	var unlocked, locked []dbus.ObjectPath
	call := s.svc.Call(secretServiceIface+".SearchItems", 0, attrs)
	if call.Err != nil {
		log.Debugf("[SecretAgent] deleteAll SearchItems failed: %v", call.Err)
		return
	}
	if err := call.Store(&unlocked, &locked); err != nil {
		log.Debugf("[SecretAgent] deleteAll failed to store SearchItems result: %v", err)
		return
	}

	for _, path := range append(unlocked, locked...) {
		item := s.conn.Object(secretServiceBusName, path)
		if call := item.Call(secretItemIface+".Delete", 0); call.Err != nil {
			log.Debugf("[SecretAgent] deleteAll failed to delete %s: %v", path, call.Err)
		}
	}
}

func (s *secretServiceSession) close() {
	s.conn.Object(secretServiceBusName, s.sessionPath).Call(secretServiceSessionIface+".Close", 0)
}

func (a *SecretAgent) trySecretService(
	connUuid string,
	settingName string,
	fields []string,
) nmSettingMap {
	if connUuid == "" {
		log.Debugf("[SecretAgent] trySecretService: connUuid is empty, skipping keyring lookup")
		return nil
	}
	if len(fields) == 0 {
		log.Debugf("[SecretAgent] trySecretService: no fields requested, skipping keyring lookup")
		return nil
	}

	switch settingName {
	case "802-11-wireless-security", "802-1x", "vpn", "wireguard":
	default:
		log.Debugf("[SecretAgent] trySecretService: setting %s not supported for keyring lookup", settingName)
		return nil
	}

	sess, err := openSecretService()
	if err != nil {
		log.Debugf("[SecretAgent] Failed to open secret service session: %v", err)
		return nil
	}
	defer sess.close()

	found := make(map[string]string)
	for _, field := range fields {
		val := sess.lookup(connUuid, settingName, field)
		if val == "" {
			log.Debugf("[SecretAgent] Secret service missing field '%s' for %s", field, connUuid)
			return nil
		}
		found[field] = val
	}

	out := nmSettingMap{}
	sec := nmVariantMap{}
	for k, v := range found {
		sec[k] = dbus.MakeVariant(v)
	}

	switch settingName {
	case "vpn":
		secretsDict := make(map[string]string)
		for k, v := range found {
			if k != "username" {
				secretsDict[k] = v
			}
		}
		vpnSec := nmVariantMap{}
		vpnSec["secrets"] = dbus.MakeVariant(secretsDict)
		out[settingName] = vpnSec
		log.Infof("[SecretAgent] Returning VPN secrets from secret service with %d fields", len(secretsDict))
	case "802-1x":
		secretsOnly := nmVariantMap{}
		for k, v := range found {
			switch k {
			case "password", "private-key-password", "phase2-private-key-password", "pin":
				secretsOnly[k] = dbus.MakeVariant(v)
			}
		}
		out[settingName] = secretsOnly
		log.Infof("[SecretAgent] Returning 802-1x secrets from secret service with %d fields", len(secretsOnly))
	default:
		out[settingName] = sec
		log.Infof("[SecretAgent] Returning %s secrets from secret service", settingName)
	}

	return out
}
