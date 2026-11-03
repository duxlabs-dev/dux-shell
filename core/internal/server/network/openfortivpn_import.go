package network

import (
	"bufio"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/Wifx/gonetworkmanager/v2"
	"github.com/duxlabs-dev/dux-shell/core/internal/log"
)

// openfortivpnConfig holds the parts of an openfortivpn config file that map
// onto a NetworkManager openconnect profile. openfortivpn options that only
// affect its own ppp handling are ignored.
type openfortivpnConfig struct {
	Host         string
	Port         int
	Username     string
	Password     string
	Realm        string
	TrustedCerts []string
	SAML         bool
	SAMLPort     int
}

func parseOpenfortivpnConfig(r io.Reader) (*openfortivpnConfig, error) {
	cfg := &openfortivpnConfig{Port: fortinetDefaultGatewayPort}

	scanner := bufio.NewScanner(r)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if strings.HasPrefix(line, "[") {
			return nil, fmt.Errorf("not an openfortivpn config: section header %q", line)
		}

		key, value, found := strings.Cut(line, "=")
		if !found {
			continue
		}
		key = strings.TrimSpace(key)
		value = strings.TrimSpace(value)

		switch key {
		case "host":
			cfg.Host = value
		case "port":
			port, err := strconv.Atoi(value)
			if err != nil || port < 1 || port > 65535 {
				return nil, fmt.Errorf("invalid port in openfortivpn config: %q", value)
			}
			cfg.Port = port
		case "username":
			cfg.Username = value
		case "password":
			cfg.Password = value
		case "realm":
			cfg.Realm = value
		case "trusted-cert":
			if !isCertDigest(value) {
				log.Warnf("[openfortivpn] Ignoring malformed trusted-cert digest: %q", value)
				continue
			}
			cfg.TrustedCerts = append(cfg.TrustedCerts, strings.ToLower(value))
		case "saml-login":
			port, err := strconv.Atoi(value)
			if err != nil || port < 1 || port > 65535 {
				return nil, fmt.Errorf("invalid saml-login port in openfortivpn config: %q", value)
			}
			cfg.SAML = true
			cfg.SAMLPort = port
		}
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}

	if cfg.Host == "" {
		return nil, fmt.Errorf("not an openfortivpn config: no host")
	}
	return cfg, nil
}

func isCertDigest(value string) bool {
	if len(value) != 64 {
		return false
	}
	_, err := hex.DecodeString(value)
	return err == nil
}

// profile maps the config onto the settings a Fortinet profile is built from.
// A "saml-login" line selects the browser login, and its password is dropped
// because that path never reads one. openfortivpn options that only affect its
// own ppp handling have no equivalent and are dropped too.
func (c *openfortivpnConfig) profile() fortinetProfile {
	p := fortinetProfile{
		Host:         c.Host,
		Port:         c.Port,
		Username:     c.Username,
		Realm:        c.Realm,
		SAML:         c.SAML,
		SAMLPort:     c.SAMLPort,
		TrustedCerts: c.TrustedCerts,
	}
	if c.SAML {
		return p
	}

	p.Password = c.Password
	return p
}

func (b *NetworkManagerBackend) importOpenfortivpnConfig(cfg *openfortivpnConfig, name string) (*VPNImportResult, error) {
	serviceType, err := b.openConnectServiceType()
	if err != nil {
		return &VPNImportResult{Success: false, Error: err.Error()}, nil
	}

	s := b.settings
	if s == nil {
		s, err = gonetworkmanager.NewSettings()
		if err != nil {
			return nil, fmt.Errorf("failed to get settings: %w", err)
		}
		b.settings = s
	}

	settingsMgr := s.(gonetworkmanager.Settings)
	conn, err := settingsMgr.AddConnection(buildFortinetSettings(cfg.profile(), name, serviceType))
	if err != nil {
		return &VPNImportResult{
			Success: false,
			Error:   fmt.Sprintf("failed to create VPN profile: %v", err),
		}, nil
	}

	connUUID := ""
	if created, err := conn.GetSettings(); err == nil {
		if connMeta, ok := created["connection"]; ok {
			connUUID, _ = connMeta["uuid"].(string)
		}
	}

	b.ListVPNProfiles()
	if b.onStateChange != nil {
		b.onStateChange()
	}

	return &VPNImportResult{
		Success:     true,
		UUID:        connUUID,
		Name:        name,
		ServiceType: serviceType,
	}, nil
}

// openConnectServiceType returns the installed openconnect plugin's service
// type, since a Fortinet SAML profile is useless without it.
func (b *NetworkManagerBackend) openConnectServiceType() (string, error) {
	plugins, err := b.ListVPNPlugins()
	if err != nil {
		return "", fmt.Errorf("failed to list VPN plugins: %w", err)
	}

	for _, plugin := range plugins {
		if strings.Contains(plugin.ServiceType, "openconnect") {
			return plugin.ServiceType, nil
		}
	}
	return "", fmt.Errorf("importing an openfortivpn config requires the NetworkManager openconnect plugin")
}

// readOpenfortivpnConfig returns nil when the file is not an openfortivpn
// config, so the caller can fall back to the NetworkManager importers.
func readOpenfortivpnConfig(filePath string) *openfortivpnConfig {
	file, err := os.Open(filePath)
	if err != nil {
		return nil
	}
	defer file.Close()

	cfg, err := parseOpenfortivpnConfig(file)
	if err != nil {
		log.Debugf("[openfortivpn] %s is not an openfortivpn config: %v", filePath, err)
		return nil
	}
	return cfg
}

func vpnNameFromPath(filePath string) string {
	base := filepath.Base(filePath)
	return strings.TrimSuffix(base, filepath.Ext(base))
}
