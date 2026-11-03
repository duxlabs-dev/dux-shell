import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Plugins
import qs.Modules.DDash
import qs.Modules.DDash.Overview

DashTabComponent {
    id: root

    readonly property int count: pluginData.count ?? 0
    widgetGrid: grid
    focusTarget: grid.focusTarget
    implicitHeight: grid.implicitHeight

    function bump(delta) {
        setData("count", Math.max(0, count + delta));
    }

    function handleKeyEvent(event) {
        if (grid.handleKeyEvent(event))
            return true;
        if (editMode)
            return false;
        switch (event.key) {
        case Qt.Key_Plus:
        case Qt.Key_Equal:
            bump(1);
            return true;
        case Qt.Key_Minus:
            bump(-1);
            return true;
        }
        return false;
    }

    DashWidgetGrid {
        id: grid
        width: parent.width
        entryId: root.entryId
        live: root.live
        editMode: root.editMode
        definitions: [
            {
                id: "counter",
                text: I18n.trFor("dashCounterExample", "Counter"),
                icon: "counter_1",
                component: counterWidget,
                w: 2,
                h: 2,
                minW: 2,
                minH: 2,
                maxW: 4,
                maxH: 3,
                options: [DashRegistry.toneOption("primary")]
            },
            {
                id: "reset",
                text: I18n.trFor("dashCounterExample", "Reset"),
                icon: "restart_alt",
                component: resetWidget,
                w: 2,
                h: 1,
                minW: 1,
                minH: 1,
                maxW: 4,
                maxH: 1,
                enabled: false
            }
        ]
    }

    Component {
        id: counterWidget

        Card {
            id: counterCard

            property var widgetOptions: ({})

            tone: widgetOptions.tone ?? "primary"

            Column {
                anchors.centerIn: parent
                spacing: Theme.spacingL

                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.count
                    font.pixelSize: Theme.fontSizeDisplay
                    font.weight: Theme.fontWeightMedium
                    color: counterCard.contentColor
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Theme.spacingS

                    DActionButton {
                        buttonSize: Theme.buttonHeightM
                        iconSize: Theme.iconSize
                        iconName: "remove"
                        iconColor: counterCard.contentColor
                        Accessible.name: I18n.trFor("dashCounterExample", "Decrease")
                        onClicked: root.bump(-1)
                    }

                    DActionButton {
                        buttonSize: Theme.buttonHeightM
                        iconSize: Theme.iconSize
                        iconName: "add"
                        iconColor: counterCard.onAccentColor
                        backgroundColor: counterCard.accentColor
                        Accessible.name: I18n.trFor("dashCounterExample", "Increase")
                        onClicked: root.bump(1)
                    }
                }
            }
        }
    }

    Component {
        id: resetWidget

        Card {
            DButton {
                anchors.centerIn: parent
                text: I18n.trFor("dashCounterExample", "Reset")
                iconName: "restart_alt"
                enabled: root.count > 0
                onClicked: root.setData("count", 0)
            }
        }
    }
}
