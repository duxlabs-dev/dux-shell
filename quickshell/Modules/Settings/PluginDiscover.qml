import QtQuick
import Quickshell.Widgets
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import qs.Modules.Settings.Widgets

Column {
    id: root

    property var picks: []
    property var shelves: []
    property int columns: 1
    property real cardSpacing: Theme.spacingM
    property int shelfIndex: 0

    readonly property var shelf: shelves[Math.min(shelfIndex, shelves.length - 1)] || null
    readonly property real cardWidth: Math.floor((width - cardSpacing * (columns - 1)) / columns)
    readonly property int pickColumns: Math.min(Math.max(1, picks.length), columns > 1 ? 2 : 1)
    readonly property int pickHeight: Theme.fontSizeMedium + Theme.fontSizeSmall * 6 + Theme.spacingM * 2

    signal pluginOpened(var plugin)
    signal installRequested(var plugin)

    spacing: Theme.spacingM

    Grid {
        width: parent.width
        columns: root.pickColumns
        spacing: root.cardSpacing
        visible: root.picks.length > 0

        Repeater {
            model: root.picks

            DCard {
                id: pickCard

                required property var modelData
                readonly property var plugin: modelData.plugin

                width: Math.floor((root.width - root.cardSpacing * (root.pickColumns - 1)) / root.pickColumns)
                height: root.pickHeight
                radius: Theme.cornerRadiusM
                color: SettingsMetrics.rowColor
                border.color: Theme.outlineMedium
                border.width: Theme.layerOutlineWidth
                pad: 0
                clickable: true
                Accessible.name: modelData.label + ": " + (plugin.name || "")
                onClicked: root.pluginOpened(plugin)

                ClippingRectangle {
                    id: pickPreview
                    z: 1
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.margins: Theme.spacingS
                    width: Math.round(height / SettingsMetrics.choiceCardPreviewRatio)
                    radius: Theme.cornerRadiusS
                    color: SettingsMetrics.controlColor

                    CachingImage {
                        id: pickImage
                        anchors.fill: parent
                        imagePath: PluginService.thumbUrl(pickCard.plugin)
                        maxCacheSize: 640
                        fillMode: Image.PreserveAspectCrop
                        animate: false
                        visible: status === Image.Ready
                    }

                    DIcon {
                        anchors.centerIn: parent
                        name: pickCard.plugin.icon || "extension"
                        size: Theme.iconSizeLarge
                        color: Theme.onSurfaceVariant
                        visible: pickImage.status !== Image.Ready
                    }
                }

                Column {
                    z: 1
                    anchors.left: pickPreview.right
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Theme.spacingM
                    anchors.rightMargin: Theme.spacingM
                    spacing: Theme.spacingXXS

                    Row {
                        spacing: Theme.spacingXXS

                        DIcon {
                            name: "award_star"
                            size: Theme.iconSizeSmall
                            color: Theme.primary
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: pickCard.modelData.label
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Theme.fontWeightMedium
                            color: Theme.primary
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    StyledText {
                        width: parent.width
                        text: pickCard.plugin.name || ""
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Theme.fontWeightMedium
                        color: Theme.surfaceText
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    StyledText {
                        width: parent.width
                        text: I18n.tr("by %1", "author attribution").arg(pickCard.plugin.author || I18n.tr("Unknown", "unknown author"))
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.onSurfaceVariant
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    StyledText {
                        width: parent.width
                        text: pickCard.plugin.description || ""
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        wrapMode: Text.WordWrap
                        elide: Text.ElideRight
                        maximumLineCount: 2
                    }
                }
            }
        }
    }

    DFilterChips {
        width: parent.width
        visible: root.shelves.length > 0
        model: root.shelves.map(shelf => shelf.label)
        currentIndex: Math.min(root.shelfIndex, Math.max(0, root.shelves.length - 1))
        onSelectionChanged: index => root.shelfIndex = index
    }

    Row {
        width: parent.width
        spacing: root.cardSpacing
        visible: !!root.shelf

        Repeater {
            model: root.shelf ? root.shelf.plugins.slice(0, root.columns) : []

            PluginCard {
                required property var modelData
                required property int index

                width: root.cardWidth
                plugin: modelData
                busy: !!PluginService.installingPlugins[modelData.id]
                installed: modelData.installed || false
                highlight: root.shelf.captions[index] || ""
                onClicked: root.pluginOpened(modelData)
                onInstallRequested: root.installRequested(modelData)
            }
        }
    }

    StyledText {
        text: I18n.tr("All plugins", "plugin browser section title above the full list")
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Theme.fontWeightMedium
        color: Theme.surfaceVariantText
    }
}
