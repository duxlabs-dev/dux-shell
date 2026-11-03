import QtQuick
import qs.Common
import qs.Modals.Common
import qs.DCommon.Widgets

DModal {
    id: root

    layerNamespace: "dms:input-modal"
    keepPopoutsOpen: true

    property string inputTitle: ""
    property string inputMessage: ""
    property string inputPlaceholder: ""
    property string inputText: ""
    property string confirmButtonText: I18n.tr("Confirm")
    property string cancelButtonText: I18n.tr("Cancel")
    property color confirmButtonColor: Theme.primary
    property var onConfirm: function (text) {}
    property var onCancel: function () {}

    function show(title, message, onConfirmCallback, onCancelCallback) {
        inputTitle = title || "";
        inputMessage = message || "";
        inputPlaceholder = "";
        inputText = "";
        confirmButtonText = I18n.tr("Confirm");
        cancelButtonText = I18n.tr("Cancel");
        confirmButtonColor = Theme.primary;
        onConfirm = onConfirmCallback || (text => {});
        onCancel = onCancelCallback || (() => {});
        open();
    }

    function showWithOptions(options) {
        inputTitle = options.title || "";
        inputMessage = options.message || "";
        inputPlaceholder = options.placeholder || "";
        inputText = options.initialText || "";
        confirmButtonText = options.confirmText || I18n.tr("Confirm");
        cancelButtonText = options.cancelText || I18n.tr("Cancel");
        confirmButtonColor = options.confirmColor || Theme.primary;
        onConfirm = options.onConfirm || (text => {});
        onCancel = options.onCancel || (() => {});
        open();
    }

    function confirmAndClose() {
        const text = inputText;
        close();
        if (onConfirm) {
            onConfirm(text);
        }
    }

    function cancelAndClose() {
        close();
        if (onCancel) {
            onCancel();
        }
    }

    shouldBeVisible: false
    allowStacking: true
    modalWidth: Math.min(Theme.dialogMaxWidth, screenWidth - Theme.spacingXL * 2)
    modalHeight: contentLoader.item ? Math.min(contentLoader.item.implicitHeight, screenHeight - Theme.spacingXL * 2) : 200
    enableShadow: true
    shouldHaveFocus: true
    onBackgroundClicked: cancelAndClose()
    onOpened: {
        Qt.callLater(function () {
            if (contentLoader.item && contentLoader.item.textInputRef) {
                contentLoader.item.textInputRef.forceActiveFocus();
            }
        });
    }

    content: DDialog {
        id: inputDialog
        property alias textInputRef: textInput

        title: root.inputTitle
        supportingText: root.inputMessage
        onAccepted: root.confirmAndClose()
        onRejected: root.cancelAndClose()

        DTextField {
            id: textInput

            width: parent.width
            outlined: true
            controlHeight: Theme.fieldHeightLarge
            labelText: root.inputPlaceholder || root.inputTitle
            leftIconName: "edit"
            text: root.inputText
            onTextEdited: root.inputText = text
            onAccepted: root.confirmAndClose()
        }

        actions: [
            DButton {
                maximumWidth: inputDialog.actionWidth
                wrapText: true
                text: root.cancelButtonText
                backgroundColor: "transparent"
                textColor: Theme.primary
                onClicked: root.cancelAndClose()
            },
            DButton {
                maximumWidth: inputDialog.actionWidth
                wrapText: true
                text: root.confirmButtonText
                backgroundColor: root.confirmButtonColor
                onClicked: root.confirmAndClose()
            }
        ]
    }
}
