import QtQuick
import qs.Services

LabelOSD {
    osdKind: "inputMethod"
    iconName: "language"
    label: Fcitx5Service.currentIMLabel
    autoShowOnLabelChange: true
    labelReady: label !== ""

    Component.onCompleted: Fcitx5Service.consumers++
    Component.onDestruction: Fcitx5Service.consumers--
}
