import QtQuick
import QtQuick.Window
import qs.Common

Item {
    id: root

    property string confirmTitle: ""
    property string confirmMessage: ""
    property string reviewUrl: ""
    property Item returnFocusItem: null
    property string confirmButtonText: I18n.tr("Confirm")
    property string cancelButtonText: I18n.tr("Cancel")
    property color confirmButtonColor: Theme.primary
    property var onConfirm: function () {}
    property var onCancel: function () {}
    property real backgroundOpacity: Theme.scrimAlpha

    signal dialogClosed

    function show(title, message, onConfirmCallback, onCancelCallback) {
        showWithOptions({
            "title": title,
            "message": message,
            "onConfirm": onConfirmCallback,
            "onCancel": onCancelCallback
        });
    }

    function showWithOptions(options) {
        returnFocusItem = root.Window.window?.activeFocusItem ?? null;
        confirmTitle = options.title || "";
        confirmMessage = options.message || "";
        reviewUrl = options.reviewUrl || "";
        confirmButtonText = options.confirmText || I18n.tr("Confirm");
        cancelButtonText = options.cancelText || I18n.tr("Cancel");
        confirmButtonColor = options.confirmColor || Theme.primary;
        onConfirm = options.onConfirm || (() => {});
        onCancel = options.onCancel || (() => {});
        visible = true;
        dialogContent.keyboardNavigation = false;
        dialogContent.selectedButton = options.confirmByDefault === true ? 1 : 0;
        focusDialog();
    }

    function focusDialog() {
        if (!visible)
            return;
        overlayFocusScope.forceActiveFocus();
    }

    function close() {
        visible = false;
        const focusItem = returnFocusItem;
        returnFocusItem = null;
        if (focusItem?.visible && focusItem.enabled)
            focusItem.forceActiveFocus(Qt.OtherFocusReason);
        dialogClosed();
    }

    function _activate(button) {
        const cancelCallback = onCancel;
        const confirmCallback = onConfirm;
        close();
        if (button === 0) {
            cancelCallback && cancelCallback();
            return;
        }
        confirmCallback && confirmCallback();
    }

    anchors.fill: parent
    visible: false
    z: 100

    Connections {
        target: root.Window.window
        enabled: root.visible

        function onActiveFocusItemChanged() {
            if (!overlayFocusScope.activeFocus)
                Qt.callLater(root.focusDialog);
        }
    }

    FocusScope {
        id: overlayFocusScope

        anchors.fill: parent
        focus: root.visible

        Keys.onPressed: event => dialogContent.handleKey(event)

        Rectangle {
            anchors.fill: parent
            color: Theme.backdropColor
            opacity: root.backgroundOpacity
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root._activate(0)
        }

        Rectangle {
            width: Math.min(Theme.smallBreakpoint, parent.width - Theme.spacingL * 2)
            height: dialogContent.implicitHeight + Theme.spacingL * 2
            anchors.centerIn: parent
            radius: Theme.windowRadius
            color: Theme.foregroundColor(Theme.cardSurface, Theme.isFloatingWindow(root))
            border.color: Theme.outlineMedium
            border.width: Theme.layerOutlineWidth

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
            }

            ConfirmDialogContent {
                id: dialogContent

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: Theme.spacingL
                anchors.rightMargin: Theme.spacingL
                anchors.topMargin: Theme.spacingL
                confirmTitle: root.confirmTitle
                confirmMessage: root.confirmMessage
                reviewUrl: root.reviewUrl
                confirmButtonText: root.confirmButtonText
                cancelButtonText: root.cancelButtonText
                confirmButtonColor: root.confirmButtonColor
                onButtonActivated: button => root._activate(button)
                onCancelled: root._activate(0)
            }
        }
    }
}
