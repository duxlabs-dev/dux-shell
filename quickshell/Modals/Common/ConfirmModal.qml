import QtQuick
import qs.Common
import qs.Modals.Common

DModal {
    id: root

    layerNamespace: "dms:confirm-modal"
    keepPopoutsOpen: true

    property string confirmTitle: ""
    property string confirmMessage: ""
    property string confirmButtonText: I18n.tr("Confirm", "verb, default confirm button in dialogs")
    property string cancelButtonText: I18n.tr("Cancel")
    property color confirmButtonColor: Theme.primary
    property int defaultButton: 0
    property var onConfirm: function () {}
    property var onCancel: function () {}

    function show(title, message, onConfirmCallback, onCancelCallback) {
        showWithOptions({
            "title": title,
            "message": message,
            "onConfirm": onConfirmCallback,
            "onCancel": onCancelCallback
        });
    }

    function showWithOptions(options) {
        confirmTitle = options.title || "";
        confirmMessage = options.message || "";
        confirmButtonText = options.confirmText || I18n.tr("Confirm");
        cancelButtonText = options.cancelText || I18n.tr("Cancel");
        confirmButtonColor = options.confirmColor || Theme.primary;
        defaultButton = options.defaultButton || 0;
        onConfirm = options.onConfirm || (() => {});
        onCancel = options.onCancel || (() => {});
        open();
    }

    function _activate(button) {
        close();
        if (button === 0) {
            onCancel && onCancel();
            return;
        }
        onConfirm && onConfirm();
    }

    shouldBeVisible: false
    allowStacking: true
    modalWidth: 350
    modalHeight: contentLoader.item ? contentLoader.item.implicitHeight + Theme.spacingM * 2 : 160
    enableShadow: true
    shouldHaveFocus: true
    onBackgroundClicked: _activate(0)
    onOpened: {
        contentLoader?.item?.dialog?.reset();
        // reset() selects Cancel so a stray Enter never confirms; only a caller that asks for it moves the selection.
        if (root.defaultButton !== 0 && contentLoader?.item?.dialog)
            contentLoader.item.dialog.selectedButton = root.defaultButton;
        Qt.callLater(function () {
            modalFocusScope.forceActiveFocus();
            modalFocusScope.focus = true;
            shouldHaveFocus = true;
        });
    }
    modalFocusScope.Keys.onPressed: function (event) {
        contentLoader?.item?.dialog?.handleKey(event);
    }

    content: Component {
        Item {
            anchors.fill: parent
            implicitHeight: dialogContent.implicitHeight

            property alias dialog: dialogContent

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
                confirmButtonText: root.confirmButtonText
                cancelButtonText: root.cancelButtonText
                confirmButtonColor: root.confirmButtonColor
                onButtonActivated: button => root._activate(button)
                onCancelled: root._activate(0)
            }
        }
    }
}
