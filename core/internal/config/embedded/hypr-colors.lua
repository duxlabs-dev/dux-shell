-- ! Auto-generated file. Do not edit directly.
-- Regenerate via DMS theme tools or remove require("dms.colors") from hyprland.lua to override.

hl.config({
	general = {
		col = {
			active_border = "rgb(d0bcff)",
			inactive_border = "rgb(948f99)",
		},
	},
	group = {
		col = {
			border_active = "rgb(d0bcff)",
			border_inactive = "rgb(948f99)",
			border_locked_active = "rgb(f2b8b5)",
			border_locked_inactive = "rgb(948f99)",
		},
		groupbar = {
			col = {
				active = "rgb(d0bcff)",
				inactive = "rgb(948f99)",
				locked_active = "rgb(f2b8b5)",
				locked_inactive = "rgb(948f99)",
			},
		},
	},
})

-- Effect colors exist only on newer Hyprland; skip them elsewhere instead of raising config errors
local function themed(key, value)
	local ok, current = pcall(hl.get_config, key)
	if ok and current ~= nil then
		hl.config({ [key] = value })
	end
end

themed("decoration.glow.color", "rgba(d0bcffee)")
themed("decoration.glow.color_inactive", "rgba(948f99ee)")
themed("decoration.blur.acrylic.tint", "rgba(d0bcff14)")
themed("decoration.blur.aurora.color1", "rgba(d0bcff29)")
themed("decoration.blur.aurora.color2", "rgba(efb8c87a)")
themed("decoration.blur.fluid_jar.color", "rgba(d0bcffcc)")
