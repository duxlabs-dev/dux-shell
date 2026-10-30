import QtQuick
import Quickshell.Io
import qs.Common
import qs.Modals.Common
import qs.Modules.ColorPicker

DModal {
    id: root

    layerNamespace: "dms:color-picker"

    property string pickerTitle: I18n.tr("Choose color", "color picker title")
    property color selectedColor: SessionData.recentColors.length > 0 ? SessionData.recentColors[0] : Theme.primary
    property var onColorSelectedCallback: null

    signal colorSelected(color selectedColor)

    objectName: "colorPickerModal"
    modalWidth: Theme.dialogMaxWidth
    modalHeight: Math.min(screenHeight - Theme.spacingXL * 2, contentLoader?.item?.implicitHeight ?? 0)
    keepContentLoaded: true
    allowStacking: true

    function show(overlayLayer = false) {
        useOverlayLayer = overlayLayer;
        open();
        contentLoader?.item?.setColor(selectedColor);
    }

    function hide() {
        close();
    }

    function hideInstant() {
        instantClose();
    }

    function toggle() {
        shouldBeVisible ? hide() : show();
    }

    function toggleInstant() {
        shouldBeVisible ? hideInstant() : show();
    }

    // show() applies selectedColor on open. While the picker is open, a change to the
    // recent colors (which selectedColor follows) must not reset the color being edited.
    onSelectedColorChanged: {
        if (!shouldBeVisible)
            contentLoader?.item?.setColor(selectedColor);
    }
    onBackgroundClicked: hide()
    onOpened: Qt.callLater(() => contentLoader?.item?.focusInitial())
    onDialogClosed: {
        if (contentLoader?.item?.pickingFromScreen)
            return;
        onColorSelectedCallback = null;
        useOverlayLayer = false;
    }
    onColorSelected: color => {
        if (typeof onColorSelectedCallback === "function")
            onColorSelectedCallback(color);
    }

    IpcHandler {
        function open(): string {
            root.show();
            return "COLOR_PICKER_MODAL_OPEN_SUCCESS";
        }

        function openColor(color: string): string {
            const text = color.trim();
            try {
                root.selectedColor = Qt.color(/^[0-9a-f]{6}([0-9a-f]{2})?$/i.test(text) ? "#" + text : text);
            } catch (error) {
                return "COLOR_PICKER_INVALID_COLOR";
            }
            return open();
        }

        function close(): string {
            root.hide();
            return "COLOR_PICKER_MODAL_CLOSE_SUCCESS";
        }

        function closeInstant(): string {
            root.hideInstant();
            return "COLOR_PICKER_MODAL_CLOSE_INSTANT_SUCCESS";
        }

        function toggle(): string {
            root.toggle();
            return "COLOR_PICKER_MODAL_TOGGLE_SUCCESS";
        }

        function toggleInstant(): string {
            root.toggleInstant();
            return "COLOR_PICKER_MODAL_TOGGLE_INSTANT_SUCCESS";
        }

        target: "color-picker"
    }

    content: Component {
        ColorPickerContent {
            anchors.fill: parent
            pickerTitle: root.pickerTitle
            initialColor: root.selectedColor
            showSaveButton: typeof root.onColorSelectedCallback === "function"
            onColorSelected: color => root.colorSelected(color)
            onCloseRequested: root.hide()
            onHideRequested: {
                root.hideInstant();
                startScreenPick();
            }
            onShowRequested: root.show(root.useOverlayLayer)
        }
    }
}
