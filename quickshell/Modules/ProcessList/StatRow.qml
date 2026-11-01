import QtQuick
import qs.Common
import qs.DCommon.Widgets

Item {
    id: root

    property string label: ""
    property string value: ""
    property string tooltip: ""
    property bool loading: false

    height: Theme.iconButtonSize

    StyledText {
        id: labelText
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, root.width / 2)
        text: root.label
        font.pixelSize: Theme.fontSizeMedium
        color: Theme.surfaceVariantText
        wrapMode: Text.NoWrap
        elide: Text.ElideRight
    }

    Loader {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        active: root.loading
        sourceComponent: DSpinner {
            size: Theme.iconSizeSmall
        }
    }

    NumericText {
        visible: !root.loading
        anchors.left: labelText.right
        anchors.leftMargin: Theme.spacingM
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: root.value || "—"
        font.pixelSize: Theme.fontSizeMedium
        color: Theme.surfaceText
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideRight
    }

    MouseArea {
        id: rowHover
        anchors.fill: parent
        enabled: root.tooltip !== ""
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onContainsMouseChanged: {
            if (containsMouse) {
                tip.text = root.tooltip;
                tip.schedule();
            } else {
                tip.dismiss();
            }
        }
    }

    // The tooltip is built on first hover; rows are rebuilt often and most are never hovered.
    DTooltipHost {
        id: tip
        target: root
        hoverArea: rowHover
        multiline: true
    }
}
