import QtQuick
import qs.Common
import qs.Modals.Common
import qs.Services
import qs.Modules.PowerMenu
import qs.DCommon.Session

DModal {
    id: root

    layerNamespace: "dms:power-menu"
    keepPopoutsOpen: true
    useOverlayLayer: true
    animationType: "fade"
    animationDuration: LockMetrics.effectsDuration
    animationEnterCurve: Theme.expressiveCurves.expressiveEffects
    animationExitCurve: Theme.expressiveCurves.expressiveEffects

    property rect parentBounds: Qt.rect(0, 0, 0, 0)
    property var parentScreen: null

    signal powerActionRequested(string action, string title, string message)
    signal lockRequested
    signal switchUserRequested

    function openCentered() {
        parentBounds = Qt.rect(0, 0, 0, 0);
        parentScreen = null;
        open();
    }

    function openFromControlCenter(bounds, targetScreen) {
        parentBounds = bounds;
        parentScreen = targetScreen;
        open();
    }

    shouldBeVisible: false
    modalWidth: contentLoader.item?.desiredWidth ?? LockMetrics.powerMenuWidth
    modalHeight: contentLoader.item ? contentLoader.item.implicitHeight : LockMetrics.powerGridButtonHeight
    enableShadow: true
    targetScreen: parentScreen
    positioning: parentBounds.width > 0 ? "custom" : "center"
    customPosition: {
        if (parentBounds.width > 0) {
            const bar = SettingsData.getPrimaryBarConfig();
            const effectiveBarThickness = Theme.barThickness(bar?.innerPadding ?? SettingsData.barInnerPaddingDefault, CompositorService.getScreenScale(parentScreen));
            const barExclusionZone = effectiveBarThickness + (bar?.spacing ?? 4) + (bar?.bottomGap ?? 0);
            const barPosition = bar?.position ?? SettingsData.Position.Top;
            const screenW = parentScreen?.width ?? 1920;
            const screenH = parentScreen?.height ?? 1080;
            const margin = Theme.spacingL;

            let targetX = parentBounds.x + (parentBounds.width - modalWidth) / 2;
            let targetY = parentBounds.y + (parentBounds.height - modalHeight) / 2;

            const topChrome = Math.max(bar && barPosition === SettingsData.Position.Top ? barExclusionZone : 0, SettingsData.dankIslandEdgeOffset(parentScreen, "top"));
            const bottomChrome = Math.max(bar && barPosition === SettingsData.Position.Bottom ? barExclusionZone : 0, SettingsData.dankIslandEdgeOffset(parentScreen, "bottom"));
            const leftChrome = Math.max(bar && barPosition === SettingsData.Position.Left ? barExclusionZone : 0, SettingsData.dankIslandEdgeOffset(parentScreen, "left"));
            const rightChrome = Math.max(bar && barPosition === SettingsData.Position.Right ? barExclusionZone : 0, SettingsData.dankIslandEdgeOffset(parentScreen, "right"));
            const minY = topChrome + margin;
            const maxY = screenH - modalHeight - bottomChrome - margin;
            const minX = leftChrome + margin;
            const maxX = screenW - modalWidth - rightChrome - margin;

            targetX = Math.max(minX, Math.min(maxX, targetX));
            targetY = Math.max(minY, Math.min(maxY, targetY));

            return Qt.point(targetX, targetY);
        }
        return Qt.point(0, 0);
    }
    onBackgroundClicked: () => {
        contentLoader.item?.cancelHold();
        close();
    }
    onShouldBeVisibleChanged: {
        if (!shouldBeVisible)
            return;
        contentLoader.item?.resetState();
    }
    onShouldHaveFocusChanged: {
        if (!shouldHaveFocus)
            return;
        Qt.callLater(() => contentLoader.item?.forceActiveFocus());
    }
    onDialogClosed: () => {
        contentLoader.item?.cancelHold();
    }

    content: Component {
        PowerMenuContent {
            anchors.fill: parent
            focus: true
            onPowerActionRequested: action => root.powerActionRequested(action, "", "")
            onLockRequested: root.lockRequested()
            onSwitchUserRequested: root.switchUserRequested()
            onCloseRequested: root.close()
        }
    }
}
