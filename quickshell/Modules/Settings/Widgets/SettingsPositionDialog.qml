import QtQuick
import qs.Common
import qs.DCommon.Widgets

// Parent to the page dialog host so it covers the content column; focus returns to the opener on close
Loader {
    id: root

    property string title: I18n.tr("Position")
    property string supportingText: ""
    property int selected: SettingsData.Position.BottomCenter
    property bool resettable: false
    readonly property bool opened: _opened

    property bool _opened: false
    property Item _returnFocusTo: null

    signal picked(int position)
    signal resetRequested

    anchors.fill: parent
    z: 1000
    active: false
    onLoaded: item.show()

    function show() {
        if (_opened)
            return;
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
        maximumWidth: SettingsMetrics.positionPickerMaxWidth + padding * 2
        surfaceColor: Theme.hostSurface
        title: root.title
        supportingText: root.supportingText
        acceptEnabled: false
        onRejected: root.hide()
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
                text: I18n.tr("Reset")
                variant: "text"
                visible: root.resettable
                onClicked: {
                    root.resetRequested();
                    root.hide();
                }
            },
            DButton {
                text: I18n.tr("Cancel")
                variant: "text"
                onClicked: dialog.rejected()
            }
        ]

        SettingsScreenPositionPicker {
            selected: root.selected
            onPicked: position => {
                root.picked(position);
                root.hide();
            }
        }
    }
}
