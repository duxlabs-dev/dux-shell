import QtQuick
import qs.Common
import qs.Widgets

Rectangle {
    id: keyboardHints

    property bool pasteAvailable: false
    property bool enterToPaste: false
    readonly property bool enterPastes: pasteAvailable && enterToPaste

    implicitHeight: hints.implicitHeight + Theme.spacingM * 2
    radius: Theme.cornerRadius
    color: Theme.floatingWindowNestedSurface
    border.color: Theme.primary
    border.width: 2
    opacity: visible ? 1 : 0
    z: 100

    DKeyHints {
        id: hints

        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.spacingM
        hints: {
            const pasteHints = keyboardHints.pasteAvailable ? [
                {
                    keys: keyboardHints.enterPastes ? ["Return"] : ["Shift+Return"],
                    label: I18n.tr("Paste")
                }
            ] : [];
            return [
                {
                    keys: ["Up", "Down"],
                    label: I18n.tr("Navigate", "verb, keyboard shortcut hint for arrow keys")
                },
                {
                    keys: keyboardHints.enterPastes ? ["Ctrl+C", "Shift+Return"] : ["Return", "Ctrl+C"],
                    label: I18n.tr("Copy")
                }
            ].concat(pasteHints, [
                {
                    keys: ["Ctrl+Space"],
                    label: I18n.tr("Preview", "verb, clipboard entry action button tooltip", true)
                },
                {
                    keys: ["Ctrl+E"],
                    label: I18n.tr("Edit")
                },
                {
                    keys: ["Ctrl+S"],
                    label: I18n.tr("Pin", "verb, keep an item pinned in place")
                },
                {
                    keys: ["Delete"],
                    label: I18n.tr("Delete")
                },
                {
                    keys: ["Shift+Delete"],
                    label: I18n.tr("Clear All")
                },
                {
                    keys: ["Ctrl+Tab"],
                    label: I18n.tr("Tabs")
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

    Behavior on opacity {
        NumberAnimation {
            duration: Theme.shortDuration
            easing.type: Theme.standardEasing
        }
    }
}
