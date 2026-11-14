pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets
import "../../Common/ConfigIncludeResolve.js" as ConfigIncludeResolve

Item {
    id: root

    property var parentModal: null

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    component IncludeRow: SettingsRow {
        id: row

        required property string kind
        required property string page
        readonly property var spec: ConfigIncludeResolve.includeSpec(kind, CompositorService.compositor, CompositorService.isMango ? MangoService.configName : "")
        readonly property ConfigInclude include: ConfigInclude {
            includeKind: row.kind
            procTag: row.kind + "-include-overview"
            onDisabled: {
                if (row.kind === "binds")
                    KeybindsService.forceReload();
            }
        }

        visible: spec !== null
        // Pages stay alive under the stack, so Setup on another page only shows here after a recheck
        onVisibleChanged: {
            if (visible && !include.checking)
                include.check();
        }
        iconName: SettingsTabs.page(page)?.icon ?? ""
        subtitle: {
            if (include.checking)
                return "";
            if (include.included)
                return (spec?.fragmentNames ?? []).map(name => "dms/" + name).join(", ");
            return I18n.tr("Not managed, set up from its page", "compositor include status, the page has a Setup button");
        }
        clickable: !include.checking && !include.included
        showChevron: clickable
        onClicked: keyboard => root.parentModal?.navigateTo(page, keyboard)

        DButton {
            visible: row.include.included
            text: row.include.disabling ? I18n.tr("Stopping...", "button state while dms stops managing a compositor config file") : I18n.tr("Stop managing", "button, dms stops including its config file in the compositor config")
            enabled: !row.include.disabling && !row.include.readOnly
            onClicked: row.include.disable()
        }
    }

    SettingsPage {
        SettingsCard {
            width: parent.width
            tags: ["niri", "hyprland", "mango", "include", "config", "compositor", "manage", "unmanage", "opt out", "restore", "manual", "files"]
            title: I18n.tr("Managed files", "settings card title, compositor config files dms writes")
            settingKey: "compositorIncludes"
            iconName: "description"

            SettingsRow {
                body: StyledText {
                    width: parent.width
                    text: I18n.tr("Stop managing comments out the include in your %1 config and keeps the DMS file, so your own settings take over. Setup on the page turns it back on.", "compositor includes page note, %1 is the compositor name").arg(CompositorService.displayName)
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                }
            }

            IncludeRow {
                kind: "outputs"
                page: "display_config"
                title: I18n.tr("Displays")
            }

            IncludeRow {
                kind: "layout"
                page: "compositor_layout"
                title: I18n.tr("Layout")
            }

            IncludeRow {
                kind: "input"
                page: "keyboard"
                title: I18n.tr("Input")
            }

            IncludeRow {
                kind: "windowrules"
                page: "window_rules"
                title: I18n.tr("Window rules")
            }

            IncludeRow {
                kind: "cursor"
                page: "personalization"
                title: I18n.tr("Cursor")
            }

            IncludeRow {
                kind: "animations"
                page: "compositor_animations"
                title: I18n.tr("Animations")
            }

            IncludeRow {
                kind: "binds"
                page: "keybinds"
                title: I18n.tr("Keybinds")
            }
        }
    }
}
