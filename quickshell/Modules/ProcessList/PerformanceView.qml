pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Modules.Settings.Widgets

Item {
    id: root

    readonly property bool isFloatingWindowSurface: true

    property string currentKey: "cpu"
    property bool showHidden: false

    function scrollToTop() {
        const flick = pane.item as DevicePane;
        if (flick)
            flick.contentY = 0;
    }

    readonly property var allDevices: SysmonService.devices({
        showHidden: true
    })
    readonly property int hiddenCount: allDevices.filter(e => e.hidden).length

    readonly property var railModel: allDevices.filter(e => root.showHidden || !e.hidden).map(e => Object.assign({}, e, SysmonService.summary(e)))

    readonly property var activeEntry: railModel.find(e => e.key === currentKey) ?? railModel[0]
    readonly property string activeKey: activeEntry.key
    onActiveKeyChanged: scrollToTop()

    function revealCurrent() {
        if (allDevices.find(e => e.key === currentKey)?.hidden)
            showHidden = true;
    }

    onCurrentKeyChanged: revealCurrent()
    Component.onCompleted: revealCurrent()

    Ref {
        service: DgopService
        modules: ["cpu", "memory", "system", "disk-rate", "net-rate", "diskmounts", "gpu", "memory-modules"]
        active: root.visible
    }

    RowLayout {
        anchors.fill: parent
        spacing: Theme.spacingXL

        DeviceRail {
            Layout.preferredWidth: Theme.navigationRailWidth * 3
            Layout.fillHeight: true
            model: root.railModel
            currentKey: root.activeKey
            historyLength: DgopService.historySize
            hiddenCount: root.hiddenCount
            showHidden: root.showHidden
            onSelected: key => root.currentKey = key
            onShowHiddenToggled: {
                root.showHidden = !root.showHidden;
                root.currentKey = root.activeKey;
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: SettingsMetrics.paneRadius
            color: SettingsMetrics.paneColor
            border.width: Theme.layerOutlineWidth
            border.color: Theme.outlineMedium
            clip: true

            DevicePaneLoader {
                id: pane
                anchors.fill: parent
                anchors.margins: SettingsMetrics.panePadding
                key: root.activeKey
            }
        }
    }
}
