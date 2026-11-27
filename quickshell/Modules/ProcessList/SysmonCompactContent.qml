import QtQuick
import qs.Common
import qs.Services
import "../../Services/SysmonCatalog.js" as SysmonCatalog

Item {
    id: root

    property string deviceKey: ""
    property string entryType: ""
    property bool active: false

    readonly property string paneKey: deviceKey || entryType
    readonly property string type: SysmonService.parseKey(paneKey).type
    // A GPU dgop doesn't list (yet) has no pane to show.
    readonly property bool placeholder: (type === "gpu" || type === "") && SysmonService.device(paneKey) === null
    readonly property bool gpuLook: type === "gpu"
    readonly property string monitorTarget: placeholder ? "processes" : paneKey
    readonly property var modules: SysmonCatalog.paneModules(paneKey)

    implicitHeight: placeholder ? placeholderPane.implicitHeight : pane.implicitHeight

    Ref {
        service: DgopService
        modules: root.modules
        active: root.active && root.modules.length > 0
    }

    Ref {
        service: DriveService
        active: root.active && root.type === "disk"
    }

    DevicePaneLoader {
        id: pane
        width: parent.width
        height: implicitHeight
        active: root.active && !root.placeholder
        visible: active
        key: root.paneKey
        variant: "compact"
    }

    DevicePane {
        id: placeholderPane
        width: parent.width
        height: implicitHeight
        visible: root.placeholder
        variant: "compact"
        typeKey: root.type
        title: root.gpuLook ? SysmonService.typeName("gpu") : ""
        iconName: root.gpuLook ? "gpu" : ""
        mainValue: "—"
    }
}
