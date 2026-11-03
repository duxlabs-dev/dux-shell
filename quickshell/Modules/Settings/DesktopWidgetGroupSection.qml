pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

Column {
    id: section

    required property var reorderGroup
    property var groupId: null
    property string groupName: ""
    property bool isUngrouped: false
    property bool showHeader: true
    property bool collapsed: false
    property var instances: []

    readonly property string sectionKey: groupId ? groupId : ""
    readonly property bool dragActive: reorderGroup.active
    readonly property bool isDropTarget: dragActive && reorderGroup.target === cardsList

    signal collapseToggled(string key)
    signal configureRequested(string instanceId, string title)
    signal duplicateRequested(string instanceId)
    signal deleteRequested(string instanceId)

    width: parent.width
    spacing: Theme.spacingM

    SettingsRow {
        title: section.groupName
        iconName: section.isUngrouped ? "widgets" : "folder"
        trailingBadge: section.instances.length.toString()
        visible: section.showHeader
        rowColor: section.isDropTarget ? Theme.selectedContainer : SettingsMetrics.rowColor
        clickable: true
        onClicked: section.collapseToggled(section.sectionKey)

        DIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: section.collapsed ? "expand_more" : "expand_less"
            size: Theme.iconSize
            color: Theme.onSurfaceVariant
        }
    }

    Item {
        id: bodyContainer

        width: parent.width
        height: section.collapsed ? 0 : Math.max(cardsList.height, emptyDropZone.visible ? emptyDropZone.height : 0)
        visible: !section.collapsed
        clip: false

        SettingsReorderList {
            id: cardsList

            model: section.instances
            group: section.reorderGroup
            groupKey: section.sectionKey
            dropArea: section
            onReordered: indices => {
                const ordered = indices.map(i => section.instances[i]);
                const ids = new Set(ordered.map(item => item.id));
                let index = 0;
                SettingsData.set("desktopWidgetInstances", SettingsData.desktopWidgetInstances.map(item => ids.has(item.id) ? ordered[index++] : item));
            }

            delegate: DesktopWidgetInstanceCard {
                required property var modelData

                reorderList: cardsList
                instanceData: modelData
                opacity: dragging && cardsList.crossSectionActive ? 0 : 1

                onConfigureRequested: section.configureRequested(instanceId, widgetName)
                onDuplicateRequested: section.duplicateRequested(instanceId)
                onDeleteRequested: section.deleteRequested(instanceId)
            }
        }

        Rectangle {
            id: emptyDropZone
            width: parent.width
            height: Theme.listItemHeight
            radius: Theme.groupedListOuterRadius
            visible: section.dragActive && section.instances.length === 0
            color: section.isDropTarget ? Theme.selectedContainer : "transparent"
            border.width: Theme.outlineWidth
            border.color: section.isDropTarget ? Theme.primary : Theme.outline

            StyledText {
                anchors.centerIn: parent
                text: I18n.tr("Drop here")
                font.pixelSize: Theme.fontSizeSmall
                color: section.isDropTarget ? Theme.onSelectedContainer : Theme.surfaceVariantText
            }
        }
    }
}
