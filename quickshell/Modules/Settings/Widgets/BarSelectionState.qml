import QtQuick
import Quickshell
import qs.Common
import qs.Services

Item {
    id: root

    readonly property string selectedBarId: SettingsUiState.selectedBarId

    function select(id) {
        SettingsUiState.selectedBarId = id;
    }

    readonly property var selectedBarConfig: {
        SettingsData.barConfigs;
        return SettingsData.getBarConfig(selectedBarId) ?? SettingsData.barConfigs[0] ?? null;
    }
    readonly property string selectedBarName: {
        selectedBarId;
        SettingsData.barConfigs;
        const index = SettingsData.barConfigs.findIndex(config => config.id === selectedBarId);
        if (index < 0)
            return I18n.tr("Bar", "fallback name for an unnamed bar");
        return SettingsData.barConfigs[index].name || I18n.tr("Bar %1", "numbered name for an unnamed bar, %1 is its position").arg(index + 1);
    }

    property bool selectedBarIsVertical: {
        selectedBarId;
        const pos = selectedBarConfig?.position ?? SettingsData.Position.Top;
        return pos === SettingsData.Position.Left || pos === SettingsData.Position.Right;
    }
    readonly property var selectedBarScreens: selectedBarConfig ? ShellLayout.assignedScreens(selectedBarConfig) : []

    readonly property bool selectedBarIsIsland: {
        SettingsData.barConfigs;
        selectedBarId;
        return SettingsData.isIslandBarConfig(selectedBarConfig);
    }
    readonly property int islandShadowedScreenCount: {
        SettingsData.barConfigs;
        if (!selectedBarConfig || root.selectedBarIsIsland)
            return 0;
        const edge = SettingsData.positionToSide(selectedBarConfig.position ?? SettingsData.Position.Top);
        return root.selectedBarScreens.filter(screen => SettingsData.dankIslandOwnsEdge(screen, edge)).length;
    }
    readonly property bool islandShadowsSelectedBar: root.islandShadowedScreenCount > 0 && root.islandShadowedScreenCount === root.selectedBarScreens.length
    readonly property bool islandOwnsSelectedBarTop: root.selectedBarIsIsland || root.islandShadowsSelectedBar
    readonly property int frameStyledScreenCount: {
        SettingsData.frameScreenPreferences;
        if (!SettingsData.frameEnabled)
            return 0;
        return root.selectedBarScreens.filter(screen => ShellLayout.forScreen(screen)?.frameConfigured).length;
    }
    readonly property bool selectedBarFrameStyled: SettingsData.frameEnabled && root.frameStyledScreenCount === root.selectedBarScreens.length
    readonly property bool selectedBarFrameSanitized: SettingsData.barUsesConnectedFrameStyle(root.selectedBarConfig) || root.selectedBarFrameStyled
    readonly property var positionChoices: ShellLayout.positionChoices(selectedBarConfig)

    function positionLabel(pos) {
        switch (pos) {
        case SettingsData.Position.Bottom:
            return I18n.tr("Bottom", "screen edge position");
        case SettingsData.Position.Left:
            return I18n.tr("Left", "screen edge position");
        case SettingsData.Position.Right:
            return I18n.tr("Right", "screen edge position");
        }
        return I18n.tr("Top", "screen edge position");
    }

    // inset padding stores < 0 as "auto", resolved here to the mode's natural inset
    readonly property real insetPadAutoUI: (SettingsData.connectedFrameModeActive && root.selectedBarFrameStyled) ? SettingsData.frameThickness : (selectedBarIsVertical ? Theme.spacingXS : Math.max(Theme.spacingXS, (selectedBarConfig?.innerPadding ?? SettingsData.barInnerPaddingDefault) * 0.8))
    readonly property int insetPadDisplayValue: {
        const raw = SettingsData.barInsetPaddingSyncAll ? SettingsData.barInsetPaddingShared : (selectedBarConfig?.barInsetPadding ?? -1);
        return raw < 0 ? Math.round(insetPadAutoUI) : raw;
    }

    Timer {
        id: horizontalBarChangeDebounce
        interval: 500
        repeat: false
        onTriggered: {
            const verticalBars = SettingsData.getBarKindConfigs().filter(cfg => {
                const pos = cfg.position ?? SettingsData.Position.Top;
                return pos === SettingsData.Position.Left || pos === SettingsData.Position.Right;
            });

            verticalBars.forEach(bar => {
                if (!bar.enabled)
                    return;
                SettingsData.updateBarConfig(bar.id, {
                    enabled: false
                });
                Qt.callLater(() => SettingsData.updateBarConfig(bar.id, {
                        enabled: true
                    }));
            });
        }
    }

    function defaultFor(key) {
        return key in SettingsData.islandDefaults ? SettingsData.islandDefaults[key] : SettingsData.barConfigDefault(key);
    }

    function isDefault(keys) {
        const config = selectedBarConfig;
        if (!config)
            return true;
        return keys.every(key => config[key] === undefined || JSON.stringify(config[key]) === JSON.stringify(defaultFor(key)));
    }

    function resetToDefault(keys) {
        const patch = {};
        for (const key of keys)
            patch[key] = defaultFor(key);
        SettingsData.updateBarConfig(selectedBarId, patch);
    }

    function islandSetting(key) {
        return SettingsData.islandSetting(selectedBarConfig, key);
    }

    readonly property IslandSettingsStore islandStore: IslandSettingsStore {
        barId: root.selectedBarId
    }

    function apply(key, value) {
        if (!selectedBarId)
            return;
        SettingsData.updateBarConfig(selectedBarId, {
            [key]: value
        });
    }

    function _isBarActive(c) {
        if (!c.enabled || SettingsData.isIslandBarConfig(c))
            return false;
        const prefs = c.screenPreferences || ["all"];
        if (prefs.length > 0)
            return !(c.hideOnLastDisplay ?? false) || Quickshell.screens.length !== 1;
        return (c.showOnLastDisplay ?? true) && Quickshell.screens.length === 1;
    }

    function notifyHorizontalBarChange() {
        const configs = SettingsData.getBarKindConfigs();
        if (configs.length < 2)
            return;

        const hasHorizontal = configs.some(c => {
            if (!_isBarActive(c))
                return false;
            const p = c.position ?? SettingsData.Position.Top;
            return p === SettingsData.Position.Top || p === SettingsData.Position.Bottom;
        });
        if (!hasHorizontal)
            return;

        const hasVertical = configs.some(c => {
            if (!_isBarActive(c))
                return false;
            const p = c.position ?? SettingsData.Position.Top;
            return p === SettingsData.Position.Left || p === SettingsData.Position.Right;
        });
        if (!hasVertical)
            return;

        horizontalBarChangeDebounce.restart();
    }
}
