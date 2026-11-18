pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

Singleton {
    id: root

    readonly property int durShort: 200
    readonly property int durMed: 450
    readonly property int durLong: 600

    // Navigation feedback stays responsive even when ambient shell motion is slow.
    readonly property int settingsNavigationStateDuration: 180
    readonly property int settingsNavigationRippleDuration: 200

    readonly property int slidePx: 80
}
