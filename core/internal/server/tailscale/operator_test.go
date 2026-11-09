package tailscale

import (
	"context"
	"errors"
	"os"
	"os/user"
	"path/filepath"
	"syscall"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

type stubInfo struct {
	os.FileInfo
	mode     os.FileMode
	uid      uint32
	foreignS bool
}

func (s stubInfo) Mode() os.FileMode { return s.mode }
func (s stubInfo) Sys() any {
	if s.foreignS {
		return struct{}{}
	}
	return &syscall.Stat_t{Uid: s.uid}
}

func rootStat(string) (os.FileInfo, error) { return stubInfo{mode: 0o755 | os.ModeSetuid}, nil }

func TestOperatorGrantArgv(t *testing.T) {
	str := func(s string) *string { return &s }
	absLook := func(n string) (string, error) { return "/usr/bin/" + n, nil }
	ts, pk := "/usr/bin/tailscale", "/usr/bin/pkexec"
	for name, tc := range map[string]struct {
		user    *string
		server  *string
		path    string
		info    stubInfo
		statErr bool
		look    func(string) (string, error)
		err     string
	}{
		"ok":                {user: str("machine$")},
		"underscore user":   {user: str("_svc")},
		"dotted user":       {user: str("first.last-2")},
		"shell user":        {user: str("x;y"), err: "unsupported user"},
		"flag user":         {user: str("-rf"), err: "unsupported user"},
		"spaced user":       {user: str("a b"), err: "unsupported user"},
		"empty user":        {user: str(""), err: "unsupported user"},
		"binary not root's": {path: ts, info: stubInfo{mode: 0o755, uid: 1000}, err: "root-owned"},
		"group-writable":    {path: ts, info: stubInfo{mode: 0o775}, err: "not writable"},
		"world-writable":    {path: ts, info: stubInfo{mode: 0o757}, err: "not writable"},
		"directory":         {path: ts, info: stubInfo{mode: os.ModeDir | 0o755}, err: "root-owned"},
		"foreign stat info": {path: ts, info: stubInfo{mode: 0o755, foreignS: true}, err: "root-owned"},
		"stat error":        {path: ts, statErr: true, err: "not usable"},
		"pkexec not setuid": {path: pk, info: stubInfo{mode: 0o755}, err: "not setuid"},
		"relative pkexec":   {look: func(n string) (string, error) { return "./" + n, nil }, err: "not found"},
		"lookup unreadable": {look: func(string) (string, error) { return "", os.ErrPermission }, err: "not usable"},
		"https server":      {server: str("https://headscale.example.com")},
		"http server, port": {server: str("http://hs.lan:8080/")},
		"default server":    {server: str("")},
		"ftp server":        {server: str("ftp://hs.lan"), err: "login server"},
		"no host":           {server: str("https://"), err: "login server"},
		"userinfo":          {server: str("https://u:p@hs.lan"), err: "login server"},
		"query":             {server: str("https://hs.lan?q"), err: "login server"},
		"fragment":          {server: str("https://hs.lan#f"), err: "login server"},
		"space":             {server: str("https://hs .lan"), err: "login server"},
		"newline":           {server: str("https://hs.lan\n"), err: "login server"},
		"flag":              {server: str("-rf"), err: "login server"},
	} {
		t.Run(name, func(t *testing.T) {
			stat := func(p string) (os.FileInfo, error) {
				if p == tc.path {
					if tc.statErr {
						return nil, os.ErrPermission
					}
					return tc.info, nil
				}
				return rootStat(p)
			}
			look := absLook
			if tc.look != nil {
				look = tc.look
			}
			u := "marlon"
			if tc.user != nil {
				u = *tc.user
			}
			cur := func() (*user.User, error) { return &user.User{Username: u}, nil }
			argv, err := operatorGrantArgv(stat, look, cur)
			want := []string{pk, ts, "set", "--operator=" + u}
			if tc.server != nil {
				argv, err = addProfileArgv(stat, look, cur, *tc.server)
				server := *tc.server
				if server == "" {
					server = defaultLoginServer
				}
				want = []string{pk, ts, "login", "--operator=" + u, "--login-server=" + server, "--timeout=1s"}
			}
			if tc.err != "" {
				require.ErrorContains(t, err, tc.err)
				return
			}
			require.NoError(t, err)
			assert.Equal(t, want, argv)
		})
	}
}

func TestGrantOperator(t *testing.T) {
	for name, tc := range map[string]struct {
		argv []string
		code int
		err  error
		want string
	}{
		"success":        {argv: []string{"pkexec"}},
		"dismissed":      {argv: []string{"pkexec"}, code: 126, want: "permission not granted: no agent"},
		"not authorized": {argv: []string{"pkexec"}, code: 127, want: "permission not granted: no agent"},
		"failure":        {argv: []string{"pkexec"}, code: 1, want: "tailscale set --operator failed: no agent"},
		"exec error":     {argv: []string{"pkexec"}, err: errors.New("boom"), want: "tailscale set --operator failed: boom"},
		"nil argv":       {want: "empty command"},
		"empty argv":     {argv: []string{}, want: "empty command"},
	} {
		t.Run(name, func(t *testing.T) {
			err := grantOperator(context.Background(), tc.argv, func(context.Context, []string) ([]byte, int, error) {
				return []byte(" no agent\n"), tc.code, tc.err
			})
			if tc.want == "" {
				require.NoError(t, err)
			} else {
				assert.EqualError(t, err, tc.want)
			}
		})
	}
}

func TestExecCommandRunner(t *testing.T) {
	_, code, err := execCommandRunner(context.Background(), []string{"sh", "-c", "exit 3"})
	require.NoError(t, err)
	assert.Equal(t, 3, code)

	_, code, err = execCommandRunner(context.Background(), []string{"/nonexistent/binary"})
	require.Error(t, err)
	assert.Equal(t, -1, code)
}

func TestLookPathResolved_RefusesDifferentBasename(t *testing.T) {
	dir := t.TempDir()
	real := filepath.Join(dir, "tailscaled")
	require.NoError(t, os.WriteFile(real, []byte("#!/bin/sh\n"), 0o755))
	require.NoError(t, os.Symlink(real, filepath.Join(dir, "tailscale")))
	t.Setenv("PATH", dir)

	_, err := lookPathResolved("tailscale")
	require.ErrorContains(t, err, "tailscaled")
}
