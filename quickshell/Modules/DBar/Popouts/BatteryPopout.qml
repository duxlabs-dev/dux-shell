import QtQuick
import QtQuick.Window
import qs.Common
import qs.Widgets

DPopout {
    id: root

    layerNamespace: "dms:battery"
    property var triggerScreen: null

    popupWidth: Math.min(Theme.iconButtonSize * 11, (screen?.width ?? Screen.width) - Theme.spacingL * 2)
    popupHeight: Math.min(contentLoader.item?.implicitHeight ?? 0, Math.max(0, (screen?.height ?? Screen.height) - Theme.barHeight - Theme.spacingXL * 2))
    triggerWidth: 70
    positioning: ""
    screen: triggerScreen
    contentHandlesKeys: true

    onBackgroundClicked: close()

    content: Component {
        BatteryPopoutContent {
            active: root.shouldBeVisible
            onDismissRequested: root.close()
        }
    }
}
