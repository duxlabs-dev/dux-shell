import QtQuick
import qs.Common
import qs.Modules.Settings.Widgets

Column {
    id: root

    property var page: null

    readonly property IslandSettingsStore widgetStore: IslandSettingsStore {
        barId: root.page?.barId ?? ""
    }

    width: parent?.width ?? 0
    spacing: Theme.spacingL

    IslandHomeCard {
        store: widgetStore
        hosted: true
        keyPrefix: "islandWidget"
    }

    IslandBehaviorCard {
        store: widgetStore
        hosted: true
        docked: true
        keyPrefix: "islandWidget"
    }

    IslandNotificationsCard {
        store: widgetStore
        keyPrefix: "islandWidget"
    }

    IslandMotionCard {
        store: widgetStore
        keyPrefix: "islandWidget"
    }
}
