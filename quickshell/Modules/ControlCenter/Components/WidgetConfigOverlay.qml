pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Modules.ControlCenter
import qs.Modules.ControlCenter.Widgets
import qs.Modules.DBar.Widgets
import qs.Modules.DDash
import "../utils/widgets.js" as WidgetUtils
import "../../../Common/QmlUtils.js" as QmlUtils
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets

Item {
    id: root

    property int widgetIndex: -1
    property var transientSurfaceTracker: null
    property Item hostItem: null
    property Item _anchor: null

    readonly property var widgetData: {
        if (widgetIndex < 0)
            return null;
        const widgets = SettingsData.controlCenterWidgets || [];
        return widgets[widgetIndex] || null;
    }
    readonly property string widgetId: String(widgetData?.id ?? "")
    readonly property bool isPlugin: widgetId.startsWith("plugin_")
    readonly property bool isDisk: widgetId === "diskUsage"
    readonly property bool isIdleInhibitor: widgetId === "idleInhibitor"
    readonly property bool isUser: widgetId === "user"
    readonly property bool isGroup: widgetId === WidgetUtils.GROUP_ID
    readonly property bool isBrightness: widgetId === "brightnessSlider"
    readonly property bool isSlider: WidgetUtils.isSliderWidget(widgetId)
    // Same order as WidgetUtils.USER_SHAPES.
    readonly property var shapeLabels: [I18n.tr("Circle", "icon shape"), I18n.tr("4-sided cookie", "avatar shape"), I18n.tr("7-sided cookie", "avatar shape"), I18n.tr("12-sided cookie", "avatar shape"), I18n.tr("4-leaf clover", "avatar shape"), I18n.tr("8-leaf clover", "avatar shape"), I18n.tr("Sunny", "avatar shape, a circle with soft rays"), I18n.tr("Pentagon", "avatar shape"), I18n.tr("Arch", "avatar shape"), I18n.tr("Slanted", "Album artwork shape"), I18n.tr("Gem", "avatar shape"), I18n.tr("Squircle", "icon shape"), I18n.tr("Rounded square", "icon shape"), I18n.tr("Square", "icon shape")]
    // Grouped tiles have no menu of their own, so the group's menu styles its battery.
    readonly property int batteryIndex: {
        if (widgetId === "battery")
            return widgetIndex;
        if (!isGroup)
            return -1;
        return WidgetUtils.groupMembers(SettingsData.controlCenterWidgets || [], widgetData.instanceId).find(member => member.widget.id === "battery")?.index ?? -1;
    }

    visible: widgetIndex >= 0 || contextMenu.renderActive

    function open(index, data, anchorItem, boundsItem) {
        // Attached once widgetIndex settles; built earlier, the rows read stale data and their toggles slide.
        contextMenu.customContent = null;
        widgetIndex = index;
        contextMenu.customContent = optionsContent;
        // Refocus only an anchor that had focus, or a right-clicked tile keeps its edit chrome.
        _anchor = anchorItem?.activeFocus ? anchorItem : null;
        // Placement needs the final menu height, which settles after widgetIndex propagates.
        Qt.callLater(() => {
            const window = root.QsWindow.window;
            const pos = QmlUtils.screenPointOf(window, boundsItem, 0, 0);
            const hostItem = root.hostItem;
            const hostPos = hostItem ? QmlUtils.screenPointOf(window, hostItem, 0, 0) : null;
            if (root.widgetIndex !== index || !pos)
                return;
            const screen = window.screen;
            const menuW = contextMenu.effectiveMenuWidth;
            const menuH = contextMenu.effectiveMenuHeight;
            const idealX = I18n.isRtl ? pos.x : pos.x + boundsItem.width - menuW;
            const minX = hostPos ? hostPos.x + Theme.spacingS : Theme.spacingS;
            const maxX = hostPos ? Math.max(minX, hostPos.x + hostItem.width - Theme.spacingS - menuW) : idealX;
            const menuX = Math.max(minX, Math.min(maxX, idealX));

            const belowY = pos.y + boundsItem.height + Theme.spacingS;
            const aboveY = () => pos.y - contextMenu.effectiveMenuHeight - Theme.spacingS;
            const spaceAbove = hostPos ? pos.y - hostPos.y - Theme.spacingS : pos.y - Theme.spacingS;
            const spaceBelow = hostPos ? (hostPos.y + hostItem.height) - (pos.y + boundsItem.height) - Theme.spacingS : (screen?.height ?? 0) - belowY;
            const needed = menuH + Theme.spacingS;
            const fitsBelow = spaceBelow >= needed;
            const fitsAbove = spaceAbove >= needed;

            let placeBelow;
            if (fitsBelow || fitsAbove) {
                placeBelow = fitsBelow && (!fitsAbove || spaceBelow >= spaceAbove);
            } else {
                const screenBelow = (screen?.height ?? 0) - belowY;
                const screenAbove = pos.y - Theme.spacingS;
                placeBelow = screenBelow >= screenAbove;
            }

            if (placeBelow) {
                contextMenu.open(screen, menuX, belowY, false);
                return;
            }
            contextMenu.open(screen, menuX, aboveY(), false);
            contextMenu.anchorY = Qt.binding(aboveY);
        });
    }

    function close() {
        if (!contextMenu.renderActive) {
            contextMenu.customContent = null;
            widgetIndex = -1;
            _anchor = null;
            return;
        }
        contextMenu.hide();
    }

    function persistOption(key, value) {
        WidgetUtils.setOption(widgetIndex, key, value);
    }

    DContextMenu {
        id: contextMenu
        layerNamespace: "dms:control-center-widget-options"
        minMenuWidth: CcMetrics.configMenuWidth
        customContentWidth: CcMetrics.configMenuWidth
        keyboardNavigable: true
        transientSurfaceTracker: root.transientSurfaceTracker

        onOpenStateChanged: {
            if (openState)
                return;
            if (root._anchor?.visible && root._anchor.enabled)
                root._anchor.forceActiveFocus();
            root._anchor = null;
        }
        // Cleared after the close fade, so the rows never fall back to defaults on screen.
        onRenderActiveChanged: {
            if (renderActive)
                return;
            customContent = null;
            root.widgetIndex = -1;
        }

        Component {
            id: optionsContent

            CcGroup {
                CcListRow {
                    visible: root.isPlugin
                    iconName: "settings"
                    title: I18n.tr("Plugin settings")
                    clickable: true
                    onClicked: {
                        PopoutService.openSettingsWithTab(SettingsTabs.pluginPrefix + root.widgetId.replace("plugin_", ""));
                        root.close();
                    }
                }

                CcListRow {
                    readonly property string shape: root.widgetData?.shape ?? WidgetUtils.USER_SHAPES[0]

                    visible: root.isUser
                    iconName: "interests"
                    title: I18n.tr("Change shape", "control center user avatar shape option")
                    subtitle: root.shapeLabels[WidgetUtils.USER_SHAPES.indexOf(shape)] ?? ""
                    clickable: true
                    showChevron: true
                    onClicked: root.persistOption("shape", WidgetUtils.nextUserShape(shape))
                }

                CcToggleRow {
                    visible: root.isUser || root.isGroup
                    text: I18n.tr("Background")
                    checked: root.isUser ? root.widgetData?.background === true : root.widgetData?.background !== false
                    onToggled: checked => root.persistOption("background", checked)
                }

                CcListRow {
                    visible: root.batteryIndex >= 0
                    iconName: "battery_std"
                    title: I18n.tr("Battery style")
                    body: DDropdown {
                        readonly property var labels: [I18n.tr("Icon", "battery widget: system battery glyph"), I18n.tr("Solid", "island settings: filled battery meter style"), I18n.tr("Outline", "island settings: outlined battery meter style"), I18n.tr("Circle", "island settings: circular battery meter style"), I18n.tr("Duo", "battery meter style: open battery arc around the network glyph")]

                        compactMode: true
                        dropdownWidth: parent.width
                        transientSurfaceTracker: contextMenu.transientSurfaceTracker
                        currentValue: labels[Math.max(0, WidgetUtils.BATTERY_STYLES.indexOf(SettingsData.controlCenterWidgets[root.batteryIndex]?.batteryStyle ?? "icon"))]
                        options: labels
                        onValueChanged: value => {
                            const style = WidgetUtils.BATTERY_STYLES[labels.indexOf(value)];
                            if (style)
                                WidgetUtils.setOption(root.batteryIndex, "batteryStyle", style);
                        }
                    }
                }

                CcListRow {
                    visible: root.batteryIndex >= 0 && (SettingsData.controlCenterWidgets[root.batteryIndex]?.batteryStyle ?? "icon") !== "icon"
                    iconName: "palette"
                    title: I18n.tr("Color")
                    body: DDropdown {
                        readonly property var labels: [I18n.tr("Theme", "battery settings: theme accent indicator colors"), I18n.tr("Level", "battery settings: charge level indicator colors")]

                        compactMode: true
                        dropdownWidth: parent.width
                        transientSurfaceTracker: contextMenu.transientSurfaceTracker
                        currentValue: labels[(SettingsData.controlCenterWidgets[root.batteryIndex]?.batteryColorMode ?? "level") === "level" ? 1 : 0]
                        options: labels
                        onValueChanged: value => WidgetUtils.setOption(root.batteryIndex, "batteryColorMode", labels.indexOf(value) === 1 ? "level" : "theme")
                    }
                }

                Repeater {
                    model: root.isUser ? DashRegistry.sheetOptionSpecs("user") : []

                    CcToggleRow {
                        required property var modelData

                        text: modelData.text
                        checked: DashRegistry.optionValue(modelData, root.widgetData?.[modelData.key])
                        onToggled: checked => root.persistOption(modelData.key, checked)
                    }
                }

                CcListRow {
                    visible: root.isBrightness
                    iconName: "brightness_6"
                    title: I18n.tr("Device")
                    body: DDropdown {
                        readonly property var devices: root.isBrightness ? (BrightnessService.devices || []) : []
                        readonly property var names: [""].concat(devices.map(device => device.name))

                        compactMode: true
                        dropdownWidth: parent.width
                        transientSurfaceTracker: contextMenu.transientSurfaceTracker
                        currentValue: options[Math.max(0, names.indexOf(root.widgetData?.deviceName ?? ""))]
                        options: [I18n.tr("Auto")].concat(devices.map(device => BrightnessService.deviceTitle(device)))
                        onValueChanged: value => {
                            const index = options.indexOf(value);
                            if (index >= 0)
                                root.persistOption("deviceName", names[index]);
                        }
                    }
                }

                CcListRow {
                    visible: root.isSlider
                    iconName: "tune"
                    title: I18n.tr("Style")
                    body: DDropdown {
                        // Same order as WidgetUtils.SLIDER_STYLES.
                        readonly property var labels: [I18n.tr("Default", "widget style option"), I18n.tr("Expressive")]

                        compactMode: true
                        dropdownWidth: parent.width
                        transientSurfaceTracker: contextMenu.transientSurfaceTracker
                        currentValue: labels[Math.max(0, WidgetUtils.SLIDER_STYLES.indexOf(root.widgetData?.sliderStyle ?? "default"))]
                        options: labels
                        onValueChanged: value => {
                            const style = WidgetUtils.SLIDER_STYLES[labels.indexOf(value)];
                            if (style)
                                root.persistOption("sliderStyle", style);
                        }
                    }
                }

                CcToggleRow {
                    visible: root.isDisk
                    text: I18n.tr("Show mount path", "toggle in control center disk usage widget to turn mount path display on or off")
                    checked: root.widgetData?.showMountPath !== false
                    onToggled: checked => root.persistOption("showMountPath", checked)
                }

                CcListRow {
                    visible: root.isIdleInhibitor
                    iconName: "timer"
                    title: I18n.tr("Duration")
                    body: DDropdown {
                        readonly property var presets: IdleInhibitPresets.presetOptions

                        compactMode: true
                        dropdownWidth: parent.width
                        transientSurfaceTracker: contextMenu.transientSurfaceTracker
                        currentValue: presets.find(p => p.minutes === (root.widgetData?.durationMinutes ?? 0))?.label ?? ""
                        options: presets.map(p => p.label)
                        onValueChanged: value => {
                            const preset = presets.find(p => p.label === value);
                            if (preset)
                                root.persistOption("durationMinutes", preset.minutes);
                        }
                    }
                }
            }
        }
    }
}
