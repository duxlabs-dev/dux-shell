package wallpaper

import "time"

type ScheduleConfig struct {
	Enabled     bool   `json:"enabled"`
	Mode        string `json:"mode"`
	IntervalSec int    `json:"intervalSec"`
	Time        string `json:"time"`
	OnLogin     bool   `json:"onLogin"`
}

type Config struct {
	PerMonitor bool                      `json:"perMonitor"`
	Global     ScheduleConfig            `json:"global"`
	Monitors   map[string]ScheduleConfig `json:"monitors"`
}

type State struct {
	Config       Config    `json:"config"`
	NextRotation time.Time `json:"nextRotation"`
	CycleSeq     uint64    `json:"cycleSeq"`
	Target       string    `json:"target"`
}
