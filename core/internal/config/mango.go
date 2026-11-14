package config

import _ "embed"

//go:embed embedded/mango.conf
var MangoConfig string

//go:embed embedded/mango-colors.conf
var MangoColorsConfig string

//go:embed embedded/mango-layout.conf
var MangoLayoutConfig string

//go:embed embedded/mango-binds.conf
var MangoBindsConfig string

//go:embed embedded/mango.toml
var MangoTOMLConfig string

//go:embed embedded/mango-animations.conf
var MangoAnimationsConfig string
