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

    readonly property var emphasized: [0.05, 0.00, 0.133333, 0.06, 0.166667, 0.40, 0.208333, 0.82, 0.25, 1.00, 1.00, 1.00]

    readonly property var emphasizedDecel: [0.05, 0.70, 0.10, 1.00, 1.00, 1.00]

    readonly property var emphasizedAccel: [0.30, 0.00, 0.80, 0.15, 1.00, 1.00]

    readonly property var standard: [0.20, 0.00, 0.00, 1.00, 1.00, 1.00]
    readonly property var standardDecel: [0.00, 0.00, 0.00, 1.00, 1.00, 1.00]
    readonly property var standardAccel: [0.30, 0.00, 1.00, 1.00, 1.00, 1.00]

    // Used by AnimVariants for variant/effect logic
    readonly property var expressiveDefaultSpatial: [0.38, 1.21, 0.22, 1, 1, 1]
    readonly property var expressiveFastSpatial: [0.42, 1.67, 0.21, 0.9, 1, 1]
    readonly property var expressiveEffects: [0.34, 0.8, 0.34, 1, 1, 1]
}
