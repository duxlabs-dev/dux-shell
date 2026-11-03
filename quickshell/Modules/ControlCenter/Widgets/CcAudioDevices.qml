import QtQuick
import qs.Common
import qs.Services
import "../../../Common/QmlUtils.js" as QmlUtils

CcTileActions {
    id: root

    property bool isInput: false
    readonly property var pins: QmlUtils.normalizePinList(isInput ? (CacheData.audioInputDevicePins || {}).preferredInput : (CacheData.audioOutputDevicePins || {}).preferredOutput)
    readonly property var selectedNode: isInput ? AudioService.source : AudioService.sink
    readonly property var devices: {
        const hidden = (isInput ? SessionData.hiddenInputDeviceNames : SessionData.hiddenOutputDeviceNames) || [];
        return AudioService.allNodes.filter(node => node.audio && node.isSink !== isInput && !node.isStream && !hidden.includes(node.name)).sort((a, b) => {
            const aPin = pins.indexOf(a.name);
            const bPin = pins.indexOf(b.name);
            if (aPin !== bPin)
                return (aPin < 0 ? Infinity : aPin) - (bPin < 0 ? Infinity : bPin);
            return Number(b === selectedNode) - Number(a === selectedNode);
        });
    }
    actions: devices.map(node => ({
                text: AudioService.displayName(node),
                icon: isInput ? "mic" : AudioService.sinkIcon(node),
                active: node === selectedNode,
                trigger: () => isInput ? AudioService.setDefaultSourceByName(node.name) : AudioService.setDefaultSinkByName(node.name)
            }))
}
