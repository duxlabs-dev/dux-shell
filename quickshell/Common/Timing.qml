pragma Singleton

import QtQuick
import qs.DCommon.Common as DCommon

DCommon.TimingTokens {
    readonly property int portalColorSchemeSettleDelay: 750
    readonly property var resumeRecoverySchedule: [400, 1400, 2600]
    readonly property var brightnessHotplugRescanSchedule: [3000, 5000, 8000]
    readonly property int pamActiveTimeout: 15000
    readonly property int longPress: 400
}
