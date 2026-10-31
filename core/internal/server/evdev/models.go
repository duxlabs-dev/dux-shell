package evdev

type State struct {
	Available bool `json:"available"`
	CapsLock  bool `json:"capsLock"`
	NumLock   bool `json:"numLock"`
}
