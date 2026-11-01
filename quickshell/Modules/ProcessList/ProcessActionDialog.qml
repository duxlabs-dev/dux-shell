import QtQuick
import qs.Common
import qs.DCommon.Widgets

// Confirms a process action. Parent it to an item that covers the window; focus returns to the opener on close.
Loader {
    id: root

    property var process: null
    property string action: "quit"
    property bool warn: false
    readonly property bool opened: _opened
    readonly property bool offerRestart: warn && ProcessActions.canRestart(process)

    property bool _opened: false
    property Item _returnFocusTo: null

    signal chosen(string action, var process)

    anchors.fill: parent
    z: 1000
    active: false
    onLoaded: item.show()

    function open(targetProcess, targetAction, critical) {
        process = targetProcess;
        action = targetAction;
        warn = critical;
        _returnFocusTo = Window.window?.activeFocusItem ?? null;
        _opened = true;
        if (item)
            item.show();
        else
            active = true;
    }

    function close() {
        if (!_opened)
            return;
        _opened = false;
        if (item)
            item.opened = false;
        const focusItem = _returnFocusTo;
        _returnFocusTo = null;
        if (focusItem?.visible && focusItem.enabled)
            focusItem.forceActiveFocus(Qt.OtherFocusReason);
    }

    function choose(chosenAction) {
        const target = process;
        close();
        chosen(chosenAction, target);
    }

    sourceComponent: DDialog {
        id: dialog

        embedded: false
        opened: false
        surfaceColor: Theme.hostSurface
        title: ProcessActions.title(root.action, root.process)
        supportingText: (root.process?.command ?? "") + " (" + I18n.tr("PID %1", "%1 is a process id").arg(root.process?.pid ?? 0) + ")"
        onAccepted: root.choose(root.offerRestart ? "restart" : root.action)
        onRejected: root.close()
        onActiveChanged: {
            if (!active && !root._opened)
                root.active = false;
        }

        function show() {
            opened = true;
            forceActiveFocus();
        }

        actions: [
            DButton {
                text: I18n.tr("Cancel")
                backgroundColor: "transparent"
                textColor: Theme.primary
                onClicked: dialog.rejected()
            },
            DButton {
                text: ProcessActions.title(root.action, root.process)
                backgroundColor: root.offerRestart ? "transparent" : Theme.errorContainer
                textColor: root.offerRestart ? Theme.error : Theme.onErrorContainer
                onClicked: root.choose(root.action)
            },
            DButton {
                visible: root.offerRestart
                text: ProcessActions.title("restart", root.process)
                iconName: "restart_alt"
                onClicked: root.choose("restart")
            }
        ]

        StyledText {
            visible: root.warn
            width: parent.width
            text: I18n.tr("%1 keeps your desktop running. Ending it will likely break your session. If it misbehaves, restarting it is the safer fix.", "warning before ending the compositor, systemd, the session bus or the shell; %1 is the process name").arg(root.process?.command ?? "")
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.error
            wrapMode: Text.Wrap
        }
    }
}
