pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import qs.Common
import qs.DCommon.Widgets

Popup {
    id: root

    property string title: ""
    property string current: ""
    // [{id, icon, text, dms}]
    property var actions: []

    signal picked(string action)

    padding: Theme.spacingXS
    contentWidth: Theme.minimumTouchTargetSize * 5
    margins: Theme.spacingS
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    onOpened: (items.itemAt(root.actions.findIndex(a => a.id === root.current)) ?? items.itemAt(0))?.forceActiveFocus()
    // Back to the corner button that opened the menu, so the keyboard user keeps their place.
    onClosed: root.parent?.forceActiveFocus()

    // Opaque on purpose: the menu floats over the gesture scene and readableSurface lets it bleed through.
    background: Item {
        ElevationShadow {
            anchors.fill: parent
            z: -1
            level: Theme.elevationLevel2
            targetRadius: Theme.cornerRadiusM
            targetColor: "transparent"
            shadowEnabled: Theme.elevationEnabled
        }

        Rectangle {
            anchors.fill: parent
            color: Theme.surfaceContainerHighest
            border.width: Theme.layerOutlineWidth
            border.color: Theme.outlineMedium
            radius: Theme.cornerRadiusM
        }
    }

    contentItem: Column {

        StyledText {
            x: Theme.spacingS
            height: Theme.buttonHeightXS
            verticalAlignment: Text.AlignVCenter
            text: root.title
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Theme.fontWeightMedium
            color: Theme.surfaceVariantText
        }

        Repeater {
            id: items

            model: root.actions

            delegate: Rectangle {
                id: item

                required property var modelData
                readonly property bool checked: modelData.id === root.current

                width: parent.width
                height: Theme.minimumTouchTargetSize
                radius: Theme.cornerRadiusS
                border.width: activeFocus ? Theme.outlineWidthFocused : 0
                border.color: Theme.primary
                color: area.containsMouse || activeFocus ? Theme.surfaceTextHover : Theme.withAlpha(Theme.surfaceTextHover, 0)
                activeFocusOnTab: true
                Accessible.role: Accessible.RadioButton
                Accessible.name: modelData.text
                Accessible.checked: checked
                Keys.onReturnPressed: root.picked(modelData.id)
                Keys.onSpacePressed: root.picked(modelData.id)

                Row {
                    x: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingS

                    DIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: item.modelData.icon
                        size: Theme.iconSizeMedium
                        color: item.checked ? Theme.primary : Theme.surfaceVariantText
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: item.modelData.text
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.surfaceText
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingS

                    DBadge {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: item.modelData.dms
                        text: I18n.tr("DMS")
                        tooltipText: I18n.tr("Run by DMS")
                    }

                    DIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: item.checked
                        name: "check"
                        size: Theme.iconSizeSmall
                        color: Theme.primary
                    }
                }

                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.picked(item.modelData.id)
                }
            }
        }
    }
}
