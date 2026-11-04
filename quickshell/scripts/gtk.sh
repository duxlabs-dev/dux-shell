#!/usr/bin/env bash

CONFIG_DIR="$1"
# apply: setup overrides and config dirs
# patch: refresh overrides in adw-gtk3; exits 2 when skipped, 3 when already current
# remove: remove all overrides
MODE="${2:-apply}"
IS_LIGHT="${3:-light}"

if [ -z "$CONFIG_DIR" ]; then
	echo "Usage: $0 <config_dir> [apply|patch|remove] [is_light]" >&2
	exit 1
fi

USER_DATA_THEMES="${XDG_DATA_HOME:-$HOME/.local/share}/themes"

# System theme roots come from XDG_DATA_DIRS so NixOS profiles and
# /run/current-system are found, not just /usr/share.
system_theme_roots() {
	local IFS=':'
	local dirs="${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
	local d
	for d in $dirs; do
		[ -n "$d" ] && echo "${d%/}/themes"
	done
}

# A theme is ours to patch only when it lives in a user dir and is writable;
# prefix tests like ^/usr misclassify nix store paths as user copies.
is_user_theme_dir() {
	local dir="$1"
	[ -n "$dir" ] && [ -w "$dir" ] || return 1
	case "$dir" in
		"$USER_DATA_THEMES"/*|"$HOME/.themes"/*) return 0 ;;
	esac
	return 1
}

# Patch only DMS's own copy or a theme the user ran 'apply' on (which backs it
# up), never a user's hand-made copy that merely sits next to a dank import.
is_patchable_theme_dir() {
	local dir="$1"
	is_user_theme_dir "$dir" || return 1
	[ -f "$dir/../.dms-copy" ] || [ -f "$dir/gtk.css.dms-backup" ]
}

get_adw_gtk3_dir() {
	local variant="$1"
	local name=""
	[ "$variant" == "dark" ] && name="-$variant"

	local candidates=(
		"$USER_DATA_THEMES/adw-gtk3${name}/gtk-3.0"
		"$HOME/.themes/adw-gtk3${name}/gtk-3.0"
	)
	local root
	while IFS= read -r root; do
		candidates+=("$root/adw-gtk3${name}/gtk-3.0")
	done < <(system_theme_roots)

	local target=""
	for c in "${candidates[@]}"; do
		if [ -d "$c" ]; then
			target="$c"
			break
		fi
	done
	echo "$target"
}

get_system_adw_gtk3_root() {
	local variant="$1"
	local name=""
	[ "$variant" == "dark" ] && name="-$variant"
	local root
	while IFS= read -r root; do
		if [ -d "$root/adw-gtk3${name}/gtk-3.0" ]; then
			echo "$root/adw-gtk3${name}"
			return 0
		fi
	done < <(system_theme_roots)
	return 1
}

theme_src_checksum() {
	command -v sha256sum >/dev/null 2>&1 || return 1
	sha256sum "$1/gtk-3.0/gtk.css" 2>/dev/null | cut -d' ' -f1
}

# DMS patches the theme css in place, which needs a user-writable copy;
# package managers install to read-only system dirs (nix store included).
ensure_user_adw_gtk3() {
	local variant name src dest marker src_sum
	for variant in light dark; do
		name=""
		[ "$variant" == "dark" ] && name="-$variant"
		dest="$USER_DATA_THEMES/adw-gtk3${name}"
		marker="$dest/.dms-copy"

		if [ -d "$dest/gtk-3.0" ]; then
			[ -f "$marker" ] || continue
			src="$(get_system_adw_gtk3_root "$variant")" || continue
			src_sum="$(theme_src_checksum "$src")" || continue
			if [ "$src_sum" != "$(sed -n 's/^sha256=//p' "$marker")" ]; then
				echo "System adw-gtk3${name} changed, refreshing DMS copy"
				rm -rf "$dest"
			else
				continue
			fi
		fi
		[ -d "$dest/gtk-3.0" ] && continue

		src="$(get_system_adw_gtk3_root "$variant")" || continue
		mkdir -p "$USER_DATA_THEMES"
		# -L dereferences nix store symlink forests; store files arrive read-only.
		if ! cp -RL "$src" "$dest"; then
			echo "Warning: failed to copy adw-gtk3${name} from '$src'" >&2
			rm -rf "$dest"
			continue
		fi
		chmod -R u+w "$dest"
		{
			echo "src=$src"
			echo "sha256=$(theme_src_checksum "$src")"
		} >"$marker"
		echo "Copied adw-gtk3${name} to '$dest' for dynamic theming"
	done
}

DANK_IMPORT='@import url("dank-colors.css");'
DANK_IMPORT_RE='^@import url.*dank-colors\.css.*);$'

# gtk.css is DMS-managed if it is our symlink or carries our import line.
# User-managed symlinks (e.g. home-manager) are never touched.
dms_managed_css() {
	local gtk_css="$1"
	if [ -L "$gtk_css" ]; then
		case "$(readlink "$gtk_css")" in
			*dank-colors.css*) return 0 ;;
			*) return 1 ;;
		esac
	fi
	[ -f "$gtk_css" ] && grep -q "$DANK_IMPORT_RE" "$gtk_css"
}

# Opted in when either gtk.css uses our colors, including through a user-managed
# symlink. Must match isDMSGTKActive in core/internal/matugen.
dank_colors_active() {
	local config_dir="$1" gtk_css
	for gtk_css in "$config_dir/gtk-4.0/gtk.css" "$config_dir/gtk-3.0/gtk.css"; do
		dms_managed_css "$gtk_css" && return 0
		grep -qs 'dank-colors\.css' "$gtk_css" && return 0
	done
	return 1
}

inject_dank_import() {
	local gtk_css="$1"

	if [ -L "$gtk_css" ]; then
		if grep -qs "$DANK_IMPORT_RE" "$gtk_css"; then
			echo "User-managed '$gtk_css' already imports dank-colors.css"
			return 0
		fi
		if ! dms_managed_css "$gtk_css"; then
			echo "Warning: '$gtk_css' is a user-managed symlink; leaving it untouched" >&2
			echo "Import dank-colors.css from your own stylesheet to use DMS colors" >&2
			return 1
		fi
		rm "$gtk_css"
	fi

	if [ -f "$gtk_css" ] && grep -q "$DANK_IMPORT_RE" "$gtk_css"; then
		echo "Dank import already present in '$gtk_css'"
		return 0
	fi

	if [ -f "$gtk_css" ] && [ -s "$gtk_css" ]; then
		sed -i "1i\\$DANK_IMPORT" "$gtk_css"
	else
		echo "$DANK_IMPORT" >"$gtk_css"
	fi
	echo "Added dank-colors import to '$gtk_css'"
}

remove_dank_import() {
	local gtk_css="$1"

	if [ -L "$gtk_css" ]; then
		if dms_managed_css "$gtk_css"; then
			rm "$gtk_css"
			echo "Removed DMS-managed symlink '$gtk_css'"
		fi
		return 0
	fi

	if [ -f "$gtk_css" ] && grep -q "$DANK_IMPORT_RE" "$gtk_css"; then
		sed -i "/$DANK_IMPORT_RE/d" "$gtk_css"
		echo "Removed dank-colors import from '$gtk_css'"
	fi
}

remove_gtk3_patch() {
	local theme_dir="$1"
	local css_variant="$2"
	[ "$css_variant" != "-dark" ] && css_variant=""
	sed -i '/\/\* BEGIN DMS OVERRIDE \*\//,/\/\* END DMS OVERRIDE \*\//d' "${theme_dir}/gtk${css_variant}.css"
	return $?
}

remove_gtk3_colors() {
	local config_dir="$1"

	local gtk3_dir="$config_dir/gtk-3.0"

	remove_dank_import "$gtk3_dir/gtk.css"
	if [ ! -f "${gtk3_dir}/dank-colors.css" ]; then
		echo "Nothing to remove at '${gtk3_dir}'"
	else
		if rm "${gtk3_dir}/dank-colors.css"; then
			echo "Removed GTK3 override from '${gtk3_dir}'"
		else
			echo "Failed to remove GTK3 override from '${gtk3_dir}'"
		fi
	fi

	for variant in light dark; do
		local adw_gtk3_dir && adw_gtk3_dir=$(get_adw_gtk3_dir "$variant")

		if ! is_user_theme_dir "$adw_gtk3_dir"; then
			echo "No user version of adw-gtk3 ${variant} found, nothing to unpatch"
			continue
		fi

		for css_variant in light dark; do
			if remove_gtk3_patch "$adw_gtk3_dir" "$css_variant"; then
				echo "Removed GTK colors patch from '${adw_gtk3_dir}' in '$css_variant' stylesheet"
			else
				echo "Failed to remove GTK colors patch from '${adw_gtk3_dir}' in '$css_variant' stylesheet" >&2
			fi
		done
	done
}

do_patch() {
	local theme_dir="$1"
	local variant="$2"
	if ! is_patchable_theme_dir "$theme_dir"; then
		echo "Skipping '$variant' patch: no DMS-managed copy of adw-gtk3 for this variant"
		return 0
	fi
	local css_variant=""
	[ "$variant" = "dark" ] && css_variant="-${variant}"
	local theme_css="${theme_dir}/gtk${css_variant}.css"
	if [ "$(sed -n '/\/\* BEGIN DMS OVERRIDE \*\//,/\/\* END DMS OVERRIDE \*\//p' "$theme_css" 2>/dev/null)" = "$(cat "${gtk3_dir}/dank-colors.css")" ]; then
		return 0
	fi
	PATCHED=1
	if {
		remove_gtk3_patch "$theme_dir" "$css_variant"
		cat "${gtk3_dir}/dank-colors.css" >>"${theme_dir}/gtk${css_variant}.css"
	}; then
		echo "Successfully patched '$theme_dir/gtk${css_variant}.css' with GTK '$variant' colors"
	else
		echo "Error: failed to patch '$theme_dir/gtk${css_variant}.css' with GTK '$variant' colors" >&2
		exit 1
	fi
}

patch_gtk3_colors() {
	local config_dir="$1"
	local is_light="$2"

	local gtk3_dir="$config_dir/gtk-3.0"
	local variant="light"
	[ "$is_light" = "false" ] && variant="dark"
	local adw_gtk3_dir && adw_gtk3_dir=$(get_adw_gtk3_dir "$variant")

	if ! is_patchable_theme_dir "$adw_gtk3_dir"; then
		echo "No DMS-managed adw-gtk3 ${variant} was found, skipping patch"
		exit 2
	fi

	if [ ! -f "${gtk3_dir}/dank-colors.css" ]; then
		echo "Error: GTK3 dank-colors.css not found at '${gtk3_dir}'" >&2
		echo "Run matugen first to generate theme files" >&2
		exit 1
	fi

	# adw-gtk3-dark's gtk.css is dark too, so dark mode patches both stylesheets
	if [ "$variant" = "dark" ]; then
		do_patch "$adw_gtk3_dir" "dark"
		do_patch "$adw_gtk3_dir" "light"
		do_patch "$(get_adw_gtk3_dir "light")" "dark"
	else
		do_patch "$adw_gtk3_dir" "light"
	fi

	if [ -z "$PATCHED" ]; then
		echo "GTK3 colors already current"
		exit 3
	fi
}

apply_gtk3_colors() {
	local config_dir="$1"

	local gtk3_dir="$config_dir/gtk-3.0"
	local gtk3_override="$gtk3_dir/gtk.css"
	ensure_user_adw_gtk3

	local adw_gtk3 && adw_gtk3="$(get_adw_gtk3_dir)"
	if ! is_user_theme_dir "$adw_gtk3"; then
		echo "Warning: No user version of adw-gtk3 found" >&2
		echo "Falling back on global css override" >&2
		local dank_colors="$gtk3_dir/dank-colors.css"

		if [ ! -f "$dank_colors" ]; then
			echo "Error: dank-colors.css not found at $dank_colors" >&2
			echo "Run matugen first to generate theme files" >&2
			exit 1
		fi

		inject_dank_import "$gtk3_override" || exit 1

		return
	fi

	# adw-gtk3 carries the colors; ensure there's no DMS global override
	remove_dank_import "$gtk3_override"

	for variant in light dark; do
		local adw_gtk3_dir && adw_gtk3_dir="$(get_adw_gtk3_dir "$variant")"
		for css in gtk.css gtk-dark.css; do
			if [ -f "$adw_gtk3_dir/$css" ] && [ ! -f "$adw_gtk3_dir/$css.dms-backup" ]; then
				cp "$adw_gtk3_dir/$css" "$adw_gtk3_dir/$css.dms-backup"
			fi
		done
	done
}

remove_gtk4_colors() {
	local config_dir="$1"

	local gtk4_dir="$config_dir/gtk-4.0"
	local dank_colors="$gtk4_dir/dank-colors.css"
	local gtk_css="$gtk4_dir/gtk.css"

	remove_dank_import "$gtk_css"

	if [ ! -f "$dank_colors" ]; then
		echo "Nothing to remove in '$gtk4_dir'"
		return
	fi

	rm "$dank_colors"
	echo "Removed 'dank-colors.css' from '$gtk4_dir'"
}

apply_gtk4_colors() {
	local config_dir="$1"

	local gtk4_dir="$config_dir/gtk-4.0"
	local dank_colors="$gtk4_dir/dank-colors.css"
	local gtk_css="$gtk4_dir/gtk.css"

	if [ ! -f "$dank_colors" ]; then
		echo "Error: GTK4 dank-colors.css not found at $dank_colors" >&2
		echo "Run matugen first to generate theme files" >&2
		exit 1
	fi

	inject_dank_import "$gtk_css" || exit 1
}

case "$MODE" in
	patch)
		if ! dank_colors_active "$CONFIG_DIR"; then
			echo "DMS GTK theming is not applied, skipping patch"
			exit 2
		fi
		patch_gtk3_colors "$CONFIG_DIR" "$IS_LIGHT"
		echo "GTK3 colors patched successfully"
		;;
	remove)
		remove_gtk3_colors "$CONFIG_DIR"
		remove_gtk4_colors "$CONFIG_DIR"
		;;
	apply)
		mkdir -p "$CONFIG_DIR/gtk-3.0" "$CONFIG_DIR/gtk-4.0"

		apply_gtk3_colors "$CONFIG_DIR"
		apply_gtk4_colors "$CONFIG_DIR"

		echo "GTK colors applied successfully"
		;;
	*)
		echo "Usage: $0 <config_dir> [apply|patch|remove] [is_light]" >&2
		exit 1
		;;
esac
