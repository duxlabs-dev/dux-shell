pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import qs.Modules.Settings.Widgets

Column {
    id: root

    readonly property string pluginDocsUrl: Site.docs + "/dms/plugin-development"
    readonly property string compositorDocsUrl: Site.docs + "/dms/compositors"

    readonly property var features: [
        {
            "icon": "palette",
            "shape": "softBurst",
            "hoverShape": "flower",
            "accent": "purple",
            "heading": "A new design",
            "description": "Material 3 Expressive across Settings, Control Center, Dash, and every control",
            "target": "theme_surfaces"
        },
        {
            "icon": "space_dashboard",
            "shape": "cookie9",
            "hoverShape": "sunny",
            "accent": "blue",
            "heading": "Dash plugins",
            "description": "Plugins add full tabs or overview cards, sized and ordered your way",
            "target": "dank_dash"
        },
        {
            "icon": "lock",
            "shape": "clover4",
            "hoverShape": "cookie4",
            "accent": "green",
            "heading": "Build your lock screen",
            "description": "Place the clock, media, status, and any desktop widget where you want",
            "target": "lock_screen"
        },
        {
            "icon": "lyrics",
            "shape": "sunny",
            "hoverShape": "softBurst",
            "accent": "pink",
            "heading": "Lyrical Engine",
            "description": "Word synced lyrics from six providers, right in the media player",
            "target": "media_player"
        },
        {
            "icon": "wallpaper",
            "shape": "gem",
            "hoverShape": "cookie6",
            "accent": "orange",
            "heading": "Material wallpapers",
            "description": "Presets from your seed color, plus layouts from wallpaper.duxlabs.dev",
            "target": "personalization"
        },
        {
            "icon": "digital_wellbeing",
            "shape": "puffy",
            "hoverShape": "clover8",
            "accent": "teal",
            "heading": "Digital wellbeing",
            "description": "Screen time, daily and app limits, with its own Dash tab",
            "target": "wellbeing"
        }
    ]

    readonly property var additions: [
        {
            "icon": "view_in_ar",
            "accent": "purple",
            "title": "Island",
            "subtitle": "Notch mode, workspace switcher, tray slot, clipboard, and shadows",
            "target": "dankbar_settings"
        },
        {
            "icon": "grid_view",
            "accent": "green",
            "title": "Launcher",
            "subtitle": "Custom keybindings, dmenu mode, Open with, and app editing",
            "target": "launcher"
        },
        {
            "icon": "dock_to_bottom",
            "accent": "orange",
            "title": "Dock",
            "subtitle": "Proximity magnification and a focused app pill",
            "target": "dock_appearance"
        },
        {
            "icon": "notifications",
            "accent": "pink",
            "title": "Notifications",
            "subtitle": "Rule conditions, timed app mutes, and two finger swipe to dismiss",
            "target": "notification_rules"
        },
        {
            "icon": "extension",
            "accent": "teal",
            "title": "Plugin browser",
            "subtitle": "Discover shelves, quick filters, upvotes, and typo tolerant search",
            "target": "plugins"
        },
        {
            "icon": "format_paint",
            "accent": "yellow",
            "title": "Themes",
            "subtitle": "Bold palettes, injected palettes, fixed radius, and terminal opacity",
            "target": "theme"
        },
        {
            "icon": "monitor",
            "accent": "red",
            "title": "Displays",
            "subtitle": "Per-output ICC profiles and color temperature",
            "target": "display_config"
        },
        {
            "icon": "system_update_alt",
            "accent": "blue",
            "title": "Software updates",
            "subtitle": "Update dms from Settings and switch between stable and beta",
            "target": "updater"
        },
        {
            "icon": "devices",
            "accent": "green",
            "title": "More platforms",
            "subtitle": "FreeBSD, Enterprise Linux 10, Mango, Hyprland 0.56, Umbriel, and Aqueous",
            "target": root.compositorDocsUrl
        }
    ]

    function open(target) {
        if (target.startsWith("https://")) {
            Qt.openUrlExternally(target);
            return;
        }
        PopoutService.openSettingsWithTab(target);
    }

    topPadding: 0
    spacing: Theme.spacingL

    ReleaseHero {
        width: parent.width
    }

    Grid {
        id: grid

        readonly property real cardWidth: (width - columnSpacing * (columns - 1)) / columns
        readonly property real cellHeight: {
            let tallest = 0;
            for (const card of children)
                tallest = Math.max(tallest, card.implicitHeight ?? 0);
            return tallest;
        }

        width: parent.width
        columns: 3
        rowSpacing: Theme.spacingS
        columnSpacing: Theme.spacingS
        layoutDirection: I18n.isRtl ? Qt.RightToLeft : Qt.LeftToRight

        Repeater {
            model: root.features

            delegate: FeatureCard {
                required property var modelData

                width: grid.cardWidth
                height: grid.cellHeight
                iconName: modelData.icon
                shape: modelData.shape
                hoverShape: modelData.hoverShape
                accent: modelData.accent
                heading: modelData.heading
                description: modelData.description
                onClicked: root.open(modelData.target)
            }
        }
    }

    SettingsCard {
        title: I18n.tr("More in %1", "changelog card title, %1 is a version").arg(ChangelogService.currentVersion)

        Repeater {
            model: root.additions

            delegate: SettingsRow {
                id: addition

                required property var modelData

                readonly property var accentPair: Theme.accent(modelData.accent)

                title: modelData.title
                subtitle: modelData.subtitle
                resetKeys: []
                clickable: modelData.target !== ""
                showChevron: clickable
                onClicked: root.open(modelData.target)

                leading: Rectangle {
                    width: SettingsMetrics.navIconSize
                    height: width
                    radius: Theme.fullRadius(width, height)
                    color: addition.accentPair?.container ?? Theme.primaryContainer

                    DIcon {
                        anchors.centerIn: parent
                        name: addition.modelData.icon
                        size: Theme.iconSizeMedium
                        color: addition.accentPair?.onContainer ?? Theme.onPrimaryContainer
                    }
                }
            }
        }
    }

    DCard {
        width: parent.width
        height: pluginNote.implicitHeight + pad * 2
        tone: "tertiary"
        pad: Theme.spacingL
        restRadius: Theme.groupedListOuterRadius

        Row {
            id: pluginNote
            width: parent.width
            spacing: Theme.spacingL
            LayoutMirroring.enabled: I18n.isRtl

            DMaterialShape {
                width: Theme.buttonHeightM
                height: width
                shape: "cookie6"
                color: Theme.onTertiaryContainer

                DIcon {
                    anchors.centerIn: parent
                    name: "code"
                    size: Theme.iconSize
                    color: Theme.tertiaryContainer
                }
            }

            Column {
                width: parent.width - Theme.buttonHeightM - docsButton.width - parent.spacing * 2
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXXS

                StyledText {
                    width: parent.width
                    text: I18n.tr("Plugin authors", "changelog section heading")
                    font.pixelSize: Theme.fontSizeLarge
                    font.weight: Theme.fontWeightBold
                    color: Theme.onTertiaryContainer
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignLeft
                }

                StyledText {
                    width: parent.width
                    text: "The Dank* widget wrappers are deprecated. Import qs.DCommon.Widgets and use the D names, DankButton becomes DButton. Each old type logs its replacement."
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.onTertiaryContainer
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignLeft
                }
            }

            DButton {
                id: docsButton
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("Docs")
                iconName: "open_in_new"
                backgroundColor: Theme.onTertiaryContainer
                textColor: Theme.tertiaryContainer
                onClicked: Qt.openUrlExternally(root.pluginDocsUrl)
            }
        }
    }

    Column {
        width: parent.width
        visible: ChangelogService.release !== null
        spacing: 0

        SettingsSectionLabel {
            text: I18n.tr("What changed", "changelog section heading listing the changes in a release")
        }

        ReleaseNotesCard {
            width: parent.width
            release: ChangelogService.release
            showTitle: false
        }
    }
}
