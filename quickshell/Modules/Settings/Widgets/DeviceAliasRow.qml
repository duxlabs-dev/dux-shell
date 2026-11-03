pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets

SettingsRow {
    id: root

    required property var deviceNode
    property string deviceType: "output"
    property bool showHideButton: false
    property bool isHidden: false

    readonly property bool hasCustomAlias: AudioService.hasDeviceAlias(deviceNode?.name ?? "")
    readonly property string displayedName: AudioService.displayName(deviceNode)

    signal editRequested(var deviceNode)
    signal hideRequested(var deviceNode)

    title: displayedName
    subtitle: hasCustomAlias ? I18n.tr("Original: %1").arg(AudioService.originalName(deviceNode)) : (deviceNode?.name ?? "")
    iconName: deviceType === "input" ? "mic" : "speaker"
    trailingBadge: hasCustomAlias ? I18n.tr("Custom") : ""
    modified: hasCustomAlias
    onResetRequested: AudioService.removeDeviceAlias(deviceNode.name)

    DActionButton {
        visible: root.showHideButton
        iconName: root.isHidden ? "visibility" : "visibility_off"
        iconSize: Theme.iconSizeMedium
        tooltipText: root.isHidden ? I18n.tr("Show device") : I18n.tr("Hide device")
        onClicked: root.hideRequested(root.deviceNode)
    }

    DActionButton {
        visible: !root.isHidden
        iconName: "edit"
        iconSize: Theme.iconSizeMedium
        tooltipText: I18n.tr("Set custom name")
        onClicked: root.editRequested(root.deviceNode)
    }
}
