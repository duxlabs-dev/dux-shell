pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Modules.ControlCenter
import qs.Modules.ControlCenter.Widgets
import qs.Services
import qs.DCommon.Widgets
import "../../../Common/QmlUtils.js" as QmlUtils

Item {
    id: root

    implicitHeight: column.height

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    readonly property string title: I18n.tr("Audio Input")
    readonly property var pinnedInputs: QmlUtils.normalizePinList((CacheData.audioInputDevicePins || {})["preferredInput"])

    readonly property Item headerActions: CcSettingsButton {
        settingsTab: "audio"
    }

    function togglePin(name) {
        CacheData.set("audioInputDevicePins", QmlUtils.togglePinEntry(CacheData.audioInputDevicePins, "preferredInput", name, CcMetrics.maxPins));
    }

    function deviceIcon(node) {
        const name = node?.name ?? "";
        return name.includes("bluez") || name.includes("usb") ? "headset" : "mic";
    }

    DFlickable {
        anchors.fill: parent
        contentHeight: column.height
        clip: true

        Column {
            id: column
            width: parent.width
            spacing: CcMetrics.detailContentGap

            CcGroup {
                AudioSliderRow {
                    node: AudioService.source
                    isInput: true
                }
            }

            CcSectionLabel {
                text: I18n.tr("Input devices")
            }

            CcGroup {
                Repeater {
                    model: ScriptModel {
                        values: {
                            const hidden = SessionData.hiddenInputDeviceNames ?? [];
                            const nodes = AudioService.allNodes.filter(node => node.audio && !node.isSink && !node.isStream && !hidden.includes(node.name));
                            const pinnedList = root.pinnedInputs;
                            return nodes.sort((a, b) => {
                                const aPinned = pinnedList.indexOf(a.name);
                                const bPinned = pinnedList.indexOf(b.name);
                                if (aPinned !== -1 || bPinned !== -1) {
                                    if (aPinned === -1)
                                        return 1;
                                    if (bPinned === -1)
                                        return -1;
                                    return aPinned - bPinned;
                                }
                                if (a === AudioService.source && b !== AudioService.source)
                                    return -1;
                                if (b === AudioService.source && a !== AudioService.source)
                                    return 1;
                                return 0;
                            });
                        }
                    }

                    CcListRow {
                        id: deviceRow

                        required property var modelData

                        iconName: root.deviceIcon(modelData)
                        title: AudioService.displayName(modelData)
                        subtitle: active ? I18n.tr("Active") : I18n.tr("Available")
                        active: modelData === AudioService.source
                        clickable: true
                        onClicked: {
                            if (modelData?.name)
                                AudioService.setDefaultSourceByName(modelData.name);
                        }

                        CcPinChip {
                            anchors.verticalCenter: parent.verticalCenter
                            pinned: root.pinnedInputs.includes(deviceRow.modelData.name)
                            onToggled: root.togglePin(deviceRow.modelData.name)
                        }
                    }
                }
            }
        }
    }
}
