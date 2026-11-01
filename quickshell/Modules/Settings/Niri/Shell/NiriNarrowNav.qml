import QtQuick
import qs.Common

Item {
    id: root

    property var sections: []
    property string current: ""
    property string currentText: ""
    property var counts: ({})
    property bool open: false

    signal picked(string id)
    signal toggled

    height: visible ? narrowNav.height + Theme.spacingS * 2 : 0

    Column {
        id: narrowNav
        y: Theme.spacingS
        width: parent.width
        spacing: Theme.spacingXXS

        NiriNavItem {
            width: parent.width
            iconName: "menu"
            text: root.currentText
            trailingIcon: root.open ? "expand_less" : "expand_more"
            restColor: Theme.surfaceContainerHighest
            Accessible.name: I18n.tr("Sections", "niri page narrow menu button")
            onClicked: root.toggled()
        }

        NiriNavList {
            width: parent.width
            visible: root.open
            sections: root.open ? root.sections : []
            current: root.current
            counts: root.counts
            onPicked: id => root.picked(id)
        }
    }

    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: Theme.outlineWidth
        color: Theme.outlineVariant
    }
}
