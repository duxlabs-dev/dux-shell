import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import qs.Modules.Settings.Widgets

Column {
    id: root

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    signal requestICCBrowse(string outputName)
    signal requestICCInfo(string outputName)

    required property string outputName
    required property var outputData
    readonly property bool isConnected: outputData?.connected ?? false
    readonly property bool isDisabled: {
        void (DisplayConfigState.pendingHyprlandChanges);
        void (DisplayConfigState.pendingNiriChanges);
        if (!root.isConnected)
            return false;
        if (CompositorService.isHyprland)
            return DisplayConfigState.getHyprlandSetting(root.outputData, root.outputName, "disabled", false);
        if (CompositorService.isNiri)
            return DisplayConfigState.getNiriSetting(root.outputData, root.outputName, "disabled", false);
        return false;
    }
    readonly property bool isActive: isConnected && !isDisabled
    readonly property bool vrrSupported: DisplayConfigState.outputs[outputName]?.vrr_supported ?? false
    readonly property bool hasColorControls: isActive && ICCService.outputNames.indexOf(outputName) !== -1
    readonly property int neutralTemperature: 7000

    width: parent?.width ?? 0
    spacing: Theme.spacingS

    SettingsCard {
        width: parent.width
        title: DisplayConfigState.getOutputDisplayName(root.outputData, root.outputName)

        SettingsRow {
            iconName: root.isActive ? "desktop_windows" : "desktop_access_disabled"
            iconColor: root.isActive ? Theme.primary : Theme.surfaceVariantText
            title: [root.outputData?.model, root.outputData?.make].filter(part => !!part).join(" - ") || root.outputName
            subtitle: {
                if (!root.isConnected)
                    return I18n.tr("Configuration will be preserved when this display reconnects");
                if (root.isDisabled)
                    return I18n.tr("This output is disabled in the current profile");
                return "";
            }
            trailingBadge: {
                if (!root.isConnected)
                    return I18n.tr("Disconnected");
                if (root.isDisabled)
                    return I18n.tr("Disabled");
                return "";
            }

            DActionButton {
                visible: !root.isConnected
                buttonSize: Theme.iconButtonSize
                iconName: "delete"
                iconSize: Theme.iconSizeMedium
                iconColor: Theme.error
                Accessible.name: I18n.tr("Delete")
                anchors.verticalCenter: parent.verticalCenter
                onClicked: DisplayConfigState.deleteDisconnectedOutput(root.outputName)
            }
        }

        SettingsDropdownRow {
            visible: root.isActive
            text: I18n.tr("Resolution & refresh")
            currentValue: {
                const pendingMode = DisplayConfigState.getPendingValue(root.outputName, "mode");
                if (pendingMode)
                    return pendingMode;
                const data = DisplayConfigState.outputs[root.outputName];
                if (!data?.modes || data?.current_mode === undefined)
                    return "Auto";
                const mode = data.modes[data.current_mode];
                return mode ? DisplayConfigState.formatMode(mode) : "Auto";
            }
            options: {
                const data = DisplayConfigState.outputs[root.outputName];
                if (!data?.modes)
                    return ["Auto"];
                return data.modes.map(mode => DisplayConfigState.formatMode(mode));
            }
            onValueChanged: value => {
                DisplayConfigState.setPendingChange(root.outputName, "mode", value);
                const snapped = DisplayConfigState.snapScale(root.outputName, root.outputData, scaleRow.currentScale);
                if (!isNaN(snapped) && Math.abs(snapped - scaleRow.currentScale) > scaleRow.scaleTolerance)
                    DisplayConfigState.setPendingChange(root.outputName, "scale", snapped);
            }
        }

        SettingsRow {
            id: scaleRow

            readonly property real scaleTolerance: 0.005
            readonly property string customLabel: I18n.tr("Custom", "dropdown option that opens a custom value input") + "…"
            property bool customMode: false
            readonly property real currentScale: {
                const pendingScale = DisplayConfigState.getPendingValue(root.outputName, "scale");
                if (pendingScale !== undefined)
                    return pendingScale;
                return root.outputData?.logical?.scale || 1.0;
            }
            readonly property var scaleOptions: {
                void (DisplayConfigState.pendingChanges);
                const values = DisplayConfigState.getScalePresetValues(root.outputName, root.outputData).concat([currentScale]);
                const valueByLabel = {};
                for (const value of values) {
                    const label = DisplayConfigState.formatScaleOption(root.outputName, root.outputData, value);
                    if (valueByLabel[label] === undefined)
                        valueByLabel[label] = value;
                }
                const labels = Object.keys(valueByLabel).sort((a, b) => valueByLabel[a] - valueByLabel[b]);
                return {
                    "labels": labels.concat([customLabel]),
                    "valueByLabel": valueByLabel
                };
            }
            readonly property string currentLabel: {
                void (DisplayConfigState.pendingChanges);
                return DisplayConfigState.formatScaleOption(root.outputName, root.outputData, currentScale);
            }

            function enterCustomMode() {
                customMode = true;
                scaleInput.text = DisplayConfigState.formatScaleLabel(currentScale);
                scaleInput.forceActiveFocus();
                scaleInput.selectAll();
            }

            function leaveCustomMode() {
                customMode = false;
                scaleDropdown.currentValue = currentLabel;
            }

            function applyCustomScale() {
                if (!customMode)
                    return;
                const snapped = DisplayConfigState.snapScale(root.outputName, root.outputData, parseFloat(scaleInput.text));
                if (!isNaN(snapped))
                    DisplayConfigState.setPendingChange(root.outputName, "scale", snapped);
                leaveCustomMode();
            }

            visible: root.isActive
            title: I18n.tr("Scale")
            onCurrentLabelChanged: scaleDropdown.currentValue = currentLabel

            DDropdown {
                id: scaleDropdown
                downKeyOpens: false
                backgroundColor: SettingsMetrics.controlSurface
                visible: !scaleRow.customMode
                width: Math.min(dropdownWidth, scaleRow.width - SettingsMetrics.rowPaddingH * 2)
                Accessible.name: scaleRow.title
                options: scaleRow.scaleOptions.labels
                focusReturnTarget: scaleRow.customMode ? scaleInput : null
                Component.onCompleted: currentValue = scaleRow.currentLabel
                onValueChanged: value => {
                    if (value === scaleRow.customLabel) {
                        scaleRow.enterCustomMode();
                        return;
                    }
                    const mapped = scaleRow.scaleOptions.valueByLabel[value];
                    if (mapped !== undefined)
                        DisplayConfigState.setPendingChange(root.outputName, "scale", mapped);
                }
            }

            DTextField {
                id: scaleInput
                visible: scaleRow.customMode
                outlined: true
                leftIconName: "zoom_in"
                width: scaleDropdown.width
                placeholderText: "0.25 - 4"
                Accessible.name: scaleRow.title
                onAccepted: scaleRow.applyCustomScale()
                onEditingFinished: scaleRow.applyCustomScale()
                Keys.onEscapePressed: scaleRow.leaveCustomMode()
            }
        }

        SettingsDropdownRow {
            visible: root.isActive
            text: I18n.tr("Transform", "noun, display rotation and flip dropdown label")
            currentValue: {
                const pendingTransform = DisplayConfigState.getPendingValue(root.outputName, "transform");
                if (pendingTransform)
                    return DisplayConfigState.getTransformLabel(pendingTransform);
                return DisplayConfigState.getTransformLabel(root.outputData?.logical?.transform ?? "Normal");
            }
            options: [I18n.tr("Normal", "display rotation option", true), "90°", "180°", "270°", I18n.tr("Flipped", "display transform option, mirrored output"), I18n.tr("Flipped 90°"), I18n.tr("Flipped 180°"), I18n.tr("Flipped 270°")]
            onValueChanged: value => DisplayConfigState.setPendingChange(root.outputName, "transform", DisplayConfigState.getTransformValue(value))
        }

        SettingsToggleRow {
            visible: root.isActive && root.vrrSupported && !CompositorService.isHyprland && !CompositorService.isNiri
            text: I18n.tr("Variable refresh rate")
            checked: {
                const pendingVrr = DisplayConfigState.getPendingValue(root.outputName, "vrr");
                if (pendingVrr !== undefined)
                    return pendingVrr;
                return DisplayConfigState.outputs[root.outputName]?.vrr_enabled ?? false;
            }
            onToggled: checked => DisplayConfigState.setPendingChange(root.outputName, "vrr", checked)
        }

        SettingsDropdownRow {
            readonly property var hyprlandCaps: {
                void (DisplayConfigState.pendingHyprlandChanges);
                return DisplayConfigState.getHyprlandCaps(root.outputData, root.outputName);
            }
            readonly property bool capable: hyprlandCaps?.vrr ?? true
            // Index - 1 is the Lua vrr value; -1 leaves it unset so misc:vrr applies.
            readonly property var modeLabels: [I18n.tr("Default (Global)"), I18n.tr("Off"), I18n.tr("On", "adjective, enabled state"), I18n.tr("Fullscreen only")]

            visible: root.isActive && CompositorService.isHyprland && (hyprlandCaps !== null || root.vrrSupported)
            enabled: capable
            text: I18n.tr("Variable refresh rate")
            description: capable ? "" : I18n.tr("This display does not report VRR support")
            options: modeLabels
            currentValue: {
                void (DisplayConfigState.pendingHyprlandChanges);
                void (DisplayConfigState.savedParsedOutputs);
                const mode = DisplayConfigState.getHyprlandVrrMode(root.outputData, root.outputName);
                return modeLabels[mode === undefined ? 0 : Math.min(mode, 2) + 1];
            }
            onValueChanged: value => DisplayConfigState.setHyprlandVrrMode(root.outputData, root.outputName, modeLabels.indexOf(value) - 1)
        }

        SettingsDropdownRow {
            visible: root.isActive && root.vrrSupported && CompositorService.isNiri
            text: I18n.tr("Variable refresh rate")
            options: [I18n.tr("Off"), I18n.tr("On"), I18n.tr("On-demand", "variable refresh rate option on niri")]
            currentValue: {
                void (DisplayConfigState.pendingNiriChanges);
                if (DisplayConfigState.getNiriSetting(root.outputData, root.outputName, "vrrOnDemand", false))
                    return I18n.tr("On-demand");
                const pendingVrr = DisplayConfigState.getPendingValue(root.outputName, "vrr");
                const vrrEnabled = pendingVrr !== undefined ? pendingVrr : (DisplayConfigState.outputs[root.outputName]?.vrr_enabled ?? false);
                return vrrEnabled ? I18n.tr("On") : I18n.tr("Off");
            }
            onValueChanged: value => {
                DisplayConfigState.setPendingChange(root.outputName, "vrr", value !== I18n.tr("Off"));
                DisplayConfigState.setNiriSetting(root.outputData, root.outputName, "vrrOnDemand", value === I18n.tr("On-demand") || null);
            }
        }

        SettingsRow {
            id: colorProfileRow

            readonly property var iccInfo: ICCService.status[root.outputName]
            readonly property bool hasProfile: iccInfo !== undefined

            visible: root.hasColorControls
            title: I18n.tr("Color Profile", "Display Config output card label for the per-monitor ICC profile row")
            subtitle: {
                if (!hasProfile)
                    return I18n.tr("No profile", "Display Config output card ICC row when the output has no profile applied");
                return iccInfo.description || iccInfo.path || I18n.tr("Active", "Active");
            }
            subtitleColor: hasProfile ? Theme.success : Theme.surfaceVariantText

            DActionButton {
                visible: colorProfileRow.hasProfile
                buttonSize: Theme.iconButtonSize
                iconName: "info"
                iconSize: Theme.iconSizeMedium
                Accessible.name: I18n.tr("Info")
                anchors.verticalCenter: parent.verticalCenter
                onClicked: root.requestICCInfo(root.outputName)
            }

            DActionButton {
                visible: colorProfileRow.hasProfile
                buttonSize: Theme.iconButtonSize
                iconName: "close"
                iconSize: Theme.iconSizeMedium
                iconColor: Theme.error
                Accessible.name: I18n.tr("Remove")
                anchors.verticalCenter: parent.verticalCenter
                onClicked: ICCService.removeICC(root.outputName)
            }

            DButton {
                text: I18n.tr("Browse", "Browse")
                iconName: "folder_open"
                anchors.verticalCenter: parent.verticalCenter
                onClicked: root.requestICCBrowse(root.outputName)
            }
        }

        SettingsSliderRow {
            readonly property int outputTemperature: ICCService.outputTemps[root.outputName] ?? 0

            visible: root.hasColorControls
            text: I18n.tr("Color Temperature", "Color Temperature")
            description: outputTemperature === 0 ? I18n.tr("Default", "Default") : outputTemperature + "K"
            minimum: 3000
            maximum: 10000
            step: 100
            unit: "K"
            value: outputTemperature === 0 ? root.neutralTemperature : outputTemperature
            modified: outputTemperature !== 0
            resetByKeys: false
            onResetRequested: ICCService.setOutputTemp(root.outputName, 0)
            onSliderDragFinished: finalValue => ICCService.setOutputTemp(root.outputName, finalValue)
        }
    }

    Loader {
        readonly property string compositorSettingsSource: {
            switch (CompositorService.compositor) {
            case "niri":
                return "NiriOutputSettings.qml";
            case "hyprland":
                return "HyprlandOutputSettings.qml";
            default:
                return "";
            }
        }

        width: parent.width
        active: root.isConnected && compositorSettingsSource !== ""
        visible: active
        source: compositorSettingsSource
        onLoaded: {
            item.outputName = root.outputName;
            item.outputData = root.outputData;
        }
    }
}
