import QtQuick
import qs.Services

LabelOSD {
    osdKind: "keyboardLayout"
    iconName: "keyboard"
    label: KeyboardLayoutService.currentLayout
    autoShowOnLabelChange: true
    labelReady: KeyboardLayoutService.layoutKnown

    Component.onCompleted: KeyboardLayoutService.consumers++
    Component.onDestruction: KeyboardLayoutService.consumers--
}
