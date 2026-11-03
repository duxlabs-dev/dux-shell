pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Widgets
import qs.Common
import qs.DCommon.Widgets
import qs.Widgets
import "../../../DCommon/Common/MaterialWallpaper.js" as Art

Flow {
    id: root

    property string preset: Art.defaultPreset
    property string seed: Art.defaultSeed
    property real aspectRatio: Art.designWidth / Art.designHeight
    readonly property var profiles: SessionData.materialWallpaperProfiles
    readonly property var options: Art.profiles(profiles)
    readonly property int columns: Math.max(1, Math.min(options.length + 1, Math.floor(width / SettingsMetrics.previewTileMinWidth)))
    readonly property real tileWidth: (width - spacing * (columns - 1)) / columns
    readonly property real tileHeight: (tileWidth - Theme.spacingS * 2) / aspectRatio + labelMetrics.height + Theme.spacingM * 2
    signal selected(string preset)
    signal removeRequested(string preset, string label)
    signal importRequested

    width: parent.width
    spacing: Theme.spacingS

    StyledTextMetrics {
        id: labelMetrics
        font.pixelSize: Theme.fontSizeSmall
        text: "Ag"
    }

    Repeater {
        model: root.options
        Rectangle {
            id: tile
            required property var modelData
            readonly property bool selected: root.preset === modelData.id
            readonly property string label: MaterialWallpaperOptions.profileLabel(modelData)
            readonly property var scene: Art.composition({
                "preset": modelData.id,
                "seed": root.seed
            }, root.profiles)
            width: root.tileWidth
            height: root.tileHeight
            radius: Theme.cornerRadiusM
            color: selected ? Theme.selectedContainer : SettingsMetrics.controlColor
            border.width: selected ? Theme.outlineWidthFocused : Theme.layerOutlineWidth
            border.color: selected ? Theme.primary : Theme.outlineMedium
            activeFocusOnTab: true
            Accessible.role: Accessible.RadioButton
            Accessible.name: label
            Accessible.checked: selected
            Accessible.onPressAction: root.selected(modelData.id)
            Keys.onSpacePressed: root.selected(modelData.id)
            Keys.onReturnPressed: root.selected(modelData.id)
            Keys.onEnterPressed: root.selected(modelData.id)
            Keys.onDeletePressed: root.removeRequested(modelData.id, label)

            ClippingRectangle {
                id: preview
                x: Theme.spacingS
                y: Theme.spacingS
                width: parent.width - Theme.spacingS * 2
                height: width / root.aspectRatio
                radius: Theme.cornerRadiusS
                color: Theme.surface
                MaterialWallpaper {
                    anchors.fill: parent
                    composition: tile.scene
                }
            }
            StyledText {
                anchors.top: preview.bottom
                anchors.topMargin: Theme.spacingS
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - Theme.spacingM * 2
                text: tile.label
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                color: tile.selected ? Theme.onSelectedContainer : Theme.surfaceText
                font.pixelSize: Theme.fontSizeSmall
            }
            FocusRing {
                id: ring
            }
            HoverHandler {
                id: hover
            }
            StateLayer {
                anchors.fill: parent
                cornerRadius: tile.radius
                stateColor: Theme.primary
                focused: ring.visible
                onClicked: {
                    ring.pointerFocused = true;
                    tile.forceActiveFocus(Qt.MouseFocusReason);
                    root.selected(tile.modelData.id);
                }
            }
            DIconButton {
                anchors.top: preview.top
                anchors.right: preview.right
                anchors.margins: Theme.spacingXS
                visible: hover.hovered || tile.activeFocus || activeFocus
                iconName: "delete"
                variant: "tonal"
                Accessible.name: I18n.tr("Delete")
                onClicked: root.removeRequested(tile.modelData.id, tile.label)
            }
        }
    }

    Rectangle {
        id: importTile
        width: root.tileWidth
        height: root.tileHeight
        radius: Theme.cornerRadiusM
        color: SettingsMetrics.controlColor
        border.width: Theme.layerOutlineWidth
        border.color: Theme.outlineMedium
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: I18n.tr("Import")
        Accessible.onPressAction: root.importRequested()
        Keys.onSpacePressed: root.importRequested()
        Keys.onReturnPressed: root.importRequested()
        Keys.onEnterPressed: root.importRequested()

        Column {
            anchors.centerIn: parent
            spacing: Theme.spacingS
            DIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: "add"
                size: Theme.iconSizeLarge
                color: Theme.primary
            }
            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: I18n.tr("Import")
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeSmall
            }
        }
        FocusRing {
            id: importRing
        }
        StateLayer {
            anchors.fill: parent
            cornerRadius: importTile.radius
            stateColor: Theme.primary
            focused: importRing.visible
            onClicked: {
                importRing.pointerFocused = true;
                importTile.forceActiveFocus(Qt.MouseFocusReason);
                root.importRequested();
            }
        }
    }
}
