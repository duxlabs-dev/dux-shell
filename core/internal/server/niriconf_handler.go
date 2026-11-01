package server

import (
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/duxlabs-dev/dux-go/ipc"
	"github.com/duxlabs-dev/dux-go/ipc/params"
	"github.com/duxlabs-dev/dux-shell/core/internal/niriconf"
)

// The socket only touches the page's fragments: DMS writes the other dms/*.kdl elsewhere.
const (
	niriPageFragment    = "niri.kdl"
	niriCustomFragment  = "niri-custom.kdl"
	maxNiriFragmentSize = 256 << 10
)

var errNiriTooLarge = errors.New("too large")

var niriConfigStore = sync.OnceValue(newNiriConfigStore)

func newNiriConfigStore() *niriconf.Store {
	configDir, err := os.UserConfigDir()
	if err != nil {
		configDir = filepath.Join(os.Getenv("HOME"), ".config")
	}
	store := &niriconf.Store{ConfigDir: filepath.Join(configDir, "niri")}
	if socket := os.Getenv("NIRI_SOCKET"); socket != "" {
		store.Events = niriconf.SocketEvents{Socket: socket}
	}
	return store
}

type niriConfigVersion struct {
	N      int       `json:"n"`
	Time   time.Time `json:"time"`
	Hash   string    `json:"hash"`
	Failed bool      `json:"failed"`
}

type niriConfigApplied struct {
	Version int    `json:"version"`
	Hash    string `json:"hash"`
}

// niriConfigError keeps paths out: they carry the account name to the screen and logs.
func niriConfigError(err error) string {
	var invalid *niriconf.InvalidError
	var pathErr *fs.PathError
	var linkErr *os.LinkError
	switch {
	case errors.Is(err, niriconf.ErrChanged):
		return "changed"
	case errors.As(err, &invalid):
		return "invalid: " + invalid.Output
	case errors.Is(err, niriconf.ErrReloadFailed):
		return "reload failed"
	case errors.Is(err, niriconf.ErrBadName):
		return "bad name"
	case errors.As(err, &pathErr):
		return pathErr.Op + ": " + pathErr.Err.Error()
	case errors.As(err, &linkErr):
		return linkErr.Op + ": " + linkErr.Err.Error()
	}
	return err.Error()
}

// niriConfigFragment reads the fragment param, limited to the page's main fragment
// unless also is set (history may list the custom one too).
func niriConfigFragment(req ipc.Request, also string) (string, error) {
	fragment, err := params.String(req.Params, "fragment")
	if err != nil {
		return "", err
	}
	if fragment != niriPageFragment && (also == "" || fragment != also) {
		return "", niriconf.ErrBadName
	}
	return fragment, nil
}

func handleNiriConfigRead(conn *ipc.ConnWriter, req ipc.Request) {
	fragment, err := niriConfigFragment(req, "")
	if err != nil {
		conn.RespondError(req.ID, niriConfigError(err))
		return
	}
	content, hash, err := niriConfigStore().Read(fragment, niriCustomFragment)
	if err != nil {
		conn.RespondError(req.ID, niriConfigError(err))
		return
	}
	conn.Respond(req.ID, map[string]string{"content": content, "hash": hash})
}

// niriConfigExtra takes only the custom fragment: the main one includes it, so config.kdl needs no line for it.
func niriConfigExtra(req ipc.Request) ([]niriconf.Fragment, error) {
	extra := params.StringMapOpt(req.Params, "extra")
	custom, ok := extra[niriCustomFragment]
	if len(extra) != 1 || !ok {
		return nil, niriconf.ErrBadName
	}
	if len(custom) > maxNiriFragmentSize {
		return nil, errNiriTooLarge
	}
	return []niriconf.Fragment{{Name: niriCustomFragment, Content: custom}}, nil
}

func handleNiriConfigApply(conn *ipc.ConnWriter, req ipc.Request) {
	fragment, err := niriConfigFragment(req, "")
	if err != nil {
		conn.RespondError(req.ID, niriConfigError(err))
		return
	}
	content, err := params.String(req.Params, "content")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	if len(content) > maxNiriFragmentSize {
		conn.RespondError(req.ID, errNiriTooLarge.Error())
		return
	}
	baseHash, err := params.String(req.Params, "baseHash")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	extra, err := niriConfigExtra(req)
	if err != nil {
		conn.RespondError(req.ID, niriConfigError(err))
		return
	}
	v, err := niriConfigStore().Apply(fragment, content, baseHash, extra...)
	if err != nil {
		conn.RespondError(req.ID, niriConfigError(err))
		return
	}
	conn.Respond(req.ID, niriConfigApplied{Version: v.N, Hash: niriconf.PageHash(content, extra)})
}

func handleNiriConfigHistory(conn *ipc.ConnWriter, req ipc.Request) {
	fragment, err := niriConfigFragment(req, niriCustomFragment)
	if err != nil {
		conn.RespondError(req.ID, niriConfigError(err))
		return
	}
	versions, err := niriConfigStore().History(fragment)
	if err != nil {
		conn.RespondError(req.ID, niriConfigError(err))
		return
	}
	result := make([]niriConfigVersion, 0, len(versions))
	for _, v := range versions {
		result = append(result, niriConfigVersion{N: v.N, Time: v.Time, Hash: v.Hash, Failed: v.Failed})
	}
	conn.Respond(req.ID, result)
}

func handleNiriConfigRestore(conn *ipc.ConnWriter, req ipc.Request) {
	fragment, err := niriConfigFragment(req, "")
	if err != nil {
		conn.RespondError(req.ID, niriConfigError(err))
		return
	}
	n, err := params.Int(req.Params, "version")
	if err != nil {
		conn.RespondError(req.ID, err.Error())
		return
	}
	// The page hash also covers the custom fragment, which a restore leaves as is.
	v, hash, err := niriConfigStore().Restore(fragment, n, niriCustomFragment)
	if errors.Is(err, fs.ErrNotExist) {
		conn.RespondError(req.ID, "no such version")
		return
	}
	if err != nil {
		conn.RespondError(req.ID, niriConfigError(err))
		return
	}
	conn.Respond(req.ID, niriConfigApplied{Version: v.N, Hash: hash})
}

// handleNiriConfigDoctor applies the one safe fix (or its undo) first when asked, then checks again.
func handleNiriConfigDoctor(conn *ipc.ConnWriter, req ipc.Request) {
	store := niriConfigStore()
	switch params.StringOpt(req.Params, "fix", "") {
	case "":
	case niriconf.FixAddInclude:
		fragment, err := params.String(req.Params, "fragment")
		if err != nil {
			conn.RespondError(req.ID, err.Error())
			return
		}
		if err := store.AddInclude(fragment); err != nil {
			conn.RespondError(req.ID, niriConfigError(err))
			return
		}
	case niriconf.FixUndoInclude:
		if err := store.UndoInclude(); err != nil {
			conn.RespondError(req.ID, niriConfigError(err))
			return
		}
	default:
		conn.RespondError(req.ID, "bad fix")
		return
	}
	conn.Respond(req.ID, niriconf.Doctor(store.ConfigDir, params.StringSlice(req.Params, "appIds")))
}
