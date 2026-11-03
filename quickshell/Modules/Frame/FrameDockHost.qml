pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Modules.Dock
import qs.Services

Item {
    id: host

    required property var frameWindow
    required property var targetScreen

    readonly property string screenName: targetScreen ? targetScreen.name : ""
    // Every dock this screen shows that the frame is allowed to host, one per edge.
    readonly property var configs: {
        SettingsData.dockConfigs;
        SettingsData.barConfigs;
        return SettingsData.dockConfigsForScreen(targetScreen).filter(config => CompositorService.frameHostsDockForConfig(host.targetScreen, config));
    }
    readonly property bool interactionActive: dockRepeater.anyInteraction
    readonly property bool editActive: dockRepeater.anyEdit
    readonly property var dockBodyItems: dockRepeater.bodies
    readonly property var dockMaskItems: dockRepeater.masks

    Repeater {
        id: dockRepeater

        property int revision: 0
        readonly property var bodies: {
            revision;
            const items = [];
            for (let i = 0; i < count; i++) {
                const body = itemAt(i)?.body;
                if (body)
                    items.push(body);
            }
            return items;
        }
        readonly property var masks: dockRepeater.bodies.map(body => body.inputMaskItem).filter(Boolean)
        readonly property bool anyInteraction: {
            revision;
            for (let i = 0; i < count; i++) {
                if (itemAt(i)?.body?.interactionActive)
                    return true;
            }
            return false;
        }
        readonly property bool anyEdit: {
            revision;
            for (let i = 0; i < count; i++) {
                if (itemAt(i)?.body?.editMode)
                    return true;
            }
            return false;
        }

        // Keyed so an edited config updates in place instead of rebuilding every dock body.
        model: ScriptModel {
            values: host.configs
            objectProp: "id"
        }

        delegate: Item {
            id: slot

            required property var modelData
            // Keep the last resolved config so the body never sees a shapeless one while the delegate is torn down.
            property var config: modelData
            onModelDataChanged: if (modelData)
                config = modelData
            readonly property alias body: dockBody

            anchors.fill: parent
            visible: (slot.config?.enabled ?? false) || ((slot.config?.openOnOverview ?? false) && CompositorService.isNiri)

            onVisibleChanged: dockRepeater.revision++
            Component.onCompleted: dockRepeater.revision++
            Component.onDestruction: dockRepeater.revision++

            DockBody {
                id: dockBody

                anchors.fill: parent
                config: slot.config
                hostWindow: host.frameWindow
                modelData: host.targetScreen
                contextMenu: BarWidgetService.dockContextMenu
                trashContextMenu: BarWidgetService.dockTrashContextMenu

                onInteractionActiveChanged: dockRepeater.revision++
                onEditModeChanged: dockRepeater.revision++
            }
        }
    }
}
