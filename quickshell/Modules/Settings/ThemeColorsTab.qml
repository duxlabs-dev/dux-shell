import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.Common
import qs.Modals.Common
import qs.Modals.FileBrowser
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets
import "../../Common/ThemePalette.js" as ThemePalette
import "../../Common/ContrastFloors.js" as ContrastFloors

Item {
    id: themeColorsTab

    property var parentModal: null
    property string pendingExtractJson: ""
    property var cachedSourceModes: Theme.availableSourceModes.map(option => option.label)
    readonly property string matugenPreviewKey: MatugenPreviewService.key
    readonly property bool matugenAvailable: Theme.matugenAvailable
    readonly property bool dynamicTheme: Theme.currentTheme === Theme.dynamic && Theme.currentThemeCategory !== "registry"
    readonly property var currentPalette: ThemePalette.pick({
        "primary": Theme.primary,
        "secondary": Theme.secondary,
        "tertiary": Theme.tertiary,
        "primaryContainer": Theme.primaryContainer,
        "info": Theme.info,
        "error": Theme.error,
        "warning": Theme.warning
    })
    onMatugenPreviewKeyChanged: MatugenPreviewService.refresh()
    onMatugenAvailableChanged: MatugenPreviewService.refresh()
    readonly property var log: Log.scoped("ThemeColorsTab")
    property var installedRegistryThemes: []
    readonly property var activeRegistryTheme: {
        const file = SettingsData.customThemeFile;
        if (Theme.currentThemeCategory !== "registry" || Theme.currentTheme !== Theme.custom || !file)
            return null;
        return installedRegistryThemes.find(t => file.endsWith((t.sourceDir || t.id) + "/theme.json")) ?? null;
    }

    function registryThemeDir(theme) {
        return Quickshell.env("HOME") + "/.config/dms/themes/" + (theme.sourceDir || theme.id);
    }
    Component.onCompleted: {
        if (DMSService.dmsAvailable)
            DMSService.listInstalledThemes();
        if (PopoutService.pendingThemeInstall)
            Qt.callLater(() => showThemeBrowser());
        MatugenPreviewService.refresh();
    }

    Connections {
        target: DMSService
        function onInstalledThemesReceived(themes) {
            themeColorsTab.installedRegistryThemes = themes;
        }
    }

    Connections {
        target: PopoutService
        function onPendingThemeInstallChanged() {
            if (PopoutService.pendingThemeInstall)
                showThemeBrowser();
        }
    }

    SettingsPage {
        id: mainColumn

        SettingsCard {
            tab: "theme"
            tags: ["color", "palette", "theme", "appearance"]
            title: I18n.tr("Theme")
            settingKey: "themeColor"
            iconName: "palette"

            SettingsRow {
                body: Column {
                    width: parent.width
                    spacing: Theme.spacingS

                    StyledText {
                        readonly property string registryThemeName: themeColorsTab.activeRegistryTheme?.name ?? ""
                        text: {
                            if (Theme.currentThemeCategory === "registry" && registryThemeName)
                                return I18n.tr("Current Theme: %1", "current theme label").arg(registryThemeName);
                            return I18n.tr("Current Theme: %1", "current theme label").arg(Theme.currentThemeLabel);
                        }
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.surfaceText
                        font.weight: Theme.fontWeightMedium
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    StyledText {
                        text: {
                            if (Theme.currentTheme === Theme.dynamic)
                                return I18n.tr("Material colors generated from wallpaper", "dynamic theme description");
                            if (Theme.currentThemeCategory === "registry")
                                return I18n.tr("Color theme from DMS registry", "registry theme description");
                            if (Theme.currentTheme === Theme.custom)
                                return I18n.tr("Custom theme loaded from JSON file", "custom theme description");
                            return I18n.tr("Material Design inspired color themes", "generic theme description");
                        }
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        anchors.horizontalCenter: parent.horizontalCenter
                        wrapMode: Text.WordWrap
                        width: Math.min(parent.width, 400)
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }

            SettingsRow {
                body: Column {
                    id: themeCategoryColumn
                    spacing: Theme.spacingM
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width

                    Item {
                        width: parent.width
                        height: themeCategoryGroup.implicitHeight + Theme.focusRingOffset * 2
                        clip: true

                        DButtonGroup {
                            id: themeCategoryGroup
                            arrowKeysSelect: false
                            anchors.centerIn: parent
                            buttonPadding: parent.width < 420 ? Theme.spacingS : Theme.spacingL
                            minButtonWidth: parent.width < 420 ? 44 : 64
                            textSize: parent.width < 420 ? Theme.fontSizeSmall : Theme.fontSizeMedium
                            property bool isRegistryTheme: Theme.currentThemeCategory === "registry"
                            property int pendingIndex: -1
                            property int computedIndex: {
                                if (isRegistryTheme)
                                    return 3;
                                if (Theme.currentTheme === Theme.dynamic)
                                    return 1;
                                if (Theme.currentThemeName === "custom")
                                    return 2;
                                return 0;
                            }

                            model: DMSService.dmsAvailable ? [I18n.tr("Generic", "theme category option"), I18n.tr("Auto", "theme category option"), I18n.tr("Custom", "theme category option"), I18n.tr("Browse", "theme category option")] : [I18n.tr("Generic", "theme category option"), I18n.tr("Auto", "theme category option"), I18n.tr("Custom", "theme category option")]
                            currentIndex: pendingIndex >= 0 ? pendingIndex : computedIndex
                            selectionMode: "single"
                            onSelectionChanged: (index, selected) => {
                                if (!selected)
                                    return;
                                pendingIndex = index;
                            }
                            onAnimationCompleted: {
                                if (pendingIndex < 0)
                                    return;
                                const idx = pendingIndex;
                                pendingIndex = -1;
                                switch (idx) {
                                case 0:
                                    Theme.switchThemeCategory("generic", "blue");
                                    break;
                                case 1:
                                    if (ToastService.wallpaperErrorStatus === "matugen_missing" || ToastService.wallpaperErrorStatus === "error") {
                                        if (ToastService.wallpaperErrorStatus === "matugen_missing")
                                            ToastService.showError(I18n.tr("%1 not found", "missing program, %1 is a program name").arg("matugen"), I18n.tr("Install the %1 package for dynamic theming", "matugen installation hint, %1 is the package name").arg("matugen"));
                                        else
                                            ToastService.showError(I18n.tr("Wallpaper processing failed - check wallpaper path", "wallpaper error"));
                                        break;
                                    }
                                    Theme.switchThemeCategory("dynamic", Theme.dynamic);
                                    break;
                                case 2:
                                    Theme.switchThemeCategory("custom", "custom");
                                    break;
                                case 3:
                                    Theme.switchThemeCategory("registry", "");
                                    break;
                                }
                            }
                        }
                    }

                    SettingsSwatchGrid {
                        readonly property bool genericTheme: Theme.currentThemeCategory === "generic" && Theme.currentTheme !== Theme.dynamic && Theme.currentThemeName !== "custom"

                        width: parent.width
                        visible: genericTheme
                        options: ["blue", "purple", "green", "orange", "red", "cyan", "pink", "amber", "coral", "monochrome"].map(name => {
                            const colors = Theme.getThemeColors(name);
                            const palette = ThemePalette.pick(colors) ?? {};
                            return {
                                "value": name,
                                "label": colors.name,
                                "primary": palette.primary ?? Theme.primary.toString(),
                                "secondary": palette.secondary,
                                "tertiary": palette.tertiary
                            };
                        })
                        currentValue: genericTheme ? Theme.currentThemeName : ""
                        onSelected: value => Theme.switchTheme(value)
                    }
                }
            }

            SettingsRow {
                visible: themeColorsTab.dynamicTheme
                body: Row {
                    width: parent.width
                    spacing: Theme.spacingM

                    StyledRect {
                        width: 120
                        height: 90
                        radius: Theme.cornerRadius
                        color: SettingsMetrics.controlColor
                        border.width: Theme.layerOutlineWidth
                        border.color: Theme.outlineMedium

                        ClippingRectangle {
                            anchors.fill: parent
                            anchors.margins: Theme.outlineWidth
                            radius: Theme.cornerRadius - Theme.outlineWidth
                            color: "transparent"

                            Image {
                                anchors.fill: parent
                                source: {
                                    var wp = Theme.wallpaperPath;
                                    if (!wp || wp === "" || wp.startsWith("#"))
                                        return "";
                                    if (wp.startsWith("file://"))
                                        wp = wp.substring(7);
                                    return "file://" + wp.split('/').map(s => encodeURIComponent(s)).join('/');
                                }
                                fillMode: Image.PreserveAspectCrop
                                visible: Theme.wallpaperPath && !Theme.wallpaperPath.startsWith("#")
                                sourceSize.width: 120
                                sourceSize.height: 120
                                asynchronous: true
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: Theme.outlineWidth
                            radius: Theme.cornerRadius - Theme.outlineWidth
                            color: Theme.wallpaperPath && Theme.wallpaperPath.startsWith("#") ? Theme.wallpaperPath : Theme.withAlpha(Theme.wallpaperPath, 0)
                            visible: Theme.wallpaperPath && Theme.wallpaperPath.startsWith("#")
                        }

                        DIcon {
                            anchors.centerIn: parent
                            name: (ToastService.wallpaperErrorStatus === "error" || ToastService.wallpaperErrorStatus === "matugen_missing") ? "error" : "palette"
                            size: Theme.iconSizeLarge
                            color: (ToastService.wallpaperErrorStatus === "error" || ToastService.wallpaperErrorStatus === "matugen_missing") ? Theme.error : Theme.surfaceVariantText
                            visible: !Theme.wallpaperPath
                        }
                    }

                    Column {
                        width: parent.width - 120 - Theme.spacingM - 36 - Theme.spacingM
                        spacing: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter

                        StyledText {
                            text: {
                                if (ToastService.wallpaperErrorStatus === "error")
                                    return I18n.tr("Wallpaper Error", "wallpaper error status");
                                if (ToastService.wallpaperErrorStatus === "matugen_missing")
                                    return I18n.tr("Matugen Missing", "matugen not found status");
                                if (Theme.wallpaperPath)
                                    return Theme.wallpaperPath.split('/').pop();
                                return I18n.tr("Material", "wallpaper type");
                            }
                            font.pixelSize: Theme.fontSizeLarge
                            color: Theme.surfaceText
                            elide: Text.ElideMiddle
                            maximumLineCount: 1
                            width: parent.width
                        }

                        StyledText {
                            id: wallpaperPathText
                            text: {
                                if (ToastService.wallpaperErrorStatus === "error")
                                    return I18n.tr("Wallpaper processing failed", "wallpaper processing error");
                                if (ToastService.wallpaperErrorStatus === "matugen_missing")
                                    return I18n.tr("Install the %1 package for dynamic theming", "matugen installation hint, %1 is the package name").arg("matugen");
                                if (Theme.wallpaperPath)
                                    return Theme.wallpaperPath;
                                return I18n.tr("Dynamic colors from wallpaper", "dynamic colors description");
                            }
                            font.pixelSize: Theme.fontSizeSmall
                            color: (ToastService.wallpaperErrorStatus === "error" || ToastService.wallpaperErrorStatus === "matugen_missing") ? Theme.error : Theme.surfaceVariantText
                            elide: Text.ElideMiddle
                            maximumLineCount: 2
                            width: parent.width
                            wrapMode: Text.WordWrap
                        }
                    }

                    DActionButton {
                        buttonSize: 36
                        iconName: "download"
                        iconSize: Theme.iconSize
                        backgroundColor: Theme.primaryHover
                        iconColor: Theme.primary
                        tooltipText: I18n.tr("Extract theme to JSON", "extract theme tooltip")
                        anchors.bottom: parent.bottom
                        onClicked: {
                            pendingExtractJson = Theme.extractCurrentTheme();
                            saveBrowserLoader.active = true;
                            if (saveBrowserLoader.item)
                                saveBrowserLoader.item.open();
                        }
                    }
                }
            }

            SettingsButtonGroupRow {
                visible: themeColorsTab.dynamicTheme
                tab: "theme"
                tags: ["matugen", "spec", "expressive", "vivid", "saturated", "bold", "dynamic"]
                settingKey: "matugenSpec"
                text: I18n.tr("Material palette", "theme settings card title, matugen palette options")
                enabled: Theme.matugenAvailable
                model: ["2021", "2025", "dms"]
                currentIndex: SettingsData.matugenSpec === "dms" ? 2 : SettingsData.matugenSpec === "2025" ? 1 : 0
                onSelectionChanged: (index, selected) => {
                    if (!selected)
                        return;
                    SettingsData.setMatugenSpec(["2021", "2025", "dms"][index]);
                }
            }

            SettingsRow {
                visible: themeColorsTab.dynamicTheme
                tab: "theme"
                tags: ["matugen", "palette", "algorithm", "dynamic"]
                settingKey: "matugenScheme"
                title: I18n.tr("Matugen palette")
                subtitle: {
                    const scheme = Theme.getMatugenScheme(SettingsData.matugenScheme);
                    return scheme.description + " (" + scheme.value + ")";
                }
                enabled: Theme.matugenAvailable
                body: Item {
                    width: parent.width
                    // the grid keeps its height while previews regenerate so the page does not jump
                    height: schemeGrid.implicitHeight

                    SettingsSwatchGrid {
                        id: schemeGrid
                        options: MatugenPreviewService.schemeOptions
                        currentValue: SettingsData.matugenScheme
                        enabled: MatugenPreviewService.ready
                        opacity: MatugenPreviewService.ready ? 1 : Theme.pendingOpacity
                        onSelected: value => SettingsData.setMatugenScheme(value)

                        Behavior on opacity {
                            NumberAnimation {
                                duration: Theme.expressiveDurations.expressiveFastEffects
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
                            }
                        }
                    }

                    DSpinner {
                        anchors.centerIn: parent
                        running: !MatugenPreviewService.ready
                        visible: running
                    }
                }
            }

            SettingsDropdownRow {
                visible: themeColorsTab.dynamicTheme
                tab: "theme"
                tags: ["matugen", "seed", "source", "wallpaper", "dynamic"]
                settingKey: "matugenSourceMode"
                text: I18n.tr("Source color")
                description: I18n.tr("Which wallpaper color the palette is built from", "matugen source color dropdown description")
                options: cachedSourceModes
                currentValue: Theme.getSourceMode(SettingsData.matugenSourceMode).label
                enabled: Theme.matugenAvailable && !SettingsData.matugenSeedColor && !!Theme.rawWallpaperPath
                onValueChanged: value => {
                    for (var i = 0; i < Theme.availableSourceModes.length; i++) {
                        var option = Theme.availableSourceModes[i];
                        if (option.label === value) {
                            SettingsData.setMatugenSourceMode(option.value);
                            break;
                        }
                    }
                }
            }

            ColorDropdownRow {
                visible: themeColorsTab.dynamicTheme
                tab: "theme"
                tags: ["matugen", "seed", "pick", "eyedropper", "dynamic"]
                settingKey: "matugenSeedColor"
                text: I18n.tr("Derived color", "matugen dropdown label, which color the palette is derived from")
                description: I18n.tr("Custom builds the palette from a color you pick", "matugen derived color dropdown description")
                enabled: Theme.matugenAvailable
                options: [
                    {
                        "value": "default",
                        "previewColor": (!Theme.rawWallpaperPath ? Theme.materialWallpaperSeed : Theme.getMatugenColor("source_color", Theme.primary)),
                        "label": Theme.rawWallpaperPath ? I18n.tr("From wallpaper", "matugen seed color option") : I18n.tr("Material", "wallpaper type")
                    },
                    {
                        "value": "custom",
                        "label": I18n.tr("Custom")
                    }
                ]
                currentMode: SettingsData.matugenSeedColor ? "custom" : "default"
                customColor: SettingsData.matugenSeedColor || (!Theme.rawWallpaperPath ? Theme.materialWallpaperSeed : Theme.getMatugenColor("source_color", Theme.primary))
                pickerTitle: I18n.tr("Seed color", "color picker title, the color the dynamic palette is built from")
                onModeSelected: mode => {
                    if (mode !== "custom") {
                        SettingsData.setMatugenSeedColor("");
                        return;
                    }
                    if (SettingsData.matugenSeedColor)
                        return;
                    SettingsData.setMatugenSeedColor((!Theme.rawWallpaperPath ? Theme.materialWallpaperSeed : Theme.getMatugenColor("source_color", Theme.primary)).toString());
                }
                onCustomColorSelected: selectedColor => SettingsData.setMatugenSeedColor(Theme.withAlpha(selectedColor, 1).toString())
            }

            SettingsSliderRow {
                id: contrastRow
                visible: themeColorsTab.dynamicTheme
                tab: "theme"
                tags: ["matugen", "contrast", "dynamic"]
                settingKey: "matugenContrast"
                text: I18n.tr("Contrast", "noun, slider label for color or display contrast")
                value: Math.round(SettingsData.matugenContrast * 100)
                minimum: -100
                maximum: 100
                enabled: Theme.matugenAvailable
                onSliderDragFinished: finalValue => {
                    const clamped = SettingsData.matugenSpec !== "2021" ? Math.max(0, finalValue) : finalValue;
                    SettingsData.setMatugenContrast(clamped / 100);
                    if (clamped !== finalValue)
                        contrastRow.resync();
                }
            }

            SettingsRow {
                visible: Theme.currentThemeName === "custom" && Theme.currentThemeCategory !== "registry"
                body: Column {
                    width: parent.width
                    spacing: Theme.spacingM

                    Row {
                        width: parent.width
                        spacing: Theme.spacingM

                        DActionButton {
                            buttonSize: Theme.minimumTouchTargetSize
                            iconName: "folder_open"
                            Accessible.name: I18n.tr("Browse Files")
                            iconSize: Theme.iconSize
                            backgroundColor: Theme.primaryHover
                            iconColor: Theme.primary
                            onClicked: fileBrowserModal.open()
                        }

                        DPaletteSwatch {
                            id: customSwatch
                            width: Theme.minimumTouchTargetSize
                            height: Theme.minimumTouchTargetSize
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !!SettingsData.customThemeFile
                            primaryColor: themeColorsTab.currentPalette.primary
                            secondaryColor: themeColorsTab.currentPalette.secondary
                            tertiaryColor: themeColorsTab.currentPalette.tertiary
                        }

                        Column {
                            width: parent.width - Theme.minimumTouchTargetSize - Theme.spacingM - (customSwatch.visible ? customSwatch.width + Theme.spacingM : 0)
                            spacing: Theme.spacingXS
                            anchors.verticalCenter: parent.verticalCenter

                            StyledText {
                                text: SettingsData.customThemeFile ? SettingsData.customThemeFile.split('/').pop() : I18n.tr("No custom theme file", "no custom theme file status")
                                font.pixelSize: Theme.fontSizeLarge
                                color: Theme.surfaceText
                                elide: Text.ElideMiddle
                                maximumLineCount: 1
                                width: parent.width
                            }

                            StyledText {
                                text: SettingsData.customThemeFile || I18n.tr("Click to select a custom theme JSON file", "custom theme file hint")
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                elide: Text.ElideMiddle
                                maximumLineCount: 1
                                width: parent.width
                            }
                        }
                    }
                }
            }

            SettingsRow {
                visible: Theme.currentThemeCategory === "registry"
                body: Column {
                    width: parent.width
                    spacing: Theme.spacingM

                    SettingsSwatchGrid {
                        minTileWidth: SettingsMetrics.previewTileMinWidth
                        visible: themeColorsTab.installedRegistryThemes.length > 0
                        currentValue: themeColorsTab.activeRegistryTheme?.id ?? ""
                        options: themeColorsTab.installedRegistryThemes.map(theme => ({
                                    "value": theme.id,
                                    "label": theme.name,
                                    "deletable": true
                                }))
                        resolveOption: option => {
                            const theme = themeColorsTab.installedRegistryThemes.find(t => t.id === option.value);
                            if (!theme)
                                return {};
                            const mode = Theme.isLightMode ? "light" : "dark";
                            const variant = theme.hasVariants ? SettingsData.getRegistryThemeVariant(theme.id, theme.variants?.default || "") : "";
                            const palette = ThemePalette.pick((Theme.isLightMode ? theme.light : theme.dark) ?? theme.dark) ?? {};
                            const variantCount = theme.variants?.type === "multi" ? theme.variants?.accents?.length : theme.variants?.options?.length;
                            return {
                                "preview": themeColorsTab.registryThemeDir(theme) + "/preview-" + (variant ? variant + "-" : "") + mode + ".svg",
                                "primary": palette.primary ?? Theme.primary.toString(),
                                "secondary": palette.secondary,
                                "tertiary": palette.tertiary,
                                "badge": theme.hasVariants && variantCount ? String(variantCount) : ""
                            };
                        }
                        onSelected: value => {
                            const theme = themeColorsTab.installedRegistryThemes.find(t => t.id === value);
                            if (!theme)
                                return;
                            SettingsData.set("customThemeFile", themeColorsTab.registryThemeDir(theme) + "/theme.json");
                            Theme.switchTheme("custom", true, true);
                        }
                        onDeleteRequested: value => {
                            const theme = themeColorsTab.installedRegistryThemes.find(t => t.id === value);
                            if (!theme)
                                return;
                            uninstallThemeConfirm.showWithOptions({
                                "title": I18n.tr("Uninstall"),
                                "message": I18n.tr("Uninstall %1?", "plugin removal confirmation").arg(theme.name),
                                "confirmText": I18n.tr("Uninstall"),
                                "confirmColor": Theme.error,
                                "onConfirm": () => themeColorsTab.uninstallRegistryTheme(theme)
                            });
                        }
                    }

                    StyledText {
                        text: I18n.tr("No themes installed. Browse themes to install from the registry.", "no registry themes installed hint")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        wrapMode: Text.WordWrap
                        width: parent.width
                        visible: themeColorsTab.installedRegistryThemes.length === 0
                        horizontalAlignment: Text.AlignHCenter
                    }

                    DButton {
                        text: I18n.tr("Browse Themes", "browse themes button")
                        iconName: "store"
                        anchors.horizontalCenter: parent.horizontalCenter
                        onClicked: showThemeBrowser()
                    }
                }
            }

            SettingsRow {
                visible: variantSelector.hasVariants
                body: Column {
                    id: variantSelector
                    width: parent.width
                    spacing: Theme.spacingS
                    readonly property bool hasVariants: activeThemeId !== "" && activeThemeVariants !== null && (isMultiVariant || (activeThemeVariants.options && activeThemeVariants.options.length > 0))

                    property string activeThemeId: {
                        switch (Theme.currentThemeCategory) {
                        case "registry":
                            return themeColorsTab.activeRegistryTheme?.id ?? "";
                        case "custom":
                            return Theme.currentThemeId || "";
                        default:
                            return "";
                        }
                    }
                    property var activeThemeVariants: {
                        if (!activeThemeId)
                            return null;
                        switch (Theme.currentThemeCategory) {
                        case "registry":
                            return themeColorsTab.activeRegistryTheme?.hasVariants ? themeColorsTab.activeRegistryTheme.variants : null;
                        case "custom":
                            return Theme.currentThemeVariants || null;
                        default:
                            return null;
                        }
                    }
                    property bool isMultiVariant: activeThemeVariants?.type === "multi"
                    property string colorMode: Theme.isLightMode ? "light" : "dark"
                    property var multiDefaults: {
                        if (!isMultiVariant || !activeThemeVariants?.defaults)
                            return {};
                        return activeThemeVariants.defaults[colorMode] || activeThemeVariants.defaults.dark || {};
                    }
                    property var storedMulti: activeThemeId ? SettingsData.getRegistryThemeMultiVariant(activeThemeId, multiDefaults, colorMode) : multiDefaults
                    property string selectedFlavor: {
                        var sf = storedMulti.flavor || multiDefaults.flavor || "";
                        for (var i = 0; i < flavorOptions.length; i++) {
                            if (flavorOptions[i].id === sf)
                                return sf;
                        }
                        if (flavorOptions.length > 0)
                            return flavorOptions[0].id;
                        return sf;
                    }
                    property string selectedAccent: storedMulti.accent || multiDefaults.accent || ""
                    property var flavorOptions: {
                        if (!isMultiVariant || !activeThemeVariants?.flavors)
                            return [];
                        return activeThemeVariants.flavors.filter(f => {
                            if (f.mode)
                                return f.mode === colorMode || f.mode === "both";
                            return !!f[colorMode];
                        });
                    }
                    property var flavorNames: flavorOptions.map(f => f.name)
                    property int flavorIndex: {
                        for (var i = 0; i < flavorOptions.length; i++) {
                            if (flavorOptions[i].id === selectedFlavor)
                                return i;
                        }
                        return 0;
                    }
                    property string selectedVariant: activeThemeId ? SettingsData.getRegistryThemeVariant(activeThemeId, activeThemeVariants?.default || "") : ""
                    property var variantNames: {
                        if (!activeThemeVariants?.options)
                            return [];
                        return activeThemeVariants.options.map(v => v.name);
                    }
                    property int selectedIndex: {
                        if (!activeThemeVariants?.options || !selectedVariant)
                            return 0;
                        for (var i = 0; i < activeThemeVariants.options.length; i++) {
                            if (activeThemeVariants.options[i].id === selectedVariant)
                                return i;
                        }
                        return 0;
                    }

                    Item {
                        width: parent.width
                        height: flavorButtonGroup.implicitHeight + Theme.focusRingOffset * 2
                        clip: true
                        visible: variantSelector.isMultiVariant && variantSelector.flavorOptions.length > 1

                        DButtonGroup {
                            id: flavorButtonGroup
                            arrowKeysSelect: false
                            anchors.centerIn: parent
                            property int _count: variantSelector.flavorNames.length
                            property real _maxPerItem: _count > 1 ? (parent.width - (_count - 1) * spacing) / _count : parent.width
                            buttonPadding: _maxPerItem < 55 ? Theme.spacingXS : (_maxPerItem < 75 ? Theme.spacingS : Theme.spacingL)
                            minButtonWidth: Math.min(_maxPerItem < 55 ? 28 : (_maxPerItem < 75 ? 44 : 64), Math.max(28, Math.floor(_maxPerItem)))
                            textSize: _maxPerItem < 55 ? Theme.fontSizeSmall - 2 : (_maxPerItem < 75 ? Theme.fontSizeSmall : Theme.fontSizeMedium)
                            checkEnabled: _maxPerItem >= 55
                            property int pendingIndex: -1
                            model: variantSelector.flavorNames
                            currentIndex: pendingIndex >= 0 ? pendingIndex : variantSelector.flavorIndex
                            selectionMode: "single"
                            onSelectionChanged: (index, selected) => {
                                if (!selected)
                                    return;
                                pendingIndex = index;
                            }
                            onAnimationCompleted: {
                                if (pendingIndex < 0 || pendingIndex >= variantSelector.flavorOptions.length)
                                    return;
                                const flavorId = variantSelector.flavorOptions[pendingIndex]?.id;
                                const idx = pendingIndex;
                                pendingIndex = -1;
                                if (!flavorId || flavorId === variantSelector.selectedFlavor)
                                    return;
                                Theme.screenTransition();
                                SettingsData.setRegistryThemeMultiVariant(variantSelector.activeThemeId, flavorId, variantSelector.selectedAccent, variantSelector.colorMode);
                            }
                        }
                    }

                    Item {
                        width: parent.width
                        height: accentColorsGrid.implicitHeight
                        visible: variantSelector.isMultiVariant && variantSelector.activeThemeVariants?.accents?.length > 0

                        Grid {
                            id: accentColorsGrid
                            property int accentCount: variantSelector.activeThemeVariants?.accents?.length ?? 0
                            property int dotSize: parent.width < 300 ? Theme.buttonHeightXXS : Theme.buttonHeightXS
                            columns: accentCount > 0 ? Math.ceil(accentCount / 2) : 1
                            rowSpacing: Theme.spacingS
                            columnSpacing: Theme.spacingS
                            anchors.horizontalCenter: parent.horizontalCenter

                            Repeater {
                                model: variantSelector.activeThemeVariants?.accents || []

                                DColorButton {
                                    required property var modelData
                                    required property int index
                                    readonly property string accentId: modelData.id

                                    width: accentColorsGrid.dotSize
                                    height: accentColorsGrid.dotSize
                                    swatchColor: modelData.color || modelData[variantSelector.selectedFlavor]?.primary || Theme.primary
                                    selected: accentId === variantSelector.selectedAccent
                                    tooltipText: modelData.name
                                    onClicked: {
                                        if (selected)
                                            return;
                                        Theme.screenTransition();
                                        SettingsData.setRegistryThemeMultiVariant(variantSelector.activeThemeId, variantSelector.selectedFlavor, accentId, variantSelector.colorMode);
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        width: parent.width
                        height: variantButtonGroup.implicitHeight + Theme.focusRingOffset * 2
                        clip: true
                        visible: !variantSelector.isMultiVariant && variantSelector.variantNames.length > 0

                        DButtonGroup {
                            id: variantButtonGroup
                            arrowKeysSelect: false
                            anchors.centerIn: parent
                            property int _count: variantSelector.variantNames.length
                            property real _maxPerItem: _count > 1 ? (parent.width - (_count - 1) * spacing) / _count : parent.width
                            buttonPadding: _maxPerItem < 55 ? Theme.spacingXS : (_maxPerItem < 75 ? Theme.spacingS : Theme.spacingL)
                            minButtonWidth: Math.min(_maxPerItem < 55 ? 28 : (_maxPerItem < 75 ? 44 : 64), Math.max(28, Math.floor(_maxPerItem)))
                            textSize: _maxPerItem < 55 ? Theme.fontSizeSmall - 2 : (_maxPerItem < 75 ? Theme.fontSizeSmall : Theme.fontSizeMedium)
                            checkEnabled: _maxPerItem >= 55
                            property int pendingIndex: -1
                            model: variantSelector.variantNames
                            currentIndex: pendingIndex >= 0 ? pendingIndex : variantSelector.selectedIndex
                            selectionMode: "single"
                            onSelectionChanged: (index, selected) => {
                                if (!selected)
                                    return;
                                pendingIndex = index;
                            }
                            onAnimationCompleted: {
                                if (pendingIndex < 0 || !variantSelector.activeThemeVariants?.options)
                                    return;
                                const variantId = variantSelector.activeThemeVariants.options[pendingIndex]?.id;
                                const idx = pendingIndex;
                                pendingIndex = -1;
                                if (!variantId || variantId === variantSelector.selectedVariant)
                                    return;
                                Theme.screenTransition();
                                SettingsData.setRegistryThemeVariant(variantSelector.activeThemeId, variantId);
                            }
                        }
                    }
                }
            }
        }

        SettingsCard {
            id: textContrastCard
            tab: "theme"
            tags: ["contrast", "ratio", "accessibility", "readability", "terminal", "ansi", "dim", "text", "wcag"]
            title: I18n.tr("Text Contrast Ratios", "theme settings card title, contrast of each generated text color against its background")
            settingKey: "textContrastCard"
            iconName: "contrast"
            collapsible: true
            expanded: false
            visible: Theme.matugenAvailable

            // Rows are rebuilt whenever dms-colors.json reloads, so which one is open lives here, by color.
            property string openKey: ""
            readonly property var rows: expanded ? ContrastFloors.rows(Theme.matugenColors, SettingsData.terminalsAlwaysDark) : []
            readonly property int failures: rows.filter(r => !r.pass).length

            function colorName(key) {
                const info = ContrastFloors.describe(key);
                return info.ansi === undefined ? info.name : I18n.tr("ANSI %1", "text contrast, a terminal palette color by number").arg(info.ansi);
            }

            StyledText {
                width: parent.width
                text: textContrastCard.rows.length === 0 ? I18n.tr("Unavailable") : I18n.tr("%1 of %2 colors below the recommended ratio. Click a color to change it.", "text contrast audit summary").arg(textContrastCard.failures).arg(textContrastCard.rows.length)
                font.pixelSize: Theme.fontSizeSmall
                color: textContrastCard.failures > 0 ? Theme.error : Theme.surfaceVariantText
                wrapMode: Text.WordWrap
            }

            Column {
                width: parent.width
                spacing: Theme.spacingXS

                Repeater {
                    model: textContrastCard.rows

                    Column {
                        id: auditRow
                        required property var modelData
                        readonly property var info: ContrastFloors.describe(modelData.key)
                        readonly property bool open: textContrastCard.openKey === modelData.key
                        readonly property string status: {
                            const parts = [];
                            const change = ContrastFloors.change(modelData);
                            if (change === "own")
                                parts.push(I18n.tr("changed from %1", "text contrast, the theme's own ratio before the user changed it").arg(ContrastFloors.formatRatio(modelData.original)));
                            else if (change === "cause")
                                parts.push(I18n.tr("changed from %1 due to %2 color change", "text contrast, %1 the theme's own ratio, %2 the color it is drawn on that the user changed, e.g. primary").arg(ContrastFloors.formatRatio(modelData.original)).arg(textContrastCard.colorName(modelData.cause)));
                            if (!modelData.pass)
                                parts.push(I18n.tr("below recommended ratio of %1", "text contrast, the ratio this kind of color should reach").arg(ContrastFloors.formatRatio(modelData.recommended)));
                            return parts.join("  ·  ");
                        }

                        width: parent.width
                        spacing: Theme.spacingXS

                        Item {
                            width: parent.width
                            height: Math.max(Theme.buttonHeightS, labels.implicitHeight)

                            Rectangle {
                                id: swatch
                                width: Theme.buttonHeightM
                                height: Theme.buttonHeightS
                                radius: Theme.cornerRadius
                                color: auditRow.modelData.bg
                                anchors.verticalCenter: parent.verticalCenter

                                StyledText {
                                    anchors.centerIn: parent
                                    text: "Aa"
                                    color: auditRow.modelData.fg
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Font.Medium
                                }
                            }

                            Column {
                                id: labels
                                anchors.left: swatch.right
                                anchors.leftMargin: Theme.spacingM
                                anchors.right: ratioText.left
                                anchors.rightMargin: Theme.spacingS
                                anchors.verticalCenter: parent.verticalCenter

                                StyledText {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceText
                                    text: (auditRow.info.group === "terminal" ? I18n.tr("Terminal") : (auditRow.info.group === "editors" ? I18n.tr("Editors", "text contrast audit group, editor themes") : I18n.tr("Applications"))) + "  ·  " + textContrastCard.colorName(auditRow.modelData.key)
                                }

                                StyledText {
                                    width: parent.width
                                    visible: auditRow.status !== ""
                                    wrapMode: Text.WordWrap
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: auditRow.modelData.pass ? Theme.surfaceVariantText : Theme.error
                                    text: auditRow.status
                                }
                            }

                            StyledText {
                                id: ratioText
                                anchors.right: statusIcon.left
                                anchors.rightMargin: Theme.spacingS
                                anchors.verticalCenter: parent.verticalCenter
                                font.pixelSize: Theme.fontSizeSmall
                                color: auditRow.modelData.pass ? Theme.surfaceVariantText : Theme.error
                                text: ContrastFloors.formatRatio(auditRow.modelData.ratio)
                            }

                            DIcon {
                                id: statusIcon
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                name: auditRow.modelData.pass ? "check" : "warning"
                                size: Theme.iconSizeSmall
                                color: auditRow.modelData.pass ? Theme.surfaceVariantText : Theme.error
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: textContrastCard.openKey = auditRow.open ? "" : auditRow.modelData.key
                            }
                        }

                        SettingsSliderRow {
                            id: ratioSlider
                            visible: auditRow.open
                            text: I18n.tr("Ratio for this color", "slider setting one generated text color's contrast ratio")
                            minimum: 10
                            maximum: 210
                            decimals: 1
                            unit: ":1"
                            value: Math.round(auditRow.modelData.ratio * 10)
                            onSliderDragFinished: finalValue => {
                                SettingsData.set("contrastOverrides", ContrastFloors.withOverride(SettingsData.contrastOverrides, auditRow.modelData.key, finalValue / 10));
                                // Show the ratio the color has until regeneration reports the new one; an unreachable value then never sticks.
                                ratioSlider.resync();
                            }
                        }

                        DButton {
                            visible: auditRow.open && auditRow.modelData.target > 0
                            text: I18n.tr("Reset")
                            onClicked: SettingsData.set("contrastOverrides", ContrastFloors.withOverride(SettingsData.contrastOverrides, auditRow.modelData.key, 0))
                        }
                    }
                }
            }
        }

        SettingsCard {
            tab: "theme"
            tags: ["matugen", "startup", "theming"]
            title: I18n.tr("Startup Behavior", "theme settings card title, what happens to the dynamic theme when DMS starts")
            settingKey: "themeStartupBehavior"
            iconName: "power_settings_new"
            visible: Theme.matugenAvailable

            SettingsToggleRow {
                tab: "theme"
                tags: ["matugen", "startup", "generate"]
                settingKey: "generateThemeAtStartup"
                text: I18n.tr("Generate Theme at Startup", "theme settings toggle, rerun matugen on every shell start")
                description: I18n.tr("Regenerate matugen colors when DMS starts, even if nothing changed.", "generate theme at startup toggle description")
                checked: SettingsData.generateThemeAtStartup
                onToggled: checked => SettingsData.set("generateThemeAtStartup", checked)
            }
        }
    }

    FileBrowserModal {
        id: fileBrowserModal
        browserTitle: I18n.tr("Select Custom Theme", "custom theme file browser title")
        bucket: "theme"
        filters: ["*.json"]
        showHiddenFiles: true
        onAccepted: paths => {
            SettingsData.set("customThemeFile", paths[0]);
            Theme.switchTheme("custom");
        }
    }

    LazyLoader {
        id: saveBrowserLoader
        active: false

        FileBrowserSurfaceModal {
            id: saveBrowser

            browserTitle: I18n.tr("Save Extracted Theme", "extract theme save dialog title")
            bucket: "theme"
            filters: ["*.json"]
            mode: "save"
            defaultName: "dms-extracted-theme.json"
            onAccepted: paths => saveExtractedTheme(pendingExtractJson, paths[0])
        }
    }

    LazyLoader {
        id: themeBrowserLoader
        active: false

        ThemeBrowser {
            id: themeBrowserItem
            parentModal: themeColorsTab.parentModal
        }
    }

    property bool _themeBrowserShowQueued: false

    Connections {
        target: themeBrowserLoader

        function onItemChanged() {
            if (!themeColorsTab._themeBrowserShowQueued || !themeBrowserLoader.item)
                return;
            themeColorsTab._themeBrowserShowQueued = false;
            themeBrowserLoader.item.show();
        }
    }

    function showThemeBrowser() {
        themeBrowserLoader.active = true;
        if (themeBrowserLoader.item) {
            themeBrowserLoader.item.show();
            return;
        }
        // LazyLoader can't incubate on its first event-loop tick; show once item lands
        _themeBrowserShowQueued = true;
    }

    FileView {
        id: extractSaveFileView
        blockWrites: true
        preload: false
        atomicWrites: true
        printErrors: true

        onSaved: {
            ToastService.showInfo(I18n.tr("Theme extracted to: %1", "extract theme success").arg(Paths.strip(extractSaveFileView.path)));
        }

        onSaveFailed: error => {
            ToastService.showError(I18n.tr("Failed to extract theme", "extract theme error"));
            log.warn("Failed to write extracted theme to " + extractSaveFileView.path + ": " + error);
        }
    }

    function saveExtractedTheme(json, outputPath) {
        extractSaveFileView.path = outputPath;
        extractSaveFileView.setText(json);
    }

    function uninstallRegistryTheme(theme) {
        ToastService.showInfo(I18n.tr("Uninstalling: %1", "uninstallation progress").arg(theme.name));
        DMSService.uninstallTheme(theme.id, response => {
            if (response.error) {
                ToastService.showError(I18n.tr("Uninstall failed: %1", "uninstallation error").arg(response.error));
                return;
            }
            ToastService.showInfo(I18n.tr("Uninstalled: %1", "uninstallation success").arg(theme.name));
            DMSService.listInstalledThemes();
        });
    }

    ConfirmDialogOverlay {
        id: uninstallThemeConfirm
        parent: themeColorsTab.parentModal?.modalFocusScope ?? themeColorsTab
    }
}
