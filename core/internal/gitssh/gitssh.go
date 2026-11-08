package gitssh

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io/fs"
	"net"
	"net/url"
	"os"
	"path/filepath"
	"strconv"

	"github.com/go-git/go-git/v6/plumbing/client"
	"github.com/go-git/go-git/v6/plumbing/transport"
	xssh "github.com/go-git/go-git/v6/plumbing/transport/ssh"
	"github.com/go-git/go-git/v6/plumbing/transport/ssh/knownhosts"
	"github.com/kevinburke/ssh_config"
	gossh "golang.org/x/crypto/ssh"
)

func ClientOptions() []client.Option {
	return []client.Option{client.WithSSHAuth(agentAuth{})}
}

type agentAuth struct{}

func (agentAuth) ClientConfig(ctx context.Context, req *transport.Request) (*gossh.ClientConfig, error) {
	auth, err := xssh.NewSSHAgentAuth(username(req.URL))
	if err != nil {
		return nil, err
	}
	db, err := knownHostsDB()
	if err != nil {
		return nil, err
	}
	auth.HostKeyCallback = db.HostKeyCallback()
	cfg, err := auth.ClientConfig(ctx, req)
	if err != nil {
		return nil, err
	}
	cfg.HostKeyAlgorithms = db.HostKeyAlgorithms(hostWithPort(req.URL))
	if len(cfg.HostKeyAlgorithms) == 0 {
		cfg.HostKeyAlgorithms = gossh.SupportedAlgorithms().HostKeys
	}
	return cfg, nil
}

func username(u *url.URL) string {
	if u.User == nil || u.User.Username() == "" {
		return xssh.DefaultUsername
	}
	return u.User.Username()
}

func hostWithPort(u *url.URL) string {
	hostname := u.Hostname()
	port := u.Port()
	if configHost := ssh_config.Get(hostname, "Hostname"); configHost != "" {
		hostname = configHost
	}
	if port == "" {
		if configPort := ssh_config.Get(u.Hostname(), "Port"); configPort != "" {
			if _, err := strconv.Atoi(configPort); err == nil {
				port = configPort
			}
		}
	}
	if port == "" {
		port = strconv.Itoa(xssh.DefaultPort)
	}
	return net.JoinHostPort(hostname, port)
}

// x/crypto rejects a whole known_hosts file over one key type it cannot parse,
// so entries like ssh-mldsa44-ed25519 are blanked before the file is loaded.
func knownHostsDB() (*knownhosts.HostKeyDB, error) {
	dir, err := os.MkdirTemp("", "dms-known-hosts-")
	if err != nil {
		return nil, err
	}
	defer os.RemoveAll(dir)

	var filtered []string
	for i, file := range knownHostsFiles() {
		content, err := os.ReadFile(file)
		if errors.Is(err, fs.ErrNotExist) {
			continue
		}
		if err != nil {
			return nil, err
		}
		path := filepath.Join(dir, fmt.Sprintf("%d-%s", i, filepath.Base(file)))
		if err := os.WriteFile(path, blankUnparseableLines(content), 0o600); err != nil {
			return nil, err
		}
		filtered = append(filtered, path)
	}
	if len(filtered) == 0 {
		return nil, errors.New("unable to find any valid known_hosts file, set SSH_KNOWN_HOSTS env variable")
	}
	return knownhosts.NewDB(filtered...)
}

func knownHostsFiles() []string {
	if files := filepath.SplitList(os.Getenv("SSH_KNOWN_HOSTS")); len(files) != 0 {
		return files
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return []string{"/etc/ssh/ssh_known_hosts"}
	}
	return []string{filepath.Join(home, ".ssh", "known_hosts"), "/etc/ssh/ssh_known_hosts"}
}

func blankUnparseableLines(content []byte) []byte {
	lines := bytes.Split(content, []byte("\n"))
	for i, line := range lines {
		trimmed := bytes.TrimSpace(line)
		if len(trimmed) == 0 || trimmed[0] == '#' {
			continue
		}
		if _, _, _, _, _, err := gossh.ParseKnownHosts(trimmed); err != nil {
			lines[i] = nil
		}
	}
	return bytes.Join(lines, []byte("\n"))
}
