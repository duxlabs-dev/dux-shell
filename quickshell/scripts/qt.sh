#!/usr/bin/env bash

CONFIG_DIR="$1"

if [ -z "$CONFIG_DIR" ]; then
    echo "Usage: $0 <config_dir>" >&2
    exit 1
fi

apply_qt_colors() {
    local config_dir="$1"
    local color_scheme_path
    color_scheme_path="$(dirname "$config_dir")/.local/share/color-schemes/DankMatugen.colors"

    if [ ! -f "$color_scheme_path" ]; then
        echo "Error: Qt color scheme not found at $color_scheme_path" >&2
        echo "Run matugen first to generate theme files" >&2
        exit 1
    fi

    update_qt_config() {
        local config_file="$1"

        if [ -f "$config_file" ]; then
            sed -i 's/^\[Appearance\]\\ncustom_palette=.*/[Appearance]/' "$config_file"

            if grep -q '^\[Appearance\]' "$config_file"; then
                if grep -q '^custom_palette=' "$config_file"; then
                    sed -i 's/^custom_palette=.*/custom_palette=true/' "$config_file"
                else
                    sed -i '/^\[Appearance\]/a custom_palette=true' "$config_file"
                fi

                if grep -q '^color_scheme_path=' "$config_file"; then
                    sed -i "s|^color_scheme_path=.*|color_scheme_path=$color_scheme_path|" "$config_file"
                else
                    sed -i "/^\\[Appearance\\]/a color_scheme_path=$color_scheme_path" "$config_file"
                fi
            else
                {
                    echo ""
                    echo "[Appearance]"
                    echo "custom_palette=true"
                    echo "color_scheme_path=$color_scheme_path"
                } >>"$config_file"
            fi
        else
            printf '[Appearance]\ncustom_palette=true\ncolor_scheme_path=%s\n' "$color_scheme_path" >"$config_file"
        fi
    }

    qt5_applied=false
    qt6_applied=false

    if command -v qt5ct >/dev/null 2>&1; then
        mkdir -p "$config_dir/qt5ct"
        update_qt_config "$config_dir/qt5ct/qt5ct.conf"
        echo "Applied Qt5ct configuration"
        qt5_applied=true
    fi

    if command -v qt6ct >/dev/null 2>&1; then
        mkdir -p "$config_dir/qt6ct"
        update_qt_config "$config_dir/qt6ct/qt6ct.conf"
        echo "Applied Qt6ct configuration"
        qt6_applied=true
    fi

    kde_applied=false
    case ":${XDG_CURRENT_DESKTOP:-}:" in
    *:KDE:*) ;;
    *)
        for kwrite in kwriteconfig6 kwriteconfig5; do
            command -v "$kwrite" >/dev/null 2>&1 || continue
            "$kwrite" --file "$config_dir/kdeglobals" --group UiSettings --key ColorScheme DankMatugen && kde_applied=true
            break
        done
        ;;
    esac

    if [ "$qt5_applied" = false ] && [ "$qt6_applied" = false ] && [ "$kde_applied" = false ]; then
        echo "Warning: Neither qt5ct nor qt6ct found" >&2
        echo "Install qt5ct or qt6ct for Qt application theming" >&2
        exit 1
    fi
}

apply_qt_colors "$CONFIG_DIR"

echo "Qt colors applied successfully"
