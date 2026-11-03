pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Widgets

Item {
    id: root

    required property var controller
    required property string activityId
    required property string label
    property string value: ""
    property string iconName: ""
    property color iconColor: Theme.primary
    property Component leading: null

    readonly property bool isVertical: root.controller.isVertical

    function pushMeasuredLength() {
        root.controller.setDestinationContentLength(root.activityId, root.isVertical ? compactColumn.implicitHeight : compactRow.implicitWidth);
    }

    Component.onCompleted: root.pushMeasuredLength()
    onIsVerticalChanged: root.pushMeasuredLength()

    Row {
        id: compactRow

        anchors.centerIn: parent
        visible: !root.isVertical
        spacing: Theme.spacingS

        onImplicitWidthChanged: root.pushMeasuredLength()

        Loader {
            anchors.verticalCenter: parent.verticalCenter
            active: !root.isVertical && root.leading !== null
            visible: active
            sourceComponent: root.leading
        }

        DIcon {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.iconName !== ""
            name: root.iconName
            size: Theme.iconSizeSmall
            color: root.iconColor
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: root.label
            color: Theme.surfaceText
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Theme.fontWeightMedium
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.value !== ""
            text: root.value
            color: Theme.surfaceTextSecondary
            font.pixelSize: Theme.fontSizeMedium
        }
    }

    // The pill is only as wide as the strip on a side edge, so the label is dropped.
    Column {
        id: compactColumn

        anchors.centerIn: parent
        visible: root.isVertical
        spacing: Theme.spacingXS

        onImplicitHeightChanged: root.pushMeasuredLength()

        Loader {
            anchors.horizontalCenter: parent.horizontalCenter
            active: root.isVertical && root.leading !== null
            visible: active
            sourceComponent: root.leading
        }

        DIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.iconName !== ""
            name: root.iconName
            size: Theme.iconSizeSmall
            color: root.iconColor
        }

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.value !== ""
            text: root.value
            color: Theme.surfaceTextSecondary
            font.pixelSize: Theme.fontSizeSmall
        }
    }
}
