import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Plugins

DashCardComponent {
    id: root

    readonly property int count: pluginData.count ?? 0

    clickable: true

    function handleKeyEvent(event) {
        switch (event.key) {
        case Qt.Key_Left:
            setData("count", Math.max(0, count - 1));
            return true;
        case Qt.Key_Right:
            setData("count", count + 1);
            return true;
        }
        return false;
    }

    Row {
        anchors.centerIn: parent
        spacing: Theme.spacingM

        DIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: "counter_1"
            size: Theme.iconSizeLarge
            color: root.accentColor
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: root.count
            font.pixelSize: Theme.fontSizeXXLarge
            font.weight: Theme.fontWeightMedium
            color: root.contentColor
        }
    }
}
