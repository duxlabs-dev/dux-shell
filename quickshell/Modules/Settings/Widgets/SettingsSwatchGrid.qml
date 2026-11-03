pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Widgets
import qs.Modules.Settings.Widgets

Flow {
    id: root

    property var options: []
    property string currentValue: ""
    property bool compact: false
    property real maxHeight: 0
    property real minTileWidth: compact ? Theme.minimumTouchTargetSize + Theme.spacingM : SettingsMetrics.swatchTileMinWidth
    // option => {preview, badge, primary, secondary, tertiary}, re-evaluated per tile so `options` stays stable across theme changes
    property var resolveOption: null
    signal selected(string value)
    signal deleteRequested(string value)

    readonly property int columns: Math.max(1, Math.floor((width + spacing) / (minTileWidth + spacing)))
    readonly property real tileWidth: Math.floor((width - spacing * (columns - 1)) / columns)
    readonly property real compactTileHeight: Theme.minimumTouchTargetSize + Theme.spacingS * 2
    readonly property int maxRows: maxHeight > 0 && compact ? Math.max(1, Math.floor((maxHeight + spacing) / (compactTileHeight + spacing))) : 0
    readonly property var shownOptions: maxRows > 0 ? options.slice(0, columns * maxRows) : options

    width: parent?.width ?? 0
    spacing: Theme.spacingS

    Repeater {
        model: root.shownOptions

        Rectangle {
            id: tile
            required property var modelData

            readonly property var option: root.resolveOption ? Object.assign({}, modelData, root.resolveOption(modelData)) : modelData
            readonly property bool isActive: root.currentValue === modelData.value
            readonly property bool hasPreview: !root.compact && !!option.preview
            readonly property bool deletable: !!modelData.deletable

            width: root.tileWidth
            height: root.compact ? root.compactTileHeight : media.height + label.implicitHeight + Theme.spacingS * 3
            radius: Theme.cornerRadiusM
            color: SettingsMetrics.controlColor
            border.width: isActive ? Theme.outlineWidthFocused : Theme.layerOutlineWidth
            border.color: isActive ? Theme.primary : Theme.outlineMedium

            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: modelData.label
            Accessible.checkable: true
            Accessible.checked: isActive
            Accessible.onPressAction: root.selected(modelData.value)
            Keys.onSpacePressed: root.selected(modelData.value)
            Keys.onEnterPressed: root.selected(modelData.value)
            Keys.onReturnPressed: root.selected(modelData.value)
            Keys.onDeletePressed: event => {
                if (!tile.deletable)
                    return;
                root.deleteRequested(tile.modelData.value);
                event.accepted = true;
            }

            FocusRing {
                id: tileRing
            }

            StateLayer {
                id: tileState
                anchors.fill: parent
                stateColor: Theme.primary
                focused: tileRing.visible
                tooltipText: root.compact ? tile.modelData.label : null
                onClicked: {
                    tileRing.pointerFocused = true;
                    tile.forceActiveFocus(Qt.MouseFocusReason);
                    root.selected(tile.modelData.value);
                }
            }

            Item {
                id: media
                anchors.top: parent.top
                anchors.topMargin: Theme.spacingS
                anchors.horizontalCenter: parent.horizontalCenter
                width: tile.hasPreview ? parent.width - Theme.spacingS * 2 : Theme.minimumTouchTargetSize
                height: tile.hasPreview ? Math.round(width * SettingsMetrics.choiceCardPreviewRatio) : Theme.minimumTouchTargetSize

                Rectangle {
                    anchors.fill: parent
                    visible: tile.hasPreview
                    radius: Theme.cornerRadiusS
                    color: Theme.foregroundColor(Theme.chipSurfaceNested, true)
                    clip: true

                    Image {
                        id: previewImage
                        anchors.fill: parent
                        source: tile.hasPreview ? "file://" + tile.option.preview : ""
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        smooth: true
                        mipmap: true
                    }
                }

                DPaletteSwatch {
                    anchors.centerIn: parent
                    width: Theme.minimumTouchTargetSize
                    height: Theme.minimumTouchTargetSize
                    visible: !tile.hasPreview || previewImage.status !== Image.Ready
                    primaryColor: tile.option.primary
                    secondaryColor: tile.option.secondary ?? tile.option.primary
                    tertiaryColor: tile.option.tertiary ?? tile.option.secondary ?? tile.option.primary
                }
            }

            DBadge {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.margins: Theme.spacingXS
                visible: !root.compact && !!tile.option.badge
                text: tile.option.badge ?? ""
                color: Theme.secondaryContainer
                textColor: Theme.onSecondaryContainer
            }

            DActionButton {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: Theme.spacingXS
                visible: tile.deletable && !root.compact && (tile.activeFocus || activeFocus || hovered || tileState.containsMouse)
                iconName: "delete"
                iconColor: Theme.error
                backgroundColor: SettingsMetrics.controlSurface
                tooltipText: I18n.tr("Delete")
                onClicked: root.deleteRequested(tile.modelData.value)
            }

            StyledText {
                id: label
                visible: !root.compact
                anchors.top: media.bottom
                anchors.topMargin: Theme.spacingS
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: Theme.spacingXS
                anchors.rightMargin: Theme.spacingXS
                text: tile.modelData.label
                font.pixelSize: Theme.fontSizeSmall
                font.weight: tile.isActive ? Theme.fontWeightMedium : Theme.fontWeight
                color: tile.isActive ? Theme.primary : Theme.surfaceText
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
        }
    }
}
