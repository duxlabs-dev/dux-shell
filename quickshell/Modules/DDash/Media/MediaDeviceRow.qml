pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

SettingsRow {
    id: root

    required property var node
    property bool selected: false

    signal activated

    title: AudioService.displayName(node)
    // The selected output has nothing to do on click, and its body holds the volume controls.
    clickable: !selected
    paddingH: Theme.spacingL
    paddingV: Theme.spacingL
    rowColor: selected ? Theme.selectedContainer : Theme.chipSurface
    titleColor: selected ? Theme.onSelectedContainer : Theme.surfaceText
    subtitleColor: titleColor
    topRadius: Theme.cornerRadiusLIncreased
    bottomRadius: Theme.cornerRadiusLIncreased
    Accessible.selected: selected
    onClicked: activated()

    leading: Rectangle {
        width: Theme.iconButtonSize
        height: width
        radius: Theme.fullRadius(width, height)
        color: root.selected ? Theme.onPrimary : Theme.chipSurfaceNested

        DIcon {
            anchors.centerIn: parent
            name: AudioService.sinkIcon(root.node)
            size: Theme.iconSizeMedium
            color: root.selected ? Theme.onSelectedContainer : Theme.onSurfaceVariant
        }
    }

    body: Loader {
        width: parent.width
        active: root.selected && !!root.node?.audio
        visible: active

        sourceComponent: MediaSinkVolume {
            node: root.node
            label: root.title
            contentColor: root.titleColor
        }
    }
}
