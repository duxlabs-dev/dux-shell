import QtQuick
import qs.Common
import qs.Modules.Plugins
import qs.DCommon.Widgets

BasePill {
    id: root

    property bool isActive: false

    signal colorPickerRequested

    content: Component {
        Item {
            implicitWidth: icon.width
            implicitHeight: root.contentThickness

            DIcon {
                id: icon
                anchors.centerIn: parent
                name: "palette"
                size: Theme.barIconSize(root.barThickness, -4, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
                color: root.isActive ? Theme.primary : Theme.surfaceText
            }
        }
    }

    MouseArea {
        z: 1
        x: -root.leftMargin
        y: -root.topMargin
        width: root.width + root.leftMargin + root.rightMargin
        height: root.height + root.topMargin + root.bottomMargin
        cursorShape: Qt.PointingHandCursor
        onPressed: mouse => {
            root.triggerRipple(this, mouse.x, mouse.y);
            root.colorPickerRequested();
        }
    }
}
