pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common

Variants {
    id: root

    model: ShellLayout.realScreens

    delegate: Loader {
        id: instanceLoader

        required property var modelData

        // Live-or-latched: instances build early on enable, survive until ack on disable
        active: (SettingsData.frameEnabled || FrameTransitionState.effectiveFrameEnabled) && SettingsData.isScreenInPreferences(instanceLoader.modelData, SettingsData.frameScreenPreferences)
        asynchronous: false

        sourceComponent: FrameInstance {
            screen: instanceLoader.modelData
        }
    }
}
