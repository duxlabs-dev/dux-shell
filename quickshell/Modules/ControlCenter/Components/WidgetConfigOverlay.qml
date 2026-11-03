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
    // Grouped tiles have no menu of their own, so the group's menu styles its battery.
    readonly property int batteryIndex: {
        if (widgetId === "battery")
            return widgetIndex;
        if (!isGroup)
            return -1;
        return WidgetUtils.groupMembers(SettingsData.controlCenterWidgets || [], widgetData.instanceId).find(member => member.widget.id === "battery")?.index ?? -1;
    }

    visible: widgetIndex >= 0 || contextMenu.renderActive

    function open(index, data, anchorItem) {
        widgetIndex = index;
        _anchor = anchorItem;
        // Placement needs the final menu height, which settles after widgetIndex propagates.
        Qt.callLater(() => {
            const window = root.QsWindow.window;
            const pos = QmlUtils.screenPointOf(window, anchorItem, 0, 0);
            if (root.widgetIndex !== index || !pos)
                return;
            const screen = window.screen;
            const x = pos.x;
            const y = pos.y;
            const menuX = I18n.isRtl ? x : x + anchorItem.width - contextMenu.effectiveMenuWidth;
            const aboveY = () => y - contextMenu.effectiveMenuHeight - Theme.spacingS;
            if (aboveY() < Theme.spacingS) {
                contextMenu.open(screen, menuX, y + anchorItem.height + Theme.spacingS, false);
                return;
            }
            contextMenu.open(screen, menuX, aboveY(), false);
            contextMenu.anchorY = Qt.binding(aboveY);
        });
    }

    function close() {
        if (!contextMenu.renderActive) {
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
            root.widgetIndex = -1;
            if (root._anchor?.visible && root._anchor.enabled)
                root._anchor.forceActiveFocus();
            root._anchor = null;
        }

        customContent: Component {
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
