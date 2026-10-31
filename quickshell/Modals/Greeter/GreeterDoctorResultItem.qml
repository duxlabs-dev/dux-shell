import QtQuick
import qs.Common
import qs.DCommon.Widgets

Rectangle {
    id: root

    property var resultData: null

    readonly property string status: resultData?.status || "ok"
    readonly property string statusIcon: {
        switch (status) {
        case "error":
            return "error";
        case "warn":
            return "warning";
        case "info":
            return "info";
        default:
            return "check_circle";
        }
    }
    readonly property color statusColor: {
        switch (status) {
        case "error":
            return Theme.error;
        case "warn":
            return Theme.warning;
        case "info":
            return Theme.secondary;
        default:
            return Theme.success;
        }
    }

    height: Math.round(Theme.fontSizeMedium * 3.4)
    radius: Theme.cornerRadius
    color: Theme.withAlpha(statusColor, 0.08)

    DIcon {
        id: statusIcon
        anchors.left: parent.left
        anchors.leftMargin: Theme.spacingM
        anchors.verticalCenter: parent.verticalCenter
        name: root.statusIcon
        size: Theme.iconSize - 4
        color: root.statusColor
    }

    Column {
        anchors.left: statusIcon.right
        anchors.leftMargin: Theme.spacingS
        anchors.right: categoryChip.visible ? categoryChip.left : (urlButton.visible ? urlButton.left : parent.right)
        anchors.rightMargin: Theme.spacingS
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        StyledText {
            width: parent.width
            text: root.resultData?.name || ""
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Theme.fontWeightMedium
            color: Theme.surfaceText
            elide: Text.ElideRight
        }

        StyledText {
            width: parent.width
            text: root.resultData?.message || ""
            font.pixelSize: Theme.fontSizeXSmall
            color: Theme.surfaceVariantText
            elide: Text.ElideRight
            visible: text.length > 0
        }
    }

    Rectangle {
        id: categoryChip
        anchors.right: urlButton.visible ? urlButton.left : parent.right
        anchors.rightMargin: urlButton.visible ? Theme.spacingXS : Theme.spacingM
        anchors.verticalCenter: parent.verticalCenter
        height: Math.round(Theme.fontSizeSmall * 1.67)
        width: categoryText.implicitWidth + Theme.spacingS
        radius: Theme.spacingXS
        color: Theme.chipSurface
        visible: !!(root.resultData?.category)

        StyledText {
            id: categoryText
            anchors.centerIn: parent
            text: root.resultData?.category || ""
            font.pixelSize: Theme.fontSizeXSmall
            font.weight: Theme.fontWeightMedium
            color: Theme.surfaceVariantText
        }
    }

    DActionButton {
        id: urlButton
        anchors.right: parent.right
        anchors.rightMargin: Theme.spacingM
        anchors.verticalCenter: parent.verticalCenter
        iconName: "open_in_new"
        iconSize: Theme.iconSize - 6
        buttonSize: 24
        visible: !!(root.resultData?.url)
        tooltipText: root.resultData?.url || ""
        onClicked: Qt.openUrlExternally(root.resultData.url)
    }
}
