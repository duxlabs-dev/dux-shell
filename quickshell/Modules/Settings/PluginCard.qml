import QtQuick
import Quickshell.Widgets
import qs.Common
import qs.Modules.Settings.Widgets
import qs.Services
import qs.DCommon.Widgets
import "../../Common/PluginRanking.js" as PluginRanking

DCard {
    id: root

    property var plugin: ({})
    property bool busy: false
    property bool installed: false
    property bool selected: false
    property string fallbackIcon: "extension"
    property string highlight: ""
    property string previewSource: PluginService.thumbUrl(plugin)
    property string previewFallback: PluginService.previewUrl(plugin)
    property var badges: PluginService.badgeModel(plugin)
    property bool allowUninstall: false
    property var palette: null
    property string compositor: ""
    property real previewHeight: Math.round((width - Theme.spacingS * 2) * SettingsMetrics.choiceCardPreviewRatio)
    readonly property int infoHeight: Theme.iconButtonSize + Theme.fontSizeSmall * 4 + Theme.spacingS
    readonly property bool compatible: PluginService.checkPluginCompatibility(plugin.requires_dms)
    readonly property var otherCompositors: PluginRanking.unsupportedOn(plugin, compositor)
    readonly property bool focusRingShown: selected && Theme.focusRingWidth > 0

    signal installRequested
    signal uninstallRequested

    implicitHeight: previewHeight + infoHeight + Theme.spacingS * 2 + Theme.spacingM
    radius: Theme.cornerRadiusM
    color: SettingsMetrics.rowColor
    border.color: focusRingShown ? Theme.focusRingColor : Theme.outlineMedium
    border.width: focusRingShown ? Theme.focusRingWidth : Theme.layerOutlineWidth
    pad: 0
    clickable: true
    Accessible.name: plugin.name || ""

    Item {
        id: previewArea
        z: 1
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.spacingS
        height: root.previewHeight

        ClippingRectangle {
            anchors.fill: parent
            radius: Theme.cornerRadiusS
            color: SettingsMetrics.controlColor

            CachingImage {
                id: cardPreview

                property bool useFallback: false

                anchors.fill: parent
                imagePath: useFallback ? root.previewFallback : root.previewSource
                maxCacheSize: 640
                fillMode: Image.PreserveAspectCrop
                animate: false
                visible: status === Image.Ready
                opacity: root.otherCompositors.length > 0 ? 0.5 : 1
                onStatusChanged: {
                    if (status !== Image.Error || useFallback || !root.previewFallback || root.previewFallback === root.previewSource)
                        return;
                    useFallback = true;
                }
            }

            DIcon {
                anchors.centerIn: parent
                name: root.plugin.icon || root.fallbackIcon
                size: Theme.avatarSize
                color: Theme.onSurfaceVariant
                visible: cardPreview.status !== Image.Ready
            }

            DSpinner {
                anchors.centerIn: parent
                running: cardPreview.status === Image.Loading
                visible: running
            }
        }

        DPaletteSwatch {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: Theme.spacingXS
            width: Theme.iconSizeMedium
            height: Theme.iconSizeMedium
            visible: !!root.palette?.primary
            primaryColor: root.palette?.primary ?? Theme.primary
            secondaryColor: root.palette?.secondary ?? primaryColor
            tertiaryColor: root.palette?.tertiary ?? secondaryColor
        }

        Row {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: upvoteBadge.visible ? upvoteBadge.left : parent.right
            anchors.margins: Theme.spacingXS
            spacing: Theme.spacingXXS
            clip: true

            Repeater {
                model: root.badges

                PluginBadge {
                    required property var modelData
                    label: modelData.label
                    iconName: modelData.icon
                    tone: PluginService.badgeTone(modelData.tone)
                }
            }
        }

        PluginBadge {
            id: upvoteBadge
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: Theme.spacingXS
            iconName: "thumb_up"
            label: PluginService.upvoteCount(root.plugin)
            tone: Theme.primary
            visible: !!root.plugin.issueUrl
            // Stays clickable while a vote is sent, so the click never falls through to the card; upvotePlugin ignores it.
            interactive: true
            active: !!PluginService.upvotedPlugins[root.plugin.id]
            tooltipText: active ? I18n.tr("Remove upvote", "plugin upvote button tooltip") : I18n.tr("Upvote on GitHub", "plugin upvote button tooltip")
            Accessible.role: Accessible.Button
            Accessible.name: tooltipText
            onClicked: PluginService.upvotePlugin(root.plugin)
        }

        PluginBadge {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.margins: Theme.spacingXS
            iconName: "auto_awesome"
            label: root.highlight
            tone: Theme.primary
            visible: root.highlight.length > 0
        }

        PluginBadge {
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            anchors.margins: Theme.spacingXS
            iconName: root.installed ? "check_circle" : "desktop_windows"
            label: root.installed ? I18n.tr("Installed", "adjective, plugin or theme is already installed, button state and filter chip") : I18n.tr("%1 only", "lowercase plugin badge, compositors the plugin is limited to").arg(root.otherCompositors.join(", "))
            tone: root.installed ? Theme.primary : Theme.warning
            visible: root.installed || root.otherCompositors.length > 0
        }
    }

    Column {
        z: 1
        anchors.top: previewArea.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Theme.spacingS
        anchors.leftMargin: Theme.spacingM
        anchors.rightMargin: Theme.spacingM
        spacing: Theme.spacingXXS

        Row {
            width: parent.width
            spacing: Theme.spacingS

            DIcon {
                id: cardIcon
                name: root.plugin.icon || root.fallbackIcon
                size: Theme.iconSizeMedium
                color: Theme.primary
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                width: parent.width - cardIcon.width - installAction.width - Theme.spacingS * 2
                text: root.plugin.name || ""
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Theme.fontWeightMedium
                color: Theme.surfaceText
                elide: Text.ElideRight
                maximumLineCount: 1
                anchors.verticalCenter: parent.verticalCenter
            }

            DActionButton {
                id: installAction
                anchors.verticalCenter: parent.verticalCenter
                enabled: !root.busy && (root.installed ? root.allowUninstall : root.compatible)
                iconName: root.busy ? "hourglass_empty" : root.installed ? (root.allowUninstall ? "delete" : "check") : root.compatible ? "download" : "warning"
                iconColor: root.installed && root.allowUninstall ? Theme.error : Theme.primary
                tooltipText: root.installed ? (root.allowUninstall ? I18n.tr("Uninstall") : I18n.tr("Installed")) : root.compatible ? I18n.tr("Install") : I18n.tr("Requires %1", "version requirement").arg(root.plugin.requires_dms || "")
                onClicked: root.installed ? root.uninstallRequested() : root.installRequested()
            }
        }

        StyledText {
            width: parent.width
            text: I18n.tr("by %1", "author attribution").arg(root.plugin.author || I18n.tr("Unknown", "unknown author"))
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.onSurfaceVariant
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        StyledText {
            width: parent.width
            text: root.plugin.description || ""
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
            elide: Text.ElideRight
            maximumLineCount: 2
        }
    }
}
