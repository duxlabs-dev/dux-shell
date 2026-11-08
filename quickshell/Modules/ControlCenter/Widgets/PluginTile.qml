import QtQuick
import qs.Common
import qs.Services

CcTile {
    id: root

    readonly property string widgetId: widgetData.id || ""
    readonly property bool isBuiltin: widgetId.startsWith("builtin_")
    readonly property string pluginId: isBuiltin ? "" : widgetId.replace("plugin_", "")
    readonly property var instance: isBuiltin ? (host?.model?.builtinInstances[widgetId] ?? null) : pluginHost.instance
    readonly property bool hasDetail: (instance?.ccDetailContent ?? null) !== null

    iconName: instance?.ccWidgetIcon || widgetDef?.icon || "extension"
    title: instance?.ccWidgetPrimaryText || widgetDef?.text || I18n.tr("Plugin")
    subtitle: instance?.ccWidgetSecondaryText || ""
    // Primary text can be generic ("Display"); the registered name always identifies the plugin.
    denseTitle: widgetDef?.text ?? ""
    active: instance?.ccWidgetIsActive ?? false
    toggle: instance?.ccWidgetIsToggle ?? true
    showExpand: hasDetail
    opensPage: (!toggle || compact) && hasDetail
    expandedContent: instance?.ccExpandedContent ?? null
    expandedMinimumHeight: instance?.ccExpandedMinimumHeight ?? Theme.listItemHeight
    available: instance !== null

    onClicked: {
        if ((compact || !toggle) && hasDetail) {
            expandClicked();
            return;
        }
        instance?.ccWidgetToggled();
    }

    onExpandClicked: instance?.ccWidgetExpanded()

    PluginInstanceHost {
        id: pluginHost
        pluginId: root.pluginId
    }
}
