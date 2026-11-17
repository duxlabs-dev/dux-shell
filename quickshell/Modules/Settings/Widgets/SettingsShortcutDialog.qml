pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.DCommon.Widgets
import qs.Widgets

// Parent to the modal focus scope so it covers the window; focus returns to the opener on close
Loader {
    id: root

    property string title: I18n.tr("Edit shortcut", "keybind editor dialog title")
    property string supportingText: ""
    property string acceptText: I18n.tr("Save")
    property string key: ""
    property var conflicts: []
    property bool embedded: false
    readonly property bool opened: _opened
    readonly property bool changed: key !== _initialKey

    property string _initialKey: ""
    property bool _opened: false
    property Item _returnFocusTo: null

    signal accepted(string key)

    anchors.fill: parent
    z: 1000
    visible: !embedded || _opened
    active: false
    onLoaded: item.show()

    function show(initialKey) {
        if (_opened)
            return;
        _initialKey = initialKey ?? "";
        key = _initialKey;
        _returnFocusTo = Window.window?.activeFocusItem ?? null;
        _opened = true;
        if (item)
            item.show();
        else
            active = true;
    }

    function hide() {
        if (!_opened)
            return;
        _opened = false;
        if (embedded)
            Qt.callLater(unloadClosed);
        else if (item)
            item.opened = false;
        const focusItem = _returnFocusTo;
        _returnFocusTo = null;
        if (focusItem?.visible && focusItem.enabled)
            focusItem.forceActiveFocus(Qt.OtherFocusReason);
    }

    // hide() can run under one of the dialog's own handlers, so unload a turn later.
    function unloadClosed() {
        if (!_opened)
            active = false;
    }

    sourceComponent: DDialog {
        id: dialog

        embedded: root.embedded
        opened: root.embedded
        maximumWidth: SettingsMetrics.formDialogWidth
        surfaceColor: Theme.hostSurface
        title: root.title
        supportingText: root.supportingText
        acceptEnabled: root.changed
        onAccepted: root.accepted(root.key)
        onRejected: root.hide()
        onActiveChanged: {
            if (!active && !root._opened)
                root.active = false;
        }

        function show() {
            opened = true;
            forceActiveFocus();
            keyCapture.startRecording();
        }

        ShortcutInhibitor {
            window: root.QsWindow.window
            enabled: keyCapture.recording
        }

        actions: [
            DButton {
                text: I18n.tr("Clear")
                variant: "text"
                visible: root.key !== ""
                onClicked: root.key = ""
            },
            DButton {
                text: I18n.tr("Cancel")
                variant: "text"
                onClicked: root.hide()
            },
            DButton {
                text: root.acceptText
                iconName: "check"
                enabled: root.changed
                onClicked: root.accepted(root.key)
            }
        ]

        KeyCaptureField {
            id: keyCapture
            width: parent.width
            key: root.key
            keepsFormKeys: true
            onCaptured: key => root.key = key
        }

        Row {
            width: parent.width
            spacing: Theme.spacingS
            visible: root.conflicts.length > 0

            DIcon {
                id: conflictIcon
                name: "warning"
                size: Theme.iconSizeSmall
                color: Theme.primary
            }

            StyledText {
                width: parent.width - conflictIcon.width - parent.spacing
                text: I18n.tr("Conflicts with: %1", "keybind warning, %1 is a list of conflicting bind descriptions").arg(root.conflicts.map(bind => bind.desc).join(", "))
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.primary
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignLeft
            }
        }
    }
}
