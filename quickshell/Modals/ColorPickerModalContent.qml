import QtQuick
import qs.Modules.ColorPicker

ColorPickerContent {
    required property var modal

    anchors.fill: parent
    pickerTitle: modal.pickerTitle
    initialColor: modal.selectedColor
    showSaveButton: typeof modal.onColorSelectedCallback === "function"
    onColorSelected: color => modal.colorSelected(color)
    onCloseRequested: modal.hide()
    onHideRequested: {
        modal.hideInstant();
        startScreenPick();
    }
    onShowRequested: modal.show(modal.useOverlayLayer)
}
