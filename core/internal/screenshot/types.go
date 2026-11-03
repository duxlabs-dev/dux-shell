package screenshot

import (
	"fmt"
	"strings"
)

type Mode int

const (
	ModeRegion Mode = iota
	ModeWindow
	ModeFullScreen
	ModeAllScreens
	ModeOutput
	ModeLastRegion
	ModeScroll
)

type Format int

const (
	FormatPNG Format = iota
	FormatJPEG
	FormatPPM
)

type CursorMode int

const (
	CursorOff CursorMode = iota
	CursorOn
)

type Region struct {
	X      int32  `json:"x"`
	Y      int32  `json:"y"`
	Width  int32  `json:"width"`
	Height int32  `json:"height"`
	Output string `json:"output,omitempty"`
}

func (r Region) IsEmpty() bool {
	return r.Width <= 0 || r.Height <= 0
}

func (r Region) GeometryString() string {
	return fmt.Sprintf("%d,%d %dx%d", r.X, r.Y, r.Width, r.Height)
}

type Output struct {
	Name            string
	X, Y            int32
	Width           int32
	Height          int32
	Scale           int32
	FractionalScale float64
	Transform       int32
}

type SnapTarget struct {
	Name   string  `json:"name"`
	Type   string  `json:"type"`
	X      float64 `json:"x"`
	Y      float64 `json:"y"`
	Width  float64 `json:"width"`
	Height float64 `json:"height"`
}

func (s SnapTarget) DisplayName() string {
	name := strings.TrimPrefix(s.Name, "dms:")
	for _, suffix := range []string{"-popout", "-modal", "-surface"} {
		name = strings.TrimSuffix(name, suffix)
	}
	name = strings.ReplaceAll(name, "-", " ")
	if name == "" {
		if s.Type != "" {
			return s.Type
		}
		return "surface"
	}
	return name
}

type Config struct {
	Seat          string
	Mode          Mode
	OutputName    string
	Cursor        CursorMode
	NoConfirm     bool
	Reset         bool
	Format        Format
	Quality       int
	OutputDir     string
	Filename      string
	Clipboard     bool
	SaveFile      bool
	Notify        bool
	Stdout        bool
	Geometry      bool
	AllowMultiple bool
	IntervalMs    int
	HUD           string
	SnapTargets   []SnapTarget
	// SelectorHook runs as the interactive selector starts (true) and ends (false).
	SelectorHook func(begin bool)
}

func DefaultConfig() Config {
	return Config{
		Mode:      ModeRegion,
		Cursor:    CursorOff,
		NoConfirm: false,
		Reset:     false,
		Format:    FormatPNG,
		Quality:   90,
		OutputDir: "",
		Filename:  "",
		Clipboard: true,
		SaveFile:  true,
		Notify:    true,
		HUD:       "auto",
	}
}
