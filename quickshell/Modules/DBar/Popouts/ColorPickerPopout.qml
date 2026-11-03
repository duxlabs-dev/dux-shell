import QtQuick
import qs.Common
import qs.Modules.ColorPicker
import qs.Widgets

DPopout {
    id: root

    layerNamespace: "dms:color-picker"
    popupWidth: Math.min(Theme.dialogMaxWidth, (screen?.width ?? Theme.dialogMaxWidth + Theme.spacingXL * 2) - Theme.spacingXL * 2)
    popupHeight: Math.min(contentLoader.item?.implicitHeight ?? Theme.fieldDefaultWidth * 3, (screen?.height ?? 1080) - Theme.barHeight - Theme.spacingXL * 2)
    contentHandlesKeys: true
    triggerWidth: Theme.iconButtonSize
    positioning: ""
    shouldBeVisible: false

    onBackgroundClicked: close()
    onOpened: focusTimer.restart()

    Timer {
        id: focusTimer
        interval: 0
        onTriggered: {
            if (root.shouldBeVisible)
                root.contentLoader.item?.focusInitial();
        }
    }

    content: Component {
        ColorPickerContent {
            anchors.fill: parent
            initialColor: SessionData.recentColors.length > 0 ? SessionData.recentColors[0] : Theme.primary
            onCloseRequested: root.close()
            onHideRequested: {
                root.instantClose();
                startScreenPick();
            }
            onShowRequested: root.open()
        }
    }
}
