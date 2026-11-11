package config

import _ "embed"

//go:embed embedded/niri.kdl
var NiriConfig string

//go:embed embedded/niri-colors.kdl
var NiriColorsConfig string

//go:embed embedded/niri-layout.kdl
var NiriLayoutConfig string

//go:embed embedded/niri-alttab.kdl
var NiriAlttabConfig string

//go:embed embedded/niri-binds.kdl
var NiriBindsConfig string

//go:embed embedded/niri-input.kdl
var NiriInputConfig string
