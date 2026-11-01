import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

SettingsCard {
    id: root

    property string outputName: ""
    property var outputData: null
    readonly property bool isDisabled: {
        void (DisplayConfigState.pendingNiriChanges);
        return DisplayConfigState.getNiriSetting(root.outputData, root.outputName, "disabled", false);
    }

    title: I18n.tr("Compositor", "noun, wayland compositor, section title and launcher logo option fallback")
    collapsible: true
    expanded: false

    SettingsToggleRow {
        text: I18n.tr("Disable output")
        enabled: checked || DisplayConfigState.canDisableOutput()
        description: (!checked && !DisplayConfigState.canDisableOutput()) ? (Object.keys(DisplayConfigState.outputs).length <= 1 ? I18n.tr("Cannot disable the only output") : I18n.tr("At least one output must remain enabled")) : ""
        checked: root.isDisabled
        onToggled: checked => DisplayConfigState.setNiriSetting(root.outputData, root.outputName, "disabled", checked)
    }

    SettingsToggleRow {
        text: I18n.tr("Focus at startup")
        enabled: !root.isDisabled
        checked: DisplayConfigState.getNiriSetting(root.outputData, root.outputName, "focusAtStartup", false)
        onToggled: checked => DisplayConfigState.setNiriSetting(root.outputData, root.outputName, "focusAtStartup", checked)
    }

    SettingsDropdownRow {
        readonly property var depths: [6, 8, 10, 12, 14, 16]

        visible: "max_bpc" in (NiriService.outputs[root.outputName] ?? {})
        enabled: !root.isDisabled
        text: I18n.tr("Max bits per channel", "niri output dropdown, max-bpc sent to the display")
        description: I18n.tr("Lower only if a mode fails for lack of bandwidth")
        currentValue: {
            const value = DisplayConfigState.getNiriSetting(root.outputData, root.outputName, "maxBpc", null);
            return depths.includes(value) ? value.toString() : I18n.tr("Default");
        }
        options: [I18n.tr("Default")].concat(depths.map(d => d.toString()))
        onValueChanged: value => {
            const depth = parseInt(value);
            DisplayConfigState.setNiriSetting(root.outputData, root.outputName, "maxBpc", depths.includes(depth) ? depth : null);
        }
    }

    SettingsNiriLink {
        section: "gestures"
        hint: I18n.tr("Gestures", "niri page section")
    }

    SettingsRow {
        title: I18n.tr("Layout overrides")
        enabled: !root.isDisabled

        body: Column {
            width: parent.width
            spacing: Theme.spacingM

            Row {
                width: parent.width
                spacing: Theme.spacingM

                DTextField {
                    outlined: true
                    leftIconName: "space_dashboard"
                    labelText: I18n.tr("Window gaps (px)")
                    width: (parent.width - parent.spacing) / 2
                    placeholderText: I18n.tr("Inherit", "inherit from global setting")
                    text: {
                        const layout = DisplayConfigState.getNiriSetting(root.outputData, root.outputName, "layout", null);
                        if (layout?.gaps === undefined)
                            return "";
                        return layout.gaps.toString();
                    }
                    onEditingFinished: {
                        const layout = DisplayConfigState.getNiriSetting(root.outputData, root.outputName, "layout", {}) || {};
                        const trimmed = text.trim();
                        if (!trimmed) {
                            delete layout.gaps;
                            DisplayConfigState.setNiriSetting(root.outputData, root.outputName, "layout", Object.keys(layout).length > 0 ? layout : null);
                            return;
                        }
                        const val = parseInt(trimmed);
                        if (isNaN(val) || val < 0)
                            return;
                        layout.gaps = val;
                        DisplayConfigState.setNiriSetting(root.outputData, root.outputName, "layout", layout);
                    }
                }

                DTextField {
                    outlined: true
                    leftIconName: "width_normal"
                    labelText: I18n.tr("Default width (%)", "niri output field label, default column width percent")
                    width: (parent.width - parent.spacing) / 2
                    placeholderText: I18n.tr("Inherit", "inherit from global setting")
                    text: {
                        const layout = DisplayConfigState.getNiriSetting(root.outputData, root.outputName, "layout", null);
                        if (!layout?.defaultColumnWidth)
                            return "";
                        if (layout.defaultColumnWidth.type !== "proportion")
                            return "";
                        const percent = layout.defaultColumnWidth.value * 100;
                        return parseFloat(percent.toFixed(4)).toString();
                    }
                    onEditingFinished: {
                        const layout = DisplayConfigState.getNiriSetting(root.outputData, root.outputName, "layout", {}) || {};
                        const trimmed = text.trim().replace("%", "");
                        if (!trimmed) {
                            delete layout.defaultColumnWidth;
                            DisplayConfigState.setNiriSetting(root.outputData, root.outputName, "layout", Object.keys(layout).length > 0 ? layout : null);
                            return;
                        }
                        const val = parseFloat(trimmed);
                        if (isNaN(val) || val <= 0 || val > 100)
                            return;
                        layout.defaultColumnWidth = {
                            "type": "proportion",
                            "value": parseFloat((val / 100).toFixed(6))
                        };
                        DisplayConfigState.setNiriSetting(root.outputData, root.outputName, "layout", layout);
                    }
                }
            }

            DTextField {
                outlined: true
                leftIconName: "view_column"
                labelText: I18n.tr("Preset widths (%)", "niri output field label, preset column width percents")
                supportingText: "33.33, 50, 66.67"
                width: parent.width
                placeholderText: I18n.tr("Inherit", "inherit from global setting")
                text: {
                    const layout = DisplayConfigState.getNiriSetting(root.outputData, root.outputName, "layout", null);
                    const presets = layout?.presetColumnWidths || [];
                    if (presets.length === 0)
                        return "";
                    return presets.filter(p => p.type === "proportion").map(p => parseFloat((p.value * 100).toFixed(4))).join(", ");
                }
                onEditingFinished: {
                    const layout = DisplayConfigState.getNiriSetting(root.outputData, root.outputName, "layout", {}) || {};
                    const trimmed = text.trim();
                    if (!trimmed) {
                        delete layout.presetColumnWidths;
                        DisplayConfigState.setNiriSetting(root.outputData, root.outputName, "layout", Object.keys(layout).length > 0 ? layout : null);
                        return;
                    }
                    const parts = trimmed.split(/[,\s]+/).filter(s => s);
                    const presets = [];
                    for (const part of parts) {
                        const val = parseFloat(part.replace("%", ""));
                        if (!isNaN(val) && val > 0 && val <= 100)
                            presets.push({
                                "type": "proportion",
                                "value": parseFloat((val / 100).toFixed(6))
                            });
                    }
                    if (presets.length === 0) {
                        delete layout.presetColumnWidths;
                        DisplayConfigState.setNiriSetting(root.outputData, root.outputName, "layout", Object.keys(layout).length > 0 ? layout : null);
                        return;
                    }
                    presets.sort((a, b) => a.value - b.value);
                    layout.presetColumnWidths = presets;
                    DisplayConfigState.setNiriSetting(root.outputData, root.outputName, "layout", layout);
                }
            }
        }
    }

    SettingsToggleRow {
        text: I18n.tr("Center single column")
        enabled: !root.isDisabled
        property var layoutData: DisplayConfigState.getNiriSetting(root.outputData, root.outputName, "layout", null)
        checked: layoutData?.alwaysCenterSingleColumn ?? false
        onToggled: checked => {
            const layout = DisplayConfigState.getNiriSetting(root.outputData, root.outputName, "layout", {}) || {};
            if (checked) {
                layout.alwaysCenterSingleColumn = true;
            } else {
                delete layout.alwaysCenterSingleColumn;
            }
            DisplayConfigState.setNiriSetting(root.outputData, root.outputName, "layout", Object.keys(layout).length > 0 ? layout : null);
        }
    }
}
