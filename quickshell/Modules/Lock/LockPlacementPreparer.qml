pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Services

Variants {
    model: Quickshell.screens

    Scope {
        id: scope

        required property var modelData
        readonly property string backgroundKey: LockPlacementService.backgroundKey(modelData.name, modelData.width, modelData.height)
        property string failedKey: ""
        property bool sampling: false
        onBackgroundKeyChanged: failedKey = ""

        Loader {
            id: preparation
            active: scope.sampling || (!IdleService.isShellLocked && !LockPlacementService.usesScrollAtlas(scope.modelData.name) && LockPlacementService.neededFor(scope.modelData) && scope.failedKey !== scope.backgroundKey && !LockPlacementService.hasSample(scope.modelData.name, scope.backgroundKey))
            asynchronous: true

            sourceComponent: PanelWindow {
                screen: scope.modelData
                anchors.top: true
                anchors.bottom: true
                anchors.left: true
                anchors.right: true
                color: "transparent"
                WlrLayershell.namespace: "dms:lock-placement"
                WlrLayershell.layer: WlrLayer.Background
                WlrLayershell.exclusionMode: ExclusionMode.Ignore
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                mask: Region {}

                Item {
                    anchors.fill: parent
                    opacity: 0

                    LockScreenBackground {
                        id: background
                        anchors.fill: parent
                        screenName: scope.modelData.name
                        asynchronous: true
                    }

                    LockBackgroundSampler {
                        id: sampler
                        sourceItem: background
                        ready: background.ready && !IdleService.isShellLocked
                        renderKey: scope.backgroundKey
                        onBusyChanged: scope.sampling = busy
                        onFailed: scope.failedKey = scope.backgroundKey
                        onSampled: (luminances, sampleWidth, sampleHeight) => LockPlacementService.storeSample(scope.modelData.name, scope.backgroundKey, luminances, sampleWidth, sampleHeight)
                    }
                }
            }
        }
    }
}
