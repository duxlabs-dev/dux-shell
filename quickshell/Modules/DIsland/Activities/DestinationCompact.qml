pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Common
import qs.DCommon.Widgets
import "../../../Common/IslandKit.js" as Kit

Item {
    id: root

    required property var controller
    required property string activityId
    required property string label
    property string value: ""
    property string iconName: ""
    property color iconColor: Theme.primary
    property Component leading: null
    // A long label ends in "…"; a file name is cut in the middle, so its extension stays.
    property int labelElide: Text.ElideRight

    readonly property bool isVertical: root.controller.isVertical

    // The face never outgrows the widest compact face: the label gives way.
    readonly property real labelRoom: root.controller.mediaCompactMaxLength - root.controller.destinationCompactEndPad * 2 - (rowLeading.visible ? rowLeading.width + Theme.spacingS : 0) - (rowIcon.visible ? rowIcon.width + Theme.spacingS : 0) - (rowValue.visible ? rowValue.implicitWidth + Theme.spacingS : 0)

    // Glyphs carry their own air (a mouse icon, a "!"): the row is centred on its ink, not on its boxes.
    // Measured 8x up: the tight box snaps to whole pixels, an error as large as the air itself.
    readonly property int inkScale: 8

    TextMetrics {
        id: iconInk

        // The axes rowIcon draws with (DIcon's optical size is 24): they move the glyph's bearings.
        font.family: Fonts.icons
        font.pixelSize: Theme.iconSizeSmall * root.inkScale
        font.hintingPreference: Font.PreferNoHinting
        font.variableAxes: {
            "FILL": rowIcon.fill,
            "GRAD": rowIcon.grade,
            "opsz": 24,
            "wght": rowIcon.weight
        }
        text: root.iconName
    }

    TextMetrics {
        id: firstInk

        font.family: rowLabel.font.family
        font.weight: rowLabel.font.weight
        font.pixelSize: rowLabel.font.pixelSize * root.inkScale
        text: root.label.charAt(0)
    }

    TextMetrics {
        id: lastInk

        font.family: rowValue.visible ? rowValue.font.family : rowLabel.font.family
        font.weight: rowValue.visible ? rowValue.font.weight : rowLabel.font.weight
        font.pixelSize: (rowValue.visible ? rowValue.font.pixelSize : rowLabel.font.pixelSize) * root.inkScale
        text: rowValue.visible ? root.value.slice(-1) : rowLabel.truncated && root.labelElide === Text.ElideRight ? "…" : root.label.slice(-1)
    }

    readonly property real leadAir: rowLeading.visible ? 0 : rowIcon.visible ? Kit.boxBearing(rowIcon.width, iconInk.advanceWidth / root.inkScale, iconInk.tightBoundingRect.x / root.inkScale) : firstInk.tightBoundingRect.x / root.inkScale
    readonly property real trailAir: (lastInk.advanceWidth - lastInk.tightBoundingRect.x - lastInk.tightBoundingRect.width) / root.inkScale

    function pushMeasuredLength() {
        root.controller.setDestinationContentLength(root.activityId, root.isVertical ? compactColumn.implicitHeight : compactRow.implicitWidth);
    }

    Component.onCompleted: root.pushMeasuredLength()
    onIsVerticalChanged: root.pushMeasuredLength()

    Row {
        id: compactRow

        anchors.verticalCenter: parent.verticalCenter
        x: Kit.inkCentredX(root.width, width, root.leadAir, root.trailAir)
        visible: !root.isVertical
        spacing: Theme.spacingS

        onImplicitWidthChanged: root.pushMeasuredLength()

        Loader {
            id: rowLeading

            anchors.verticalCenter: parent.verticalCenter
            active: !root.isVertical && root.leading !== null
            visible: active
            sourceComponent: root.leading
        }

        DIcon {
            id: rowIcon

            anchors.verticalCenter: parent.verticalCenter
            visible: root.iconName !== ""
            name: root.iconName
            size: Theme.iconSizeSmall
            color: root.iconColor
        }

        StyledText {
            id: rowLabel

            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, Math.max(0, root.labelRoom))
            text: root.label
            color: Theme.surfaceText
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Theme.fontWeightMedium
            wrapMode: Text.NoWrap
            elide: root.labelElide
        }

        StyledText {
            id: rowValue

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
