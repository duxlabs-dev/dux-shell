pragma Singleton

import QtQuick
import Quickshell
import qs.Common

Singleton {
    id: root
    readonly property int previewLength: 100
    readonly property int longTextThreshold: 200
    readonly property int modalWidth: 650
    readonly property int modalHeight: 550
    readonly property int popoutWidth: 550
    readonly property int popoutHeight: 500
    readonly property real itemHeight: Theme.listItemTwoLineHeight + Theme.densityStepM
    readonly property int thumbnailSize: 100
    readonly property int retryInterval: 50
    readonly property int viewportBuffer: 100
    readonly property int extendedBuffer: 200
    readonly property int headerHeight: 32

    function sizeWidth(size) {
        switch (size) {
        case "micro":
            return Theme.launcherWidthMicro;
        case "medium":
            return Theme.launcherWidthWide;
        case "large":
            return Theme.launcherWidthLarge;
        default:
            return modalWidth;
        }
    }

    function sizeHeight(size) {
        switch (size) {
        case "micro":
            return Theme.smallBreakpoint;
        case "medium":
            return Theme.launcherWidthWide;
        case "large":
            return Theme.launcherWidthLarge;
        default:
            return modalHeight;
        }
    }
}
