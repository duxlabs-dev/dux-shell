pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import qs.Modules.Settings.Widgets

Column {
    id: root

    readonly property string migrateDocsUrl: Site.docs + "/dms/cli-migrate"
    readonly property string compositorDocsUrl: Site.docs + "/dms/compositors"

    readonly property var features: [
        {
            "icon": "density_medium",
            "shape": "softBurst",
            "hoverShape": "flower",
            "accent": "purple",
            "heading": "Interface density",
            "description": "Spacious, Comfortable, Compact, or Dense, with text and fields scaling along",
            "target": "theme_surfaces"
        },
        {
            "icon": "rounded_corner",
            "shape": "cookie9",
            "hoverShape": "sunny",
            "accent": "blue",
            "heading": "DMS Classic",
            "description": "One corner radius on every control, no pills or press morphing",
            "target": "theme_surfaces"
        },
        {
            "icon": "lyrics",
            "shape": "clover4",
            "hoverShape": "cookie4",
            "accent": "pink",
            "heading": "Media player",
            "description": "An Expressive redesign, a reworked Bento layout, and lyrics in the island",
            "target": "media_player"
        },
        {
            "icon": "monitor_heart",
            "shape": "sunny",
            "hoverShape": "softBurst",
            "accent": "green",
            "heading": "System monitor",
            "description": "Per-device graphs, disk health, process details, and a shareable report",
            "target": "system_monitor"
        },
        {
            "icon": "movie",
            "shape": "gem",
            "hoverShape": "cookie6",
            "accent": "orange",
            "heading": "Video wallpapers",
            "description": "Play a video as your wallpaper, paused while locked or covered",
            "target": "wallpaper"
        },
        {
            "icon": "keyboard",
            "shape": "puffy",
            "hoverShape": "clover8",
            "accent": "teal",
            "heading": "New OSDs",
            "description": "Keyboard layout, Num Lock, and fcitx5 input method changes",
            "target": "osd"
        }
    ]

    readonly property var additions: [
        {
            "icon": "space_dashboard",
            "accent": "purple",
            "title": "Dash",
            "subtitle": "A user info card, keyboard navigation, and the tab bar on the island",
            "target": "dank_dash"
        },
        {
            "icon": "speaker",
            "accent": "pink",
            "title": "Audio",
            "subtitle": "Turn audio cards off, and back on from their own list",
            "target": "audio"
        },
        {
            "icon": "partly_cloudy_day",
            "accent": "blue",
            "title": "Weather",
            "subtitle": "MET Norway, with an ordered fallback when a provider is down",
            "target": "weather"
        },
        {
            "icon": "power_settings_new",
            "accent": "red",
            "title": "Power menu",
            "subtitle": "Reboot into firmware setup",
            "target": "power_sleep"
        },
        {
            "icon": "view_quilt",
            "accent": "green",
            "title": "niri",
            "subtitle": "Ready for the next release: release binds, lone modifier binds, and new window rules",
            "target": root.compositorDocsUrl + "#next-niri-release"
        },
        {
            "icon": "water_drop",
            "accent": "teal",
            "title": "Hyprland",
            "subtitle": "Lua config only, Hyprland 0.57, and more wobbly window physics",
            "target": root.compositorDocsUrl + "#hyprland-configuration"
        },
        {
            "icon": "view_column",
            "accent": "orange",
            "title": "mangowm",
            "subtitle": "Native config.toml support, for mangowm 0.18 and newer",
            "target": root.compositorDocsUrl + "#mangowc-configuration"
        },
        {
            "icon": "folder_special",
            "accent": "yellow",
            "title": "Dux suite",
            "subtitle": "Folder colors and previews in Dux Files, calendar blur, and new dgop sensors",
            "target": Site.docs + "/dfiles"
        },
        {
            "icon": "deployed_code",
            "accent": "blue",
            "title": "Fedora Atomic",
            "subtitle": "The Dux installer supports Silverblue, Bazzite, and other bootc images",
            "target": Site.docs + "/duxinstall#fedora-atomic--bootc-images"
        }
    ]

    function open(target) {
        if (target.startsWith("https://")) {
            Qt.openUrlExternally(target);
            return;
        }
        if (target === "system_monitor") {
            PopoutService.showProcessListModal();
            return;
        }
        PopoutService.openSettingsWithTab(target);
    }

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
        height: migrateNote.implicitHeight + pad * 2
        tone: "tertiary"
        pad: Theme.spacingL
        restRadius: Theme.groupedListOuterRadius

        Row {
            id: migrateNote
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
                    name: "move_down"
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
                    text: "Move to the Dux Labs repositories"
                    font.pixelSize: Theme.fontSizeLarge
                    font.weight: Theme.fontWeightBold
                    color: Theme.onTertiaryContainer
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignLeft
                }

                StyledText {
                    width: parent.width
                    text: "Packaged installs now update from Dux Labs. Run dms migrate dux once, it lists every repository it moves and asks first. On Arch, pacman swaps in dux-shell on its own."
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
                onClicked: Qt.openUrlExternally(root.migrateDocsUrl)
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
