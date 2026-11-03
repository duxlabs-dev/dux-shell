package network

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/internal/errdefs"
	"github.com/godbus/dbus/v5"
)

const (
	iwdAgentManagerPath  = "/net/connman/iwd"
	iwdAgentManagerIface = "net.connman.iwd.AgentManager"
	iwdAgentInterface    = "net.connman.iwd.Agent"
	iwdAgentObjectPath   = "/com/danklinux/iwdagent"
)

type ConnectionStateChecker interface {
	IsConnectingTo(ssid string) bool
}

type IWDAgent struct {
	conn              *dbus.Conn
	objPath           dbus.ObjectPath
	prompts           PromptBroker
	onUserCanceled    func()
	onPromptRetry     func(ssid string)
	takePendingSecret func(ssid string) (string, bool)
	lastRequestSSID   string
	stateChecker      ConnectionStateChecker
}

const iwdAgentIntrospectXML = `
<node>
	<interface name="net.connman.iwd.Agent">
		<method name="Release">
			<annotation name="org.freedesktop.DBus.Method.NoReply" value="true"/>
		</method>
		<method name="RequestPassphrase">
			<arg type="o" name="network" direction="in"/>
			<arg type="s" name="passphrase" direction="out"/>
		</method>
		<method name="RequestPrivateKeyPassphrase">
			<arg type="o" name="network" direction="in"/>
			<arg type="s" name="passphrase" direction="out"/>
		</method>
		<method name="RequestUserNameAndPassword">
			<arg type="o" name="network" direction="in"/>
			<arg type="s" name="username" direction="out"/>
			<arg type="s" name="password" direction="out"/>
		</method>
		<method name="RequestUserPassword">
			<arg type="o" name="network" direction="in"/>
			<arg type="s" name="user" direction="in"/>
			<arg type="s" name="password" direction="out"/>
		</method>
		<method name="Cancel">
			<arg type="s" name="reason" direction="in"/>
			<annotation name="org.freedesktop.DBus.Method.NoReply" value="true"/>
		</method>
	</interface>
</node>`

func NewIWDAgent(conn *dbus.Conn, prompts PromptBroker) (*IWDAgent, error) {
	if conn == nil {
		return nil, fmt.Errorf("dbus connection is nil")
	}

	agent := &IWDAgent{
		conn:    conn,
		objPath: dbus.ObjectPath(iwdAgentObjectPath),
		prompts: prompts,
	}

	if err := conn.Export(agent, agent.objPath, iwdAgentInterface); err != nil {
		return nil, fmt.Errorf("failed to export IWD agent: %w", err)
	}

	if err := conn.Export(agent, agent.objPath, "org.freedesktop.DBus.Introspectable"); err != nil {
		return nil, fmt.Errorf("failed to export introspection: %w", err)
	}

	mgr := conn.Object("net.connman.iwd", dbus.ObjectPath(iwdAgentManagerPath))
	call := mgr.Call(iwdAgentManagerIface+".RegisterAgent", 0, agent.objPath)
	if call.Err != nil {
		return nil, fmt.Errorf("failed to register agent with iwd: %w", call.Err)
	}

	return agent, nil
}

func (a *IWDAgent) Close() {
	if a.conn == nil {
		return
	}
	mgr := a.conn.Object("net.connman.iwd", dbus.ObjectPath(iwdAgentManagerPath))
	mgr.Call(iwdAgentManagerIface+".UnregisterAgent", 0, a.objPath)
	_ = a.conn.Export(nil, a.objPath, iwdAgentInterface)
	_ = a.conn.Export(nil, a.objPath, "org.freedesktop.DBus.Introspectable")
}

func (a *IWDAgent) SetStateChecker(checker ConnectionStateChecker) {
	a.stateChecker = checker
}

func (a *IWDAgent) getNetworkName(networkPath dbus.ObjectPath) string {
	netObj := a.conn.Object("net.connman.iwd", networkPath)
	nameVar, err := netObj.GetProperty("net.connman.iwd.Network.Name")
	if err == nil {
		if name, ok := nameVar.Value().(string); ok {
			return name
		}
	}
	return string(networkPath)
}

func (a *IWDAgent) RequestPassphrase(network dbus.ObjectPath) (string, *dbus.Error) {
	ssid := a.getNetworkName(network)

	if a.stateChecker != nil && !a.stateChecker.IsConnectingTo(ssid) {
		return "", dbus.NewError("net.connman.iwd.Agent.Error.Canceled", nil)
	}

	if a.takePendingSecret != nil {
		if psk, ok := a.takePendingSecret(ssid); ok {
			a.lastRequestSSID = ssid
			return psk, nil
		}
	}

	if a.prompts == nil {
		if a.onUserCanceled != nil {
			a.onUserCanceled()
		}
		return "", dbus.NewError("net.connman.iwd.Agent.Error.Canceled", nil)
	}

	retry := a.lastRequestSSID == ssid
	if retry && a.onPromptRetry != nil {
		a.onPromptRetry(ssid)
	}
	a.lastRequestSSID = ssid

	reason := ""
	if retry {
		reason = "wrong-password"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()

	token, err := a.prompts.Ask(ctx, PromptRequest{
		SSID:   ssid,
		Fields: []string{"psk"},
		Reason: reason,
	})
	if err != nil {
		if a.onUserCanceled != nil {
			a.onUserCanceled()
		}
		return "", dbus.NewError("net.connman.iwd.Agent.Error.Canceled", nil)
	}

	reply, err := a.prompts.Wait(ctx, token)
	if err != nil {
		if reply.Cancel || errors.Is(err, errdefs.ErrSecretPromptCancelled) {
			if a.onUserCanceled != nil {
				a.onUserCanceled()
			}
		}
		return "", dbus.NewError("net.connman.iwd.Agent.Error.Canceled", nil)
	}

	if passphrase, ok := reply.Secrets["psk"]; ok {
		return passphrase, nil
	}

	if a.onUserCanceled != nil {
		a.onUserCanceled()
	}
	return "", dbus.NewError("net.connman.iwd.Agent.Error.Canceled", nil)
}

func (a *IWDAgent) RequestPrivateKeyPassphrase(network dbus.ObjectPath) (string, *dbus.Error) {
	ssid := a.getNetworkName(network)

	if a.stateChecker != nil && !a.stateChecker.IsConnectingTo(ssid) {
		return "", dbus.NewError("net.connman.iwd.Agent.Error.Canceled", nil)
	}

	if a.prompts == nil {
		return "", dbus.NewError("net.connman.iwd.Agent.Error.Canceled", nil)
	}

	if a.lastRequestSSID == ssid {
		if a.onPromptRetry != nil {
			a.onPromptRetry(ssid)
		}
	}
	a.lastRequestSSID = ssid

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()

	token, err := a.prompts.Ask(ctx, PromptRequest{
		SSID:   ssid,
		Fields: []string{"private-key-password"},
	})
	if err != nil {
		return "", dbus.NewError("net.connman.iwd.Agent.Error.Canceled", nil)
	}

	reply, err := a.prompts.Wait(ctx, token)
	if err != nil || reply.Cancel {
		return "", dbus.NewError("net.connman.iwd.Agent.Error.Canceled", nil)
	}

	if passphrase, ok := reply.Secrets["private-key-password"]; ok {
		return passphrase, nil
	}

	return "", dbus.NewError("net.connman.iwd.Agent.Error.Canceled", nil)
}

func (a *IWDAgent) RequestUserNameAndPassword(network dbus.ObjectPath) (string, string, *dbus.Error) {
	ssid := a.getNetworkName(network)

	if a.stateChecker != nil && !a.stateChecker.IsConnectingTo(ssid) {
		return "", "", dbus.NewError("net.connman.iwd.Agent.Error.Canceled", nil)
	}

	if a.prompts == nil {
		return "", "", dbus.NewError("net.connman.iwd.Agent.Error.Canceled", nil)
	}

	if a.lastRequestSSID == ssid {
		if a.onPromptRetry != nil {
			a.onPromptRetry(ssid)
		}
	}
	a.lastRequestSSID = ssid

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()

	token, err := a.prompts.Ask(ctx, PromptRequest{
		SSID:   ssid,
		Fields: []string{"identity", "password"},
	})
	if err != nil {
		return "", "", dbus.NewError("net.connman.iwd.Agent.Error.Canceled", nil)
	}

	reply, err := a.prompts.Wait(ctx, token)
	if err != nil || reply.Cancel {
		return "", "", dbus.NewError("net.connman.iwd.Agent.Error.Canceled", nil)
	}

	username, hasUser := reply.Secrets["identity"]
	password, hasPass := reply.Secrets["password"]

	if hasUser && hasPass {
		return username, password, nil
	}

	return "", "", dbus.NewError("net.connman.iwd.Agent.Error.Canceled", nil)
}

func (a *IWDAgent) RequestUserPassword(network dbus.ObjectPath, user string) (string, *dbus.Error) {
	ssid := a.getNetworkName(network)

	if a.stateChecker != nil && !a.stateChecker.IsConnectingTo(ssid) {
		return "", dbus.NewError("net.connman.iwd.Agent.Error.Canceled", nil)
	}

	if a.prompts == nil {
		return "", dbus.NewError("net.connman.iwd.Agent.Error.Canceled", nil)
	}

	if a.lastRequestSSID == ssid {
		if a.onPromptRetry != nil {
			a.onPromptRetry(ssid)
		}
	}
	a.lastRequestSSID = ssid

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()

	token, err := a.prompts.Ask(ctx, PromptRequest{
		SSID:   ssid,
		Fields: []string{"password"},
	})
	if err != nil {
		return "", dbus.NewError("net.connman.iwd.Agent.Error.Canceled", nil)
	}

	reply, err := a.prompts.Wait(ctx, token)
	if err != nil || reply.Cancel {
		return "", dbus.NewError("net.connman.iwd.Agent.Error.Canceled", nil)
	}

	if password, ok := reply.Secrets["password"]; ok {
		return password, nil
	}

	return "", dbus.NewError("net.connman.iwd.Agent.Error.Canceled", nil)
}

func (a *IWDAgent) Cancel(reason string) *dbus.Error {
	return nil
}

func (a *IWDAgent) Release() *dbus.Error {
	return nil
}

func (a *IWDAgent) Introspect() (string, *dbus.Error) {
	return iwdAgentIntrospectXML, nil
}
