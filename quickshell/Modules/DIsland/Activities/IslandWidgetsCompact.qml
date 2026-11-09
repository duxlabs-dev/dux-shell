pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modules.DBar
import qs.Modules.SurfaceWidgets

Item {
    id: root
    required property var controller
    required property var systemModel
    required property var mediaModel
    AxisContext {
        id: widgetAxis
        edge: root.controller.edge
    }
    SurfaceContext {
        id: context
        host: root.controller.widgetHost
        config: root.controller.barConfig
        axis: widgetAxis
        screen: root.controller.screen
        islandController: root.controller
        thickness: root.controller.compactFaceThickness
        widgetThickness: root.controller.compactIconSize
        availableSize: root.controller.isVertical ? root.controller.dashboardAvailableHeight : root.controller.dashboardAvailableWidth
    }
    SurfaceWidgetFactory {
        id: factory
        surfaceContext: context
    }
    HomeCompact {
        anchors.fill: parent
        controller: root.controller
        systemModel: root.systemModel
        mediaModel: root.mediaModel
        widgetEntries: SettingsData.islandCollapsedWidgets(root.controller.barConfig)
        widgetFactory: factory
        widgetContext: context
    }
}
