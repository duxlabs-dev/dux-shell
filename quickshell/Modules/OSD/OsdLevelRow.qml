pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Widgets

Item {
    id: root

    property string iconName: "volume_up"
    property string insetIconName: ""
    property string endIconName: ""
    property bool endIconInteractive: false
    property string endIconLabel: ""
    property string iconLabel: ""
    property bool iconInteractive: false
    property bool tonalIcon: true
    property color iconColor: Theme.onSecondaryContainer
    property color iconBackgroundColor: Theme.secondaryContainer
    property color fillColor: Theme.primary
    property int value: 0
    property int minimum: 0
    property int maximum: 100
    property string unit: "%"
    property string displayText: ""
    property bool sliderEnabled: true
    property string sliderSize: "xs"
    property bool vertical: false
    property real horizontalPadding: -1

    readonly property bool containsMouse: levelSlider.containsMouse || icon.hovered || endIcon.hovered
    readonly property bool endIconHovered: endIcon.hovered
    readonly property Item endIconItem: endIcon
    readonly property bool showValueColumn: SettingsData.osdAlwaysShowValue
    readonly property bool showEndIcon: endIconName.length > 0
    readonly property alias isDragging: levelSlider.isDragging
    readonly property real effectiveHorizontalPadding: horizontalPadding >= 0 ? horizontalPadding : Theme.spacingS
    readonly property bool mirrored: !vertical && I18n.isRtl
    readonly property real crossExtent: vertical ? width : height
    readonly property real iconExtent: tonalIcon ? Math.min(vertical ? levelSlider.trackHeight : Theme.buttonHeightS, crossExtent - effectiveHorizontalPadding * 2) : Theme.iconSize
    readonly property real endPadding: showEndIcon ? Math.max(effectiveHorizontalPadding, (crossExtent - iconExtent) / 2) : effectiveHorizontalPadding
    readonly property real itemSpacing: vertical && showEndIcon ? Theme.spacingM : Theme.spacingS
    readonly property real valueExtent: showEndIcon ? iconExtent + itemSpacing : showValueColumn ? (vertical ? valueLabel.implicitHeight : valueLabel.reservedWidth) + itemSpacing : 0

    signal sliderValueChanged(int newValue)
    signal iconClicked
    signal endIconClicked
    signal hoverChanged(bool hovered)

    onContainsMouseChanged: root.hoverChanged(root.containsMouse)
    height: Theme.osdHeight
    LayoutMirroring.enabled: !vertical && I18n.isRtl
    LayoutMirroring.childrenInherit: true

    OsdIcon {
        id: icon

        x: root.vertical ? (parent.width - width) / 2 : root.mirrored ? parent.width - width - root.endPadding : root.endPadding
        y: root.vertical ? root.endPadding : (parent.height - height) / 2
        width: root.iconExtent
        height: width
        iconName: root.iconName
        iconColor: root.iconColor
        backgroundColor: root.iconBackgroundColor
        tonal: root.tonalIcon
        label: root.iconLabel
        interactive: root.iconInteractive
        available: root.sliderEnabled
        onClicked: root.iconClicked()
    }

    Item {
        id: sliderSlot

        x: root.vertical ? root.effectiveHorizontalPadding : root.mirrored ? root.endPadding + root.valueExtent : root.endPadding + icon.width + root.itemSpacing
        y: root.vertical ? icon.y + icon.height + root.itemSpacing : 0
        width: Math.max(0, root.vertical ? parent.width - root.effectiveHorizontalPadding * 2 : parent.width - root.endPadding * 2 - icon.width - root.itemSpacing - root.valueExtent)
        height: Math.max(0, root.vertical ? parent.height - y - root.endPadding - root.valueExtent : parent.height)

        DSlider {
            id: levelSlider

            anchors.centerIn: parent
            width: root.vertical ? parent.height : parent.width
            rotation: root.vertical ? -90 : 0
            LayoutMirroring.enabled: !root.vertical && I18n.isRtl
            size: root.sliderSize
            insetIcon: root.vertical ? root.insetIconName : ""
            insetIconPosition: root.vertical ? "end" : "start"
            insetIconRotation: root.vertical ? 90 : 0
            minimum: root.minimum
            maximum: Math.max(root.minimum + 1, root.maximum)
            enabled: root.sliderEnabled
            showValue: false
            unit: root.unit
            fillColor: root.fillColor
            valueOverride: root.value
            onSliderValueChanged: newValue => root.sliderValueChanged(newValue)

            Binding on value {
                value: root.value
                restoreMode: Binding.RestoreNone
                when: !levelSlider.isDragging
            }
        }
    }

    Item {
        id: valueContainer

        x: root.vertical ? (parent.width - width) / 2 : root.mirrored ? root.endPadding : parent.width - width - root.endPadding
        y: root.vertical ? parent.height - height - root.endPadding : (parent.height - height) / 2
        width: root.showEndIcon ? root.iconExtent : root.vertical ? parent.width - root.effectiveHorizontalPadding * 2 : valueLabel.reservedWidth
        height: root.showEndIcon ? root.iconExtent : valueLabel.implicitHeight
        visible: root.showEndIcon || root.showValueColumn

        NumericText {
            id: valueLabel

            anchors.fill: parent
            text: !root.showEndIcon && root.displayText.length > 0 ? root.displayText : Math.round(root.value) + root.unit
            reserveText: Math.round(root.maximum) + root.unit
            color: !root.showEndIcon ? Theme.onSurface : root.sliderEnabled ? root.fillColor : Theme.onSurface_38
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Theme.fontWeightMedium
            horizontalAlignment: root.vertical || root.showEndIcon ? Text.AlignHCenter : Text.AlignRight
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            visible: root.showValueColumn
        }

        OsdIcon {
            id: endIcon

            anchors.fill: parent
            iconName: root.endIconName
            iconColor: root.fillColor
            tonal: false
            label: root.endIconLabel
            interactive: root.endIconInteractive
            available: root.sliderEnabled
            visible: !root.showValueColumn
            onClicked: root.endIconClicked()
        }
    }
}
