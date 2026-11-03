pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import "../../../DCommon/Common/MaterialWallpaper.js" as Art

SettingsSwatchGrid {
    id: root

    property string seed: Art.defaultSeed
    property bool light: SessionData.isLightMode
    readonly property var candidates: Art.seedCandidates().map(candidate => ({
                value: candidate.seed,
                label: MaterialWallpaperOptions.label(MaterialWallpaperOptions.seedHues, candidate.slot)
            }))
    readonly property bool customSeed: !candidates.some(candidate => candidate.value === seed)
    readonly property string previewKey: MatugenPreviewService.keySuffix
    readonly property bool matugenAvailable: Theme.matugenAvailable

    signal seedSelected(string seed)

    options: customSeed ? [
        {
            value: seed,
            label: I18n.tr("Current")
        }
    ].concat(candidates) : candidates
    currentValue: seed
    resolveOption: option => {
        const palette = MatugenPreviewService.seedPalette(option.value, root.light);
        if (!palette)
            return {
                primary: option.value,
                secondary: option.value,
                tertiary: option.value
            };
        return {
            primary: palette.primary,
            secondary: palette.secondary,
            tertiary: palette.tertiary
        };
    }
    onSelected: value => {
        if (value === root.seed)
            return;
        root.seedSelected(value);
    }
    onSeedChanged: request()
    onPreviewKeyChanged: request()
    onMatugenAvailableChanged: request()
    onVisibleChanged: request()
    Component.onCompleted: request()

    function wantedSeeds() {
        return candidates.map(candidate => candidate.value).concat([seed]);
    }

    function request() {
        if (!visible)
            return;
        MatugenPreviewService.requestSeeds(wantedSeeds());
    }

    function retry() {
        MatugenPreviewService.retrySeeds(wantedSeeds());
    }
}
