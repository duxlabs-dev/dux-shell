import QtQuick
import qs.Common
import qs.Modules.ControlCenter.Widgets

CcWidgetLibrary {
    required property Item dock

    width: Math.min(implicitWidth, dock.width - Theme.spacingL * 2)
    height: Math.min(implicitHeight, dock.height - Theme.spacingL * 2)
    widgets: dock.addableWidgets
    Component.onCompleted: reset()
    onChosen: widgetId => {
        dock.addWidget(widgetId);
        dock.closeWidgetLibrary();
    }
    onDismissed: dock.closeWidgetLibrary()
}
