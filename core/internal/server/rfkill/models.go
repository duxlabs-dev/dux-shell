package rfkill

type State struct {
	Available    bool `json:"available"`
	AirplaneMode bool `json:"airplaneMode"`
}
