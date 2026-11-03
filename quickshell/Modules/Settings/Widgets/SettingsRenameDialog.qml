import QtQuick
import qs.Common
import qs.DCommon.Widgets

// Parent to the modal focus scope so it covers the window; focus returns to the opener on close
Loader {
    id: root

    property string title: I18n.tr("Rename")
    property string supportingText: ""
    property string labelText: I18n.tr("Name")
    property string leftIconName: "edit"
    property Component aboveField: null
    property Component belowField: null
    property string text: ""
    readonly property bool opened: _opened

    property bool _opened: false
    property Item _returnFocusTo: null

    signal accepted(string name)

    anchors.fill: parent
    z: 1000
    active: false
    onLoaded: item.show()

    function show(initialText) {
        if (_opened)
            return;
        text = initialText ?? "";
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
        if (item)
            item.opened = false;
        const focusItem = _returnFocusTo;
        _returnFocusTo = null;
        if (focusItem?.visible && focusItem.enabled)
            focusItem.forceActiveFocus(Qt.OtherFocusReason);
    }

    sourceComponent: DDialog {
        id: dialog

        embedded: nativeWindow
        opened: nativeWindow
        maximumWidth: SettingsMetrics.formDialogWidth
        surfaceColor: Theme.hostSurface
        title: root.title
        supportingText: root.supportingText
        acceptEnabled: root.text.trim() !== ""
        onAccepted: root.accepted(root.text.trim())
        onRejected: root.hide()
        onActiveChanged: {
            if (!active && !root._opened)
                root.active = false;
        }

        function show() {
            nameInput.text = root.text;
            opened = true;
            forceActiveFocus();
            nameInput.forceActiveFocus();
            nameInput.selectAll();
        }

        actions: [
            DButton {
                text: I18n.tr("Cancel")
                backgroundColor: "transparent"
                textColor: Theme.primary
                onClicked: dialog.rejected()
            },
            DButton {
                text: I18n.tr("Save")
                iconName: "check"
                enabled: dialog.acceptEnabled
                onClicked: dialog.accepted()
            }
        ]

        Loader {
            width: parent.width
            visible: status === Loader.Ready && item.visible
            sourceComponent: root.aboveField
        }

        DTextField {
            id: nameInput
            outlined: true
            leftIconName: root.leftIconName
            labelText: root.labelText
            width: parent.width
            showClearButton: true
            onTextChanged: root.text = text
        }

        Loader {
            width: parent.width
            visible: status === Loader.Ready && item.visible
            sourceComponent: root.belowField
        }
    }
}
