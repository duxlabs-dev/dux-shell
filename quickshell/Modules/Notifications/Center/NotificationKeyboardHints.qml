import QtQuick
import qs.Common
import qs.Modules.Notifications
import qs.Widgets

Rectangle {
    id: root

    property bool showHints: false
    property bool historyTab: false

    implicitHeight: hintsLoader.height + Theme.spacingM * 2
    radius: NotificationMetrics.menuRadius
    color: Theme.foregroundColor(Theme.cardSurface, Theme.isFloatingWindow(root))
    border.color: Theme.primary
    border.width: Theme.outlineWidthFocused
    opacity: showHints ? 1 : 0
    visible: opacity > 0
    z: 100

    Loader {
        id: hintsLoader

        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.spacingM
        active: root.visible

        sourceComponent: DKeyHints {
            hints: {
                const listHints = root.historyTab ? [] : [
                    {
                        keys: ["Space"],
                        label: I18n.tr("Expand")
                    },
                    {
                        keys: ["Return"],
                        label: I18n.tr("Open")
                    },
                    {
                        keys: ["E"],
                        label: I18n.tr("Text")
                    },
                    {
                        keys: ["1-9"],
                        label: I18n.tr("Actions")
                    }
                ];
                return [
                    {
                        keys: ["Up", "Down"],
                        label: I18n.tr("Navigate", "verb, keyboard shortcut hint for arrow keys")
                    }
                ].concat(listHints, [
                    {
                        keys: ["Delete"],
                        label: I18n.tr("Clear")
                    },
                    {
                        keys: ["Shift+Delete"],
                        label: I18n.tr("Clear All")
                    },
                    {
                        keys: ["F10"],
                        label: I18n.tr("Help")
                    },
                    {
                        keys: ["Escape"],
                        label: I18n.tr("Close")
                    }
                ]);
            }
        }
    }

    Behavior on opacity {
        NumberAnimation {
            duration: Theme.shortDuration
            easing.type: Theme.standardEasing
        }
    }
}
