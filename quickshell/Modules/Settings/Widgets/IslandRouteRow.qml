import QtQuick
import qs.Common

SettingsToggleRow {
    id: root

    required property var store
    required property string activity
    property bool hosted: false
    readonly property string routeKey: SettingsData.islandRouteKey(root.activity)

    tags: ["island", "routing", "shortcuts", "ipc"]
    visible: root.hosted || SettingsData.islandSharedRoutingMode(root.store.config) !== "always"
    checked: root.hosted ? SettingsData.islandActivityRoutingMode(root.store.config, root.activity) === "always" : root.store.setting(root.routeKey) === "island"
    onToggled: checked => root.store.apply(root.routeKey, checked ? "island" : (root.hosted ? "bar" : "follow"))
}
