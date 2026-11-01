package bluez

import (
	"context"
	"errors"
	"fmt"
	"strconv"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/internal/errdefs"
	"github.com/duxlabs-dev/dux-shell/core/internal/log"
	"github.com/godbus/dbus/v5"
)

const (
	bluezService      = "org.bluez"
	agentManagerPath  = "/org/bluez"
	agentManagerIface = "org.bluez.AgentManager1"
	agent1Iface       = "org.bluez.Agent1"
	device1Iface      = "org.bluez.Device1"
	agentPath         = "/com/danklinux/bluez/agent"
	agentCapability   = "KeyboardDisplay"
)

const introspectXML = `
<node>
	<interface name="org.bluez.Agent1">
		<method name="Release"/>
		<method name="RequestPinCode">
			<arg direction="in" type="o" name="device"/>
			<arg direction="out" type="s" name="pincode"/>
		</method>
		<method name="RequestPasskey">
			<arg direction="in" type="o" name="device"/>
			<arg direction="out" type="u" name="passkey"/>
		</method>
		<method name="DisplayPinCode">
			<arg direction="in" type="o" name="device"/>
			<arg direction="in" type="s" name="pincode"/>
		</method>
		<method name="DisplayPasskey">
			<arg direction="in" type="o" name="device"/>
			<arg direction="in" type="u" name="passkey"/>
			<arg direction="in" type="q" name="entered"/>
		</method>
		<method name="RequestConfirmation">
			<arg direction="in" type="o" name="device"/>
			<arg direction="in" type="u" name="passkey"/>
		</method>
		<method name="RequestAuthorization">
			<arg direction="in" type="o" name="device"/>
		</method>
		<method name="AuthorizeService">
			<arg direction="in" type="o" name="device"/>
			<arg direction="in" type="s" name="uuid"/>
		</method>
		<method name="Cancel"/>
	</interface>
	<interface name="org.freedesktop.DBus.Introspectable">
		<method name="Introspect">
			<arg direction="out" type="s" name="data"/>
		</method>
	</interface>
</node>`

type BluezAgent struct {
	conn   *dbus.Conn
	broker PromptBroker
}

func NewBluezAgent(broker PromptBroker) (*BluezAgent, error) {
	conn, err := dbus.SystemBus()
	if err != nil {
		return nil, fmt.Errorf("system bus connection failed: %w", err)
	}

	agent := &BluezAgent{
		conn:   conn,
		broker: broker,
	}

	if err := conn.Export(agent, dbus.ObjectPath(agentPath), agent1Iface); err != nil {
		return nil, fmt.Errorf("agent export failed: %w", err)
	}

	if err := conn.Export(agent, dbus.ObjectPath(agentPath), "org.freedesktop.DBus.Introspectable"); err != nil {
		agent.unexport()
		return nil, fmt.Errorf("introspection export failed: %w", err)
	}

	mgr := conn.Object(bluezService, dbus.ObjectPath(agentManagerPath))
	if err := mgr.Call(agentManagerIface+".RegisterAgent", 0, dbus.ObjectPath(agentPath), agentCapability).Err; err != nil {
		agent.unexport()
		return nil, fmt.Errorf("agent registration failed: %w", err)
	}

	if err := mgr.Call(agentManagerIface+".RequestDefaultAgent", 0, dbus.ObjectPath(agentPath)).Err; err != nil {
		log.Debugf("[BluezAgent] not default agent: %v", err)
	}

	log.Infof("[BluezAgent] registered at %s with capability %s", agentPath, agentCapability)
	return agent, nil
}

func (a *BluezAgent) Close() {
	if a.conn == nil {
		return
	}
	mgr := a.conn.Object(bluezService, dbus.ObjectPath(agentManagerPath))
	mgr.Call(agentManagerIface+".UnregisterAgent", 0, dbus.ObjectPath(agentPath))
	a.unexport()
}

func (a *BluezAgent) unexport() {
	_ = a.conn.Export(nil, dbus.ObjectPath(agentPath), agent1Iface)
	_ = a.conn.Export(nil, dbus.ObjectPath(agentPath), "org.freedesktop.DBus.Introspectable")
}

func (a *BluezAgent) Release() *dbus.Error {
	log.Infof("[BluezAgent] Release called")
	return nil
}

func (a *BluezAgent) RequestPinCode(device dbus.ObjectPath) (string, *dbus.Error) {
	log.Infof("[BluezAgent] RequestPinCode: device=%s", device)

	secrets, err := a.promptFor(device, "pin", []string{"pin"}, nil)
	if err != nil {
		log.Warnf("[BluezAgent] RequestPinCode failed: %v", err)
		return "", a.errorFrom(err)
	}

	pin := secrets["pin"]
	log.Infof("[BluezAgent] RequestPinCode returning PIN (len=%d)", len(pin))
	return pin, nil
}

func (a *BluezAgent) RequestPasskey(device dbus.ObjectPath) (uint32, *dbus.Error) {
	log.Infof("[BluezAgent] RequestPasskey: device=%s", device)

	secrets, err := a.promptFor(device, "passkey", []string{"passkey"}, nil)
	if err != nil {
		log.Warnf("[BluezAgent] RequestPasskey failed: %v", err)
		return 0, a.errorFrom(err)
	}

	passkey, err := strconv.ParseUint(secrets["passkey"], 10, 32)
	if err != nil {
		log.Warnf("[BluezAgent] invalid passkey format: %v", err)
		return 0, dbus.MakeFailedError(fmt.Errorf("invalid passkey: %w", err))
	}

	log.Infof("[BluezAgent] RequestPasskey returning: %d", passkey)
	return uint32(passkey), nil
}

func (a *BluezAgent) DisplayPinCode(device dbus.ObjectPath, pincode string) *dbus.Error {
	log.Infof("[BluezAgent] DisplayPinCode: device=%s, pin=%s", device, pincode)

	_, err := a.promptFor(device, "display-pin", []string{}, &pincode)
	if err != nil {
		log.Warnf("[BluezAgent] DisplayPinCode acknowledgment failed: %v", err)
	}

	return nil
}

func (a *BluezAgent) DisplayPasskey(device dbus.ObjectPath, passkey uint32, entered uint16) *dbus.Error {
	log.Infof("[BluezAgent] DisplayPasskey: device=%s, passkey=%06d, entered=%d", device, passkey, entered)

	if entered == 0 {
		passkeyStr := strconv.FormatUint(uint64(passkey), 10)
		_, err := a.promptFor(device, "display-passkey", []string{}, &passkeyStr)
		if err != nil {
			log.Warnf("[BluezAgent] DisplayPasskey acknowledgment failed: %v", err)
		}
	}

	return nil
}

func (a *BluezAgent) RequestConfirmation(device dbus.ObjectPath, passkey uint32) *dbus.Error {
	log.Infof("[BluezAgent] RequestConfirmation: device=%s, passkey=%06d", device, passkey)

	passkeyStr := strconv.FormatUint(uint64(passkey), 10)
	secrets, err := a.promptFor(device, "confirm", []string{"decision"}, &passkeyStr)
	if err != nil {
		log.Warnf("[BluezAgent] RequestConfirmation failed: %v", err)
		return a.errorFrom(err)
	}

	if secrets["decision"] != "yes" && secrets["decision"] != "accept" {
		log.Debugf("[BluezAgent] RequestConfirmation rejected by user")
		return dbus.NewError("org.bluez.Error.Rejected", nil)
	}

	log.Infof("[BluezAgent] RequestConfirmation accepted")
	return nil
}

func (a *BluezAgent) RequestAuthorization(device dbus.ObjectPath) *dbus.Error {
	log.Infof("[BluezAgent] RequestAuthorization: device=%s", device)

	secrets, err := a.promptFor(device, "authorize", []string{"decision"}, nil)
	if err != nil {
		log.Warnf("[BluezAgent] RequestAuthorization failed: %v", err)
		return a.errorFrom(err)
	}

	if secrets["decision"] != "yes" && secrets["decision"] != "accept" {
		log.Debugf("[BluezAgent] RequestAuthorization rejected by user")
		return dbus.NewError("org.bluez.Error.Rejected", nil)
	}

	log.Infof("[BluezAgent] RequestAuthorization accepted")
	return nil
}

func (a *BluezAgent) AuthorizeService(device dbus.ObjectPath, uuid string) *dbus.Error {
	log.Infof("[BluezAgent] AuthorizeService: device=%s, uuid=%s", device, uuid)

	secrets, err := a.promptFor(device, "authorize-service:"+uuid, []string{"decision"}, nil)
	if err != nil {
		log.Warnf("[BluezAgent] AuthorizeService failed: %v", err)
		return a.errorFrom(err)
	}

	if secrets["decision"] != "yes" && secrets["decision"] != "accept" {
		log.Debugf("[BluezAgent] AuthorizeService rejected by user")
		return dbus.NewError("org.bluez.Error.Rejected", nil)
	}

	log.Infof("[BluezAgent] AuthorizeService accepted")
	return nil
}

func (a *BluezAgent) Cancel() *dbus.Error {
	log.Infof("[BluezAgent] Cancel called")
	return nil
}

func (a *BluezAgent) Introspect() (string, *dbus.Error) {
	return introspectXML, nil
}

func (a *BluezAgent) promptFor(device dbus.ObjectPath, requestType string, fields []string, displayValue *string) (map[string]string, error) {
	if a.broker == nil {
		return nil, fmt.Errorf("broker not initialized")
	}

	deviceName, deviceAddr := a.getDeviceInfo(device)
	hints := []string{}
	if displayValue != nil {
		hints = append(hints, *displayValue)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()

	var passkey *uint32
	if requestType == "confirm" || requestType == "display-passkey" {
		if displayValue != nil {
			if pk, err := strconv.ParseUint(*displayValue, 10, 32); err == nil {
				pk32 := uint32(pk)
				passkey = &pk32
			}
		}
	}

	token, err := a.broker.Ask(ctx, PromptRequest{
		DevicePath:  string(device),
		DeviceName:  deviceName,
		DeviceAddr:  deviceAddr,
		RequestType: requestType,
		Fields:      fields,
		Hints:       hints,
		Passkey:     passkey,
	})
	if err != nil {
		return nil, fmt.Errorf("prompt creation failed: %w", err)
	}

	log.Infof("[BluezAgent] waiting for user response (token=%s)", token)
	reply, err := a.broker.Wait(ctx, token)
	if err != nil {
		if errors.Is(err, errdefs.ErrSecretPromptTimeout) {
			return nil, err
		}
		if reply.Cancel || errors.Is(err, errdefs.ErrSecretPromptCancelled) {
			return nil, errdefs.ErrSecretPromptCancelled
		}
		return nil, err
	}

	if !reply.Accept && len(fields) > 0 {
		return nil, errdefs.ErrSecretPromptCancelled
	}

	return reply.Secrets, nil
}

func (a *BluezAgent) getDeviceInfo(device dbus.ObjectPath) (string, string) {
	obj := a.conn.Object(bluezService, device)

	var name, alias, addr string

	nameVar, err := obj.GetProperty(device1Iface + ".Name")
	if err == nil {
		if n, ok := nameVar.Value().(string); ok {
			name = n
		}
	}

	aliasVar, err := obj.GetProperty(device1Iface + ".Alias")
	if err == nil {
		if a, ok := aliasVar.Value().(string); ok {
			alias = a
		}
	}

	addrVar, err := obj.GetProperty(device1Iface + ".Address")
	if err == nil {
		if a, ok := addrVar.Value().(string); ok {
			addr = a
		}
	}

	if alias != "" {
		return alias, addr
	}
	if name != "" {
		return name, addr
	}
	return addr, addr
}

func (a *BluezAgent) errorFrom(err error) *dbus.Error {
	if errors.Is(err, errdefs.ErrSecretPromptTimeout) {
		return dbus.NewError("org.bluez.Error.Canceled", nil)
	}
	if errors.Is(err, errdefs.ErrSecretPromptCancelled) {
		return dbus.NewError("org.bluez.Error.Canceled", nil)
	}
	return dbus.MakeFailedError(err)
}
