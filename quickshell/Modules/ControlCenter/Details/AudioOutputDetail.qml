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

    readonly property string title: I18n.tr("Audio Output")
    readonly property var pinnedOutputs: QmlUtils.normalizePinList((CacheData.audioOutputDevicePins || {})["preferredOutput"])

    readonly property Item headerActions: CcSettingsButton {
        settingsTab: "audio"
    }

    signal showPortSelector(var node)

    Component.onCompleted: {
        AudioService.refreshSinkPorts();
        AudioService.refreshCards();
    }

    function togglePin(name) {
        CacheData.set("audioOutputDevicePins", QmlUtils.togglePinEntry(CacheData.audioOutputDevicePins, "preferredOutput", name, CcMetrics.maxPins));
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
                    node: AudioService.sink
                    maxVolume: AudioService.sinkMaxVolume
                    playFeedback: true
                }
            }

            CcSectionLabel {
                text: I18n.tr("Audio Devices")
            }

            CcGroup {
                Repeater {
                    model: ScriptModel {
                        values: {
                            const hidden = SessionData.hiddenOutputDeviceNames ?? [];
                            const nodes = AudioService.allNodes.filter(node => node.audio && node.isSink && !node.isStream && !hidden.includes(node.name) && AudioService.isSinkAvailable(node));
                            const pinnedList = root.pinnedOutputs;
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
                                if (a === AudioService.sink && b !== AudioService.sink)
                                    return -1;
                                if (b === AudioService.sink && a !== AudioService.sink)
                                    return 1;
                                return 0;
                            });
                        }
                    }

                    CcListRow {
                        id: deviceRow

                        required property var modelData

                        iconName: AudioService.sinkIcon(modelData)
                        title: AudioService.displayName(modelData)
                        subtitle: active ? I18n.tr("Active") : I18n.tr("Available")
                        active: modelData === AudioService.sink
                        clickable: true
                        onClicked: {
                            if (modelData?.name)
                                AudioService.setDefaultSinkByName(modelData.name);
                        }

                        DActionButton {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: AudioService.sinkHasMultiplePorts(deviceRow.modelData)
                            buttonSize: Theme.buttonHeightXS
                            iconSize: Theme.iconSizeMedium
                            iconName: "tune"
                            iconColor: Theme.surfaceText
                            tooltipText: I18n.tr("Port Selection", "audio output port selector button tooltip")
                            onClicked: root.showPortSelector(deviceRow.modelData)
                        }

                        CcPinChip {
                            anchors.verticalCenter: parent.verticalCenter
                            pinned: root.pinnedOutputs.includes(deviceRow.modelData.name)
                            onToggled: root.togglePin(deviceRow.modelData.name)
                        }
                    }
                }

                Repeater {
                    model: ScriptModel {
                        values: AudioService.switchableOutputPorts
                    }

                    CcListRow {
                        required property var modelData

                        iconName: modelData.icon
                        title: modelData.title
                        subtitle: modelData.cardDescription
                        clickable: true
                        onClicked: AudioService.activateOutputPort(modelData, (ok, message) => ToastService.showToast(message, ok ? ToastService.levelInfo : ToastService.levelError))
                    }
                }
            }

            CcSectionLabel {
                text: I18n.tr("Playback", "section label above per-app audio playback streams")
                visible: playbackGroup.visible
            }

            CcGroup {
                id: playbackGroup
                visible: playbackRepeater.count > 0

                Repeater {
                    id: playbackRepeater
                    model: ScriptModel {
                        values: AudioService.pipewireNodes.filter(node => node.audio && node.isSink && node.isStream && !AudioService.isOwnStream(node))
                    }

                    CcListRow {
                        id: streamRow

                        required property var modelData

                        title: AudioService.displayName(modelData) + ": " + (modelData?.properties?.["media.name"] || "")

                        body: AudioSliderRow {
                            node: streamRow.modelData
                            sliderLabel: streamRow.title
                            playFeedback: true
                        }
                    }
                }
            }
        }
    }
}
