package config

import _ "embed"

//go:embed embedded/hyprland.lua
var HyprlandLuaConfig string

//go:embed embedded/hypr-colors.lua
var DMSColorsLuaConfig string

//go:embed embedded/hypr-layout.lua
var DMSLayoutLuaConfig string

//go:embed embedded/hypr-binds.lua
var DMSBindsLuaConfig string

//go:embed embedded/hypr-outputs.lua
var DMSOutputsLuaConfig string

//go:embed embedded/hypr-cursor.lua
var DMSCursorLuaConfig string

//go:embed embedded/hypr-input.lua
var DMSInputLuaConfig string

//go:embed embedded/hypr-windowrules.lua
var DMSWindowRulesLuaConfig string

//go:embed embedded/hypr-binds-user.lua
var DMSBindsUserLuaConfig string
