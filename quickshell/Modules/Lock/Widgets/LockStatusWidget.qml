import QtQuick
import qs.Common
import qs.Modules.Lock

Item {
    id: root

    property var instanceData: null
    property var lockHost: null
    readonly property var cfg: instanceData?.config ?? ({})
    readonly property bool background: cfg.background ?? false
    readonly property real pad: background ? Theme.spacingM : 0
    readonly property bool resizable: false
    readonly property real minWidth: implicitWidth
    readonly property real minHeight: implicitHeight

    implicitWidth: statusRow.implicitWidth + pad * 2
    implicitHeight: statusRow.implicitHeight + pad * 2

    Rectangle {
        anchors.fill: parent
        visible: root.background
        radius: Theme.fullRadius(width, height)
        color: Theme.readableSurface
        border.width: Theme.layerOutlineWidth
        border.color: Theme.outlineMedium
    }

    LockStatusRow {
        id: statusRow
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: root.pad
        interactive: !(root.lockHost?.demoMode ?? true)
        showMediaPlayer: (root.cfg.showMediaPlayer ?? true) && !(root.lockHost?.greeterPreview ?? false)
        showWeather: root.cfg.showWeather ?? true
        useFahrenheit: SettingsData.useFahrenheit
    }
}
