import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

Item {
    id: root

    property var parentModal: null
    property var templateDetection: []
    readonly property var neovimDarkBaseThemes: ["aquarium", "ashes", "aylin", "ayu_dark", "bearded-arc", "carbonfox", "catppuccin", "chadracula", "chadracula-evondev", "chadtain", "chocolate", "darcula-dark", "dark_horizon", "decay", "default-dark", "doomchad", "eldritch", "embark", "everblush", "everforest", "falcon", "flexoki", "flouromachine", "gatekeeper", "github_dark", "gruvbox", "gruvchad", "hiberbee", "horizon", "jabuti", "jellybeans", "kanagawa", "kanagawa-dragon", "material-darker", "material-deep-ocean", "melange", "midnight_breeze", "mito-laser", "monekai", "monochrome", "mountain", "neofusion", "nightfox", "nightlamp", "nightowl", "nord", "obsidian-ember", "oceanic-next", "onedark", "onenord", "oxocarbon", "palenight", "pastelDark", "pastelbeans", "penumbra_dark", "poimandres", "radium", "rosepine", "rxyhn", "scaryforest", "seoul256_dark", "solarized_dark", "solarized_osaka", "starlight", "sweetpastel", "tokyodark", "tokyonight", "tomorrow_night", "tundra", "vesper", "vscode_dark", "wombat", "yoru", "zenburn"]
    readonly property var neovimLightBaseThemes: ["ayu_light", "blossom_light", "catppuccin-latte", "default-light", "everforest_light", "flex-light", "flexoki-light", "github_light", "gruvbox_light", "material-lighter", "nano-light", "oceanic-light", "one_light", "onenord_light", "penumbra_light", "rosepine-dawn", "seoul256_light", "solarized_light", "sunrise_breeze", "vscode_light"]

    function setNeovimSetting(mode, key, value) {
        const settings = JSON.parse(JSON.stringify(SettingsData.matugenTemplateNeovimSettings));
        settings[mode][key] = value;
        SettingsData.set("matugenTemplateNeovimSettings", settings);
    }

    function isTemplateDetected(templateId) {
        if (!templateDetection || templateDetection.length === 0)
            return true;
        const item = templateDetection.find(i => i.id === templateId);
        return !item || item.detected !== false;
    }

    function getTemplateDescription(templateId, baseDescription) {
        if (isTemplateDetected(templateId))
            return baseDescription;
        if (baseDescription)
            return baseDescription + " · " + I18n.tr("Not detected");
        return I18n.tr("Not detected");
    }

    function getTemplateDescriptionColor(templateId) {
        if (isTemplateDetected(templateId))
            return Theme.surfaceVariantText;
        return Theme.warning;
    }

    Component.onCompleted: {
        Proc.runCommand("template-check", [Proc.dmsBin, "matugen", "check"], (output, exitCode) => {
            if (exitCode !== 0)
                return;
            try {
                root.templateDetection = JSON.parse(output.trim());
            } catch (e) {}
        });
    }

    SettingsPage {
        id: mainColumn

        SettingsNoteRow {
            paintBackground: false
            noteIconName: "info"
            text: I18n.tr("The below settings will modify your GTK and Qt settings. If you wish to preserve your current configurations, please back them up (%1 and %2).", "theme apps backup note, %1 and %2 are config paths").arg("qt5ct.conf|qt6ct.conf|qtengine/config.json").arg("~/.config/gtk-3.0|gtk-4.0")
        }

        SettingsCard {
            tab: "theme"
            tags: ["system", "app", "theming", "gtk", "qt"]
            title: I18n.tr("GTK & Qt")
            settingKey: "systemAppTheming"
            iconName: "brush"
            visible: Theme.matugenAvailable

            SettingsRow {
                body: Row {
                    width: parent.width
                    spacing: Theme.spacingM

                    DButton {
                        width: (parent.width - Theme.spacingM) / 2
                        iconName: "settings"
                        text: I18n.tr("Apply GTK colors")
                        backgroundColor: Theme.secondaryContainer
                        textColor: Theme.onSecondaryContainer
                        onClicked: Theme.applyGtkColors()
                    }

                    DButton {
                        width: (parent.width - Theme.spacingM) / 2
                        iconName: "settings"
                        text: I18n.tr("Apply Qt colors")
                        backgroundColor: Theme.secondaryContainer
                        textColor: Theme.onSecondaryContainer
                        onClicked: Theme.applyQtColors()
                    }
                }
            }

            SettingsRow {
                body: StyledText {
                    text: I18n.tr('Generate baseline GTK3/4, QT5/QT6, or qtengine configurations to follow DMS colors (only qt6ct requires qt6ct-kde). Only needed once.<br /><br />It is recommended to configure %1 prior to applying GTK themes.', 'app theming help text, %1 is a link to adw-gtk3').arg(`<a href="https://duxlabs.dev/docs/dms/application-themes#gtk-applications" style="text-decoration:none; color:${Theme.primary};">adw-gtk3</a>`)
                    textFormat: Text.RichText
                    linkColor: Theme.primary
                    onLinkActivated: url => Qt.openUrlExternally(url)
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor
                        acceptedButtons: Qt.NoButton
                        propagateComposedEvents: true
                    }
                }
            }
        }

        SettingsCard {
            tab: "theme"
            tags: ["applications", "portal", "dark", "terminal"]
            title: I18n.tr("Portal & terminals")
            settingKey: "applications"
            iconName: "apps"

            SettingsToggleRow {
                tab: "theme"
                tags: ["portal", "sync", "dark", "mode", "xdg"]
                settingKey: "syncModeWithPortal"
                text: I18n.tr("Sync with portal")
                description: I18n.tr("Light and dark mode follow and set the system color scheme", "sync with portal toggle description")
                checked: SettingsData.syncModeWithPortal
                onToggled: checked => SettingsData.set("syncModeWithPortal", checked)
            }

            SettingsToggleRow {
                tab: "theme"
                tags: ["terminal", "dark", "always", "scheme"]
                settingKey: "terminalsAlwaysDark"
                text: I18n.tr("Terminals always dark")
                checked: SettingsData.terminalsAlwaysDark
                onToggled: checked => SettingsData.set("terminalsAlwaysDark", checked)
            }

            SettingsSliderRow {
                tab: "theme"
                tags: ["terminal", "opacity", "transparency", "background", "kitty", "foot", "ghostty", "alacritty"]
                settingKey: "terminalOpacity"
                text: I18n.tr("Opacity")
                value: SettingsData.terminalOpacity
                minimum: 10
                maximum: 100
                unit: "%"
                enabled: Theme.matugenAvailable
                onSliderDragFinished: finalValue => SettingsData.set("terminalOpacity", finalValue)
            }

            SettingsToggleRow {
                tab: "theme"
                tags: ["terminal", "palette", "ansi", "colors", "wallpaper", "intensity"]
                settingKey: "terminalPalette"
                text: I18n.tr("Colors from wallpaper")
                enabled: Theme.matugenAvailable
                checked: SettingsData.terminalPalette !== "default"
                onToggled: checked => SettingsData.set("terminalPalette", checked ? "medium" : "default")
            }

            SettingsButtonGroupRow {
                text: I18n.tr("Intensity")
                description: I18n.tr("How far terminal colors shift toward the wallpaper color", "terminal wallpaper colors intensity description")
                visible: SettingsData.terminalPalette !== "default"
                enabled: Theme.matugenAvailable
                model: [I18n.tr("Low"), I18n.tr("Medium"), I18n.tr("High")]
                values: ["low", "medium", "high"]
                value: SettingsData.terminalPalette
                fallbackValue: "medium"
                onValueSelected: value => SettingsData.set("terminalPalette", value)
            }
        }

        SettingsCard {
            tab: "theme"
            tags: ["matugen", "templates", "theming"]
            title: I18n.tr("Matugen templates")
            settingKey: "matugenTemplates"
            iconName: "auto_awesome"
            collapsible: true
            expanded: false
            visible: Theme.matugenAvailable

            SettingsToggleRow {
                tab: "theme"
                tags: ["matugen", "user", "templates"]
                settingKey: "runUserMatugenTemplates"
                text: I18n.tr("Run user templates")
                description: I18n.tr("Also runs the templates in your %1", "run user matugen templates toggle description, %1 is the matugen config file").arg("matugen config.toml")
                checked: SettingsData.runUserMatugenTemplates
                onToggled: checked => SettingsData.set("runUserMatugenTemplates", checked)
            }

            SettingsToggleRow {
                tab: "theme"
                tags: ["matugen", "dms", "templates"]
                settingKey: "runDmsMatugenTemplates"
                text: I18n.tr("Run DMS templates")
                checked: SettingsData.runDmsMatugenTemplates
                onToggled: checked => SettingsData.set("runDmsMatugenTemplates", checked)
            }

            SettingsToggleRow {
                enabled: SettingsData.runDmsMatugenTemplates
                tab: "theme"
                tags: ["matugen", "gtk", "template"]
                settingKey: "matugenTemplateGtk"
                text: "GTK"
                description: root.getTemplateDescription("gtk", "")
                descriptionColor: root.getTemplateDescriptionColor("gtk")
                checked: SettingsData.matugenTemplateGtk
                onToggled: checked => SettingsData.set("matugenTemplateGtk", checked)
            }

            SettingsToggleRow {
                enabled: SettingsData.runDmsMatugenTemplates
                tab: "theme"
                tags: ["matugen", "niri", "template"]
                settingKey: "matugenTemplateNiri"
                text: "niri"
                description: root.getTemplateDescription("niri", "")
                descriptionColor: root.getTemplateDescriptionColor("niri")
                checked: SettingsData.matugenTemplateNiri
                onToggled: checked => SettingsData.set("matugenTemplateNiri", checked)
            }

            SettingsToggleRow {
                enabled: SettingsData.runDmsMatugenTemplates
                tab: "theme"
                tags: ["matugen", "hyprland", "template"]
                settingKey: "matugenTemplateHyprland"
                text: "Hyprland"
                description: root.getTemplateDescription("hyprland", "")
                descriptionColor: root.getTemplateDescriptionColor("hyprland")
                checked: SettingsData.matugenTemplateHyprland
                onToggled: checked => SettingsData.set("matugenTemplateHyprland", checked)
            }

            SettingsToggleRow {
                enabled: SettingsData.runDmsMatugenTemplates
                tab: "theme"
                tags: ["matugen", "mangowc", "template"]
                settingKey: "matugenTemplateMangowc"
                text: "mangowc"
                description: root.getTemplateDescription("mangowc", "")
                descriptionColor: root.getTemplateDescriptionColor("mangowc")
                checked: SettingsData.matugenTemplateMangowc
                onToggled: checked => SettingsData.set("matugenTemplateMangowc", checked)
            }

            SettingsToggleRow {
                enabled: SettingsData.runDmsMatugenTemplates
                tab: "theme"
                tags: ["matugen", "qt5ct", "template"]
                settingKey: "matugenTemplateQt5ct"
                text: "qt5ct"
                description: root.getTemplateDescription("qt5ct", "")
                descriptionColor: root.getTemplateDescriptionColor("qt5ct")
                checked: SettingsData.matugenTemplateQt5ct
                onToggled: checked => SettingsData.set("matugenTemplateQt5ct", checked)
            }

            SettingsToggleRow {
                enabled: SettingsData.runDmsMatugenTemplates
                tab: "theme"
                tags: ["matugen", "qt6ct", "template"]
                settingKey: "matugenTemplateQt6ct"
                text: "qt6ct"
                description: root.getTemplateDescription("qt6ct", "")
                descriptionColor: root.getTemplateDescriptionColor("qt6ct")
                checked: SettingsData.matugenTemplateQt6ct
                onToggled: checked => SettingsData.set("matugenTemplateQt6ct", checked)
            }

            SettingsToggleRow {
                enabled: SettingsData.runDmsMatugenTemplates
                tab: "theme"
                tags: ["matugen", "qtengine", "template", "qt"]
                settingKey: "matugenTemplateQtengine"
                text: "qtengine"
                description: root.getTemplateDescription("qtengine", "")
                descriptionColor: root.getTemplateDescriptionColor("qtengine")
                checked: SettingsData.matugenTemplateQtengine
                onToggled: checked => SettingsData.set("matugenTemplateQtengine", checked)
            }

            SettingsToggleRow {
                enabled: SettingsData.runDmsMatugenTemplates
                tab: "theme"
                tags: ["matugen", "fcitx5", "input", "template"]
                settingKey: "matugenTemplateFcitx5"
                text: "Fcitx5"
                description: root.getTemplateDescription("fcitx5", "")
                descriptionColor: root.getTemplateDescriptionColor("fcitx5")
                checked: SettingsData.matugenTemplateFcitx5
                onToggled: checked => SettingsData.set("matugenTemplateFcitx5", checked)
            }

            SettingsToggleRow {
                enabled: SettingsData.runDmsMatugenTemplates
                tab: "theme"
                tags: ["matugen", "firefox", "template"]
                settingKey: "matugenTemplateFirefox"
                text: "Firefox"
                description: root.getTemplateDescription("firefox", "")
                descriptionColor: root.getTemplateDescriptionColor("firefox")
                checked: SettingsData.matugenTemplateFirefox
                onToggled: checked => SettingsData.set("matugenTemplateFirefox", checked)
            }

            SettingsToggleRow {
                enabled: SettingsData.runDmsMatugenTemplates
                tab: "theme"
                tags: ["matugen", "pywalfox", "template"]
                settingKey: "matugenTemplatePywalfox"
                text: "pywalfox"
                description: root.getTemplateDescription("pywalfox", "")
                descriptionColor: root.getTemplateDescriptionColor("pywalfox")
                checked: SettingsData.matugenTemplatePywalfox
                onToggled: checked => SettingsData.set("matugenTemplatePywalfox", checked)
            }

            SettingsToggleRow {
                enabled: SettingsData.runDmsMatugenTemplates
                tab: "theme"
                tags: ["matugen", "zenbrowser", "template"]
                settingKey: "matugenTemplateZenBrowser"
                text: "zenbrowser"
                description: root.getTemplateDescription("zenbrowser", "")
                descriptionColor: root.getTemplateDescriptionColor("zenbrowser")
                checked: SettingsData.matugenTemplateZenBrowser
                onToggled: checked => SettingsData.set("matugenTemplateZenBrowser", checked)
            }

            SettingsToggleRow {
                enabled: SettingsData.runDmsMatugenTemplates
                tab: "theme"
                tags: ["matugen", "vesktop", "discord", "template"]
                settingKey: "matugenTemplateVesktop"
                text: "vesktop"
                description: root.getTemplateDescription("vesktop", "")
                descriptionColor: root.getTemplateDescriptionColor("vesktop")
                checked: SettingsData.matugenTemplateVesktop
                onToggled: checked => SettingsData.set("matugenTemplateVesktop", checked)
            }

            SettingsToggleRow {
                enabled: SettingsData.runDmsMatugenTemplates
                tab: "theme"
                tags: ["matugen", "vencord", "discord", "template"]
                settingKey: "matugenTemplateVencord"
                text: "vencord"
                description: root.getTemplateDescription("vencord", "")
                descriptionColor: root.getTemplateDescriptionColor("vencord")
                checked: SettingsData.matugenTemplateVencord
                onToggled: checked => SettingsData.set("matugenTemplateVencord", checked)
            }

            SettingsToggleRow {
                enabled: SettingsData.runDmsMatugenTemplates
                tab: "theme"
                tags: ["matugen", "equibop", "discord", "template"]
                settingKey: "matugenTemplateEquibop"
                text: "equibop"
                description: root.getTemplateDescription("equibop", "")
                descriptionColor: root.getTemplateDescriptionColor("equibop")
                checked: SettingsData.matugenTemplateEquibop
                onToggled: checked => SettingsData.set("matugenTemplateEquibop", checked)
            }

            SettingsToggleRow {
                enabled: SettingsData.runDmsMatugenTemplates
                tab: "theme"
                tags: ["matugen", "ghostty", "terminal", "template"]
                settingKey: "matugenTemplateGhostty"
                text: "Ghostty"
                description: root.getTemplateDescription("ghostty", "")
                descriptionColor: root.getTemplateDescriptionColor("ghostty")
                checked: SettingsData.matugenTemplateGhostty
                onToggled: checked => SettingsData.set("matugenTemplateGhostty", checked)
            }

            SettingsToggleRow {
                enabled: SettingsData.runDmsMatugenTemplates
                tab: "theme"
                tags: ["matugen", "kitty", "terminal", "template"]
                settingKey: "matugenTemplateKitty"
                text: "kitty"
                description: root.getTemplateDescription("kitty", "")
                descriptionColor: root.getTemplateDescriptionColor("kitty")
                checked: SettingsData.matugenTemplateKitty
                onToggled: checked => SettingsData.set("matugenTemplateKitty", checked)
            }

            SettingsToggleRow {
                enabled: SettingsData.runDmsMatugenTemplates
                tab: "theme"
                tags: ["matugen", "foot", "terminal", "template"]
                settingKey: "matugenTemplateFoot"
                text: "foot"
                description: root.getTemplateDescription("foot", "")
                descriptionColor: root.getTemplateDescriptionColor("foot")
                checked: SettingsData.matugenTemplateFoot
                onToggled: checked => SettingsData.set("matugenTemplateFoot", checked)
            }

            SettingsDivider {
                visible: neovimThemeToggle.visible && neovimThemeToggle.checked
            }

            SettingsToggleRow {
                id: neovimThemeToggle
                enabled: SettingsData.runDmsMatugenTemplates
                tab: "theme"
                tags: ["matugen", "neovim", "terminal", "template"]
                settingKey: "matugenTemplateNeovim"
                text: "neovim"
                description: root.getTemplateDescription("nvim", I18n.tr("Required plugin: %1", "%1 is a repository URL").arg("https://github.com/duxlabs-dev/base46"))
                descriptionColor: root.getTemplateDescriptionColor("nvim")
                checked: SettingsData.matugenTemplateNeovim
                onToggled: checked => SettingsData.set("matugenTemplateNeovim", checked)
            }

            SettingsDropdownRow {
                enabled: neovimThemeToggle.visible && neovimThemeToggle.checked
                text: I18n.tr("Dark mode base")
                tab: "theme"
                tags: ["matugen", "neovim", "terminal", "template"]
                settingKey: "matugenTemplateNeovimSettings"
                resetKeys: []
                currentValue: SettingsData.matugenTemplateNeovimSettings?.dark?.baseTheme ?? "github_dark"
                options: root.neovimDarkBaseThemes.concat(root.neovimLightBaseThemes)
                enableFuzzySearch: true
                onValueChanged: value => root.setNeovimSetting("dark", "baseTheme", value)
            }

            SettingsDropdownRow {
                enabled: neovimThemeToggle.visible && neovimThemeToggle.checked
                text: I18n.tr("Light mode base")
                tab: "theme"
                tags: ["matugen", "neovim", "terminal", "template"]
                settingKey: "matugenTemplateNeovimSettings"
                resetKeys: []
                currentValue: SettingsData.matugenTemplateNeovimSettings?.light?.baseTheme ?? "github_light"
                options: root.neovimLightBaseThemes.concat(root.neovimDarkBaseThemes)
                enableFuzzySearch: true
                onValueChanged: value => root.setNeovimSetting("light", "baseTheme", value)
            }

            SettingsSliderRow {
                enabled: neovimThemeToggle.visible && neovimThemeToggle.checked
                text: I18n.tr("Dark mode harmony")
                tags: ["matugen", "neovim", "terminal", "template", "tint"]
                settingKey: "matugenTemplateNeovimSettings"
                resetKeys: []
                minimum: 0
                maximum: 100
                value: (SettingsData.matugenTemplateNeovimSettings?.dark?.harmony ?? 0.5) * 100
                onSliderValueChanged: value => root.setNeovimSetting("dark", "harmony", value / 100)
            }

            SettingsSliderRow {
                enabled: neovimThemeToggle.visible && neovimThemeToggle.checked
                text: I18n.tr("Light mode harmony")
                tags: ["matugen", "neovim", "terminal", "template", "tint"]
                settingKey: "matugenTemplateNeovimSettings"
                resetKeys: []
                minimum: 0
                maximum: 100
                value: (SettingsData.matugenTemplateNeovimSettings?.light?.harmony ?? 0.5) * 100
                onSliderValueChanged: value => root.setNeovimSetting("light", "harmony", value / 100)
            }

            SettingsToggleRow {
                enabled: neovimThemeToggle.visible && neovimThemeToggle.checked
                text: I18n.tr("Follow DMS background color")
                tags: ["matugen", "neovim", "terminal", "template"]
                settingKey: "matugenTemplateNeovimSetBackground"
                checked: SettingsData.matugenTemplateNeovimSetBackground ?? true
                onToggled: checked => SettingsData.set("matugenTemplateNeovimSetBackground", checked)
            }

            SettingsDivider {
                visible: neovimThemeToggle.visible && neovimThemeToggle.checked
            }

            SettingsToggleRow {
                enabled: SettingsData.runDmsMatugenTemplates
                tab: "theme"
                tags: ["matugen", "alacritty", "terminal", "template"]
                settingKey: "matugenTemplateAlacritty"
                text: "Alacritty"
                description: root.getTemplateDescription("alacritty", "")
                descriptionColor: root.getTemplateDescriptionColor("alacritty")
                checked: SettingsData.matugenTemplateAlacritty
                onToggled: checked => SettingsData.set("matugenTemplateAlacritty", checked)
            }

            SettingsToggleRow {
                enabled: SettingsData.runDmsMatugenTemplates
                tab: "theme"
                tags: ["matugen", "wezterm", "terminal", "template"]
                settingKey: "matugenTemplateWezterm"
                text: "WezTerm"
                description: root.getTemplateDescription("wezterm", "")
                descriptionColor: root.getTemplateDescriptionColor("wezterm")
                checked: SettingsData.matugenTemplateWezterm
                onToggled: checked => SettingsData.set("matugenTemplateWezterm", checked)
            }

            SettingsToggleRow {
                enabled: SettingsData.runDmsMatugenTemplates
                tab: "theme"
                tags: ["matugen", "dgop", "template"]
                settingKey: "matugenTemplateDgop"
                text: "dgop"
                description: root.getTemplateDescription("dgop", "")
                descriptionColor: root.getTemplateDescriptionColor("dgop")
                checked: SettingsData.matugenTemplateDgop
                onToggled: checked => SettingsData.set("matugenTemplateDgop", checked)
            }

            SettingsToggleRow {
                enabled: SettingsData.runDmsMatugenTemplates
                tab: "theme"
                tags: ["matugen", "kcolorscheme", "kde", "template"]
                settingKey: "matugenTemplateKcolorscheme"
                text: "KColorScheme"
                description: root.getTemplateDescription("kcolorscheme", "")
                descriptionColor: root.getTemplateDescriptionColor("kcolorscheme")
                checked: SettingsData.matugenTemplateKcolorscheme
                onToggled: checked => SettingsData.set("matugenTemplateKcolorscheme", checked)
            }

            SettingsToggleRow {
                enabled: SettingsData.runDmsMatugenTemplates
                tab: "theme"
                tags: ["matugen", "vscode", "code", "template"]
                settingKey: "matugenTemplateVscode"
                text: "VS Code"
                description: root.getTemplateDescription("vscode", I18n.tr("Requires the DMS Theme extension from the editor marketplace", "vscode matugen template description"))
                descriptionColor: root.getTemplateDescriptionColor("vscode")
                checked: SettingsData.matugenTemplateVscode
                onToggled: checked => SettingsData.set("matugenTemplateVscode", checked)
            }

            SettingsToggleRow {
                enabled: SettingsData.runDmsMatugenTemplates
                tab: "theme"
                tags: ["matugen", "emacs", "template"]
                settingKey: "matugenTemplateEmacs"
                text: "Emacs"
                description: root.getTemplateDescription("emacs", "")
                descriptionColor: root.getTemplateDescriptionColor("emacs")
                checked: SettingsData.matugenTemplateEmacs
                onToggled: checked => SettingsData.set("matugenTemplateEmacs", checked)
            }

            SettingsToggleRow {
                enabled: SettingsData.runDmsMatugenTemplates
                tab: "theme"
                tags: ["matugen", "zed", "template"]
                settingKey: "matugenTemplateZed"
                text: "Zed"
                description: root.getTemplateDescription("zed", "")
                descriptionColor: root.getTemplateDescriptionColor("zed")
                checked: SettingsData.matugenTemplateZed
                onToggled: checked => SettingsData.set("matugenTemplateZed", checked)
            }
        }
    }
}
