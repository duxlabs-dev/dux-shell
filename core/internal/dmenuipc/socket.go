package dmenuipc

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"os"
	"path/filepath"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/internal/utils"
)

type Range struct {
	Start int `json:"start"`
	End   int `json:"end"`
}

type Keybind struct {
	N   int    `json:"n"`
	Key string `json:"key"`
}

type Header struct {
	Prompt         string    `json:"prompt"`
	Placeholder    string    `json:"placeholder,omitempty"`
	Lines          int       `json:"lines,omitempty"`
	PromptOnly     bool      `json:"promptOnly,omitempty"`
	Select         string    `json:"select,omitempty"`
	Mesg           string    `json:"mesg,omitempty"`
	Password       bool      `json:"password,omitempty"`
	MarkupRows     bool      `json:"markupRows,omitempty"`
	OnlyMatch      bool      `json:"onlyMatch,omitempty"`
	NoCustom       bool      `json:"noCustom,omitempty"`
	MultiSelect    bool      `json:"multiSelect,omitempty"`
	Active         []Range   `json:"active,omitempty"`
	Urgent         []Range   `json:"urgent,omitempty"`
	Keybinds       []Keybind `json:"keybinds,omitempty"`
	View           string    `json:"view,omitempty"`
	Size           string    `json:"size,omitempty"`
	Icon           string    `json:"icon,omitempty"`
	DisableHistory bool      `json:"disableHistory,omitempty"`
}

type ItemMeta struct {
	Icon          string `json:"icon,omitempty"`
	Display       string `json:"display,omitempty"`
	Meta          string `json:"meta,omitempty"`
	Info          string `json:"info,omitempty"`
	NonSelectable bool   `json:"nonSelectable,omitempty"`
	Urgent        bool   `json:"urgent,omitempty"`
	Active        bool   `json:"active,omitempty"`
	Permanent     bool   `json:"permanent,omitempty"`
	Header        bool   `json:"header,omitempty"`
}

type SelectedRow struct {
	Index int    `json:"index"`
	Text  string `json:"text"`
	Info  string `json:"info,omitempty"`
}

type envelope struct {
	Type           string        `json:"type"`
	Prompt         string        `json:"prompt,omitempty"`
	Placeholder    string        `json:"placeholder,omitempty"`
	Lines          int           `json:"lines,omitempty"`
	PromptOnly     bool          `json:"promptOnly,omitempty"`
	Select         string        `json:"select,omitempty"`
	Mesg           string        `json:"mesg,omitempty"`
	Password       bool          `json:"password,omitempty"`
	MarkupRows     bool          `json:"markupRows,omitempty"`
	OnlyMatch      bool          `json:"onlyMatch,omitempty"`
	NoCustom       bool          `json:"noCustom,omitempty"`
	MultiSelect    bool          `json:"multiSelect,omitempty"`
	Active         []Range       `json:"active,omitempty"`
	Urgent         []Range       `json:"urgent,omitempty"`
	Keybinds       []Keybind     `json:"keybinds,omitempty"`
	View           string        `json:"view,omitempty"`
	Size           string        `json:"size,omitempty"`
	Icon           string        `json:"icon,omitempty"`
	DisableHistory bool          `json:"disableHistory,omitempty"`
	Text           string        `json:"text,omitempty"`
	Row            *ItemMeta     `json:"row,omitempty"`
	Kind           string        `json:"kind,omitempty"`
	Index          int           `json:"index"`
	Info           string        `json:"info,omitempty"`
	FilterText     string        `json:"filterText,omitempty"`
	Items          []SelectedRow `json:"items,omitempty"`
	KeybindN       int           `json:"keybindN,omitempty"`
}

type Session struct {
	listener *net.UnixListener
	path     string
}

func Listen() (*Session, error) {
	dir := filepath.Join(utils.RuntimeDir(), "dms")
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return nil, fmt.Errorf("create dmenu socket dir: %w", err)
	}

	token := make([]byte, 8)
	if _, err := rand.Read(token); err != nil {
		return nil, fmt.Errorf("generate dmenu socket token: %w", err)
	}
	path := filepath.Join(dir, fmt.Sprintf("dmenu-%d-%s.sock", os.Getpid(), hex.EncodeToString(token)))

	addr, err := net.ResolveUnixAddr("unix", path)
	if err != nil {
		return nil, fmt.Errorf("resolve dmenu socket address: %w", err)
	}
	listener, err := net.ListenUnix("unix", addr)
	if err != nil {
		return nil, fmt.Errorf("listen on dmenu socket: %w", err)
	}
	if err := os.Chmod(path, 0o600); err != nil {
		listener.Close()
		os.Remove(path)
		return nil, fmt.Errorf("chmod dmenu socket: %w", err)
	}

	return &Session{listener: listener, path: path}, nil
}

func (s *Session) Path() string { return s.path }

func (s *Session) Close() {
	s.listener.Close()
	os.Remove(s.path)
}

func (s *Session) Accept(timeout time.Duration) (*Conn, error) {
	if err := s.listener.SetDeadline(time.Now().Add(timeout)); err != nil {
		return nil, err
	}
	conn, err := s.listener.AcceptUnix()
	if err != nil {
		return nil, err
	}
	if err := conn.SetDeadline(time.Time{}); err != nil {
		conn.Close()
		return nil, err
	}
	return &Conn{conn: conn, dec: json.NewDecoder(conn)}, nil
}

type Conn struct {
	conn *net.UnixConn
	dec  *json.Decoder
}

func (c *Conn) Close() error { return c.conn.Close() }

func (c *Conn) SendHeader(h Header) error {
	return c.send(envelope{
		Type:           "header",
		Prompt:         h.Prompt,
		Placeholder:    h.Placeholder,
		Lines:          h.Lines,
		PromptOnly:     h.PromptOnly,
		Select:         h.Select,
		Mesg:           h.Mesg,
		Password:       h.Password,
		MarkupRows:     h.MarkupRows,
		OnlyMatch:      h.OnlyMatch,
		NoCustom:       h.NoCustom,
		MultiSelect:    h.MultiSelect,
		Active:         h.Active,
		Urgent:         h.Urgent,
		Keybinds:       h.Keybinds,
		View:           h.View,
		Size:           h.Size,
		Icon:           h.Icon,
		DisableHistory: h.DisableHistory,
	})
}

func (c *Conn) SendItem(text string, meta *ItemMeta) error {
	return c.send(envelope{Type: "item", Text: text, Row: meta})
}

func (c *Conn) SendEnd() error {
	return c.send(envelope{Type: "end"})
}

func (c *Conn) send(e envelope) error {
	return json.NewEncoder(c.conn).Encode(e)
}

type Selection struct {
	Kind       string // "row" | "freetext" | "multi"
	Index      int    // valid when Kind == "row"
	Text       string // valid when Kind == "row" or "freetext"
	Info       string // valid when Kind == "row" and the row carried info
	FilterText string // the search box's contents at accept time, always set
	Items      []SelectedRow
	KeybindN   int // nonzero when accepted via custom keybinding N
}

func (c *Conn) ReadSelection() (sel Selection, ok bool, err error) {
	var e envelope
	if decErr := c.dec.Decode(&e); decErr != nil {
		if decErr == io.EOF {
			return Selection{}, false, nil
		}
		return Selection{}, false, decErr
	}
	if e.Type != "select" {
		return Selection{}, false, fmt.Errorf("unexpected dmenu response type %q", e.Type)
	}
	return Selection{
		Kind:       e.Kind,
		Index:      e.Index,
		Text:       e.Text,
		Info:       e.Info,
		FilterText: e.FilterText,
		Items:      e.Items,
		KeybindN:   e.KeybindN,
	}, true, nil
}
