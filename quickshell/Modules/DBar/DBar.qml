import QtQuick
import Quickshell
import qs.Common
import qs.Services
import "WidgetModel.js" as WidgetModel

Item {
    id: root

    required property var barConfig

    signal barReady(var barConfig)

    property string _registeredBarId: ""
    function registerBar() {
        const id = barConfig?.id ?? "";
        if (id === _registeredBarId)
            return;
        BarWidgetService.unregisterDankBarItem(_registeredBarId, root);
        _registeredBarId = id;
        BarWidgetService.registerDankBarItem(id, root);
    }
    onBarConfigChanged: registerBar()
    Component.onCompleted: registerBar()
    Component.onDestruction: BarWidgetService.unregisterDankBarItem(_registeredBarId, root)

    property alias barVariants: barVariants
    readonly property bool fullscreenAutoHide: barVariants.instances.some(bar => bar.fullscreenAutoHide)
    property var hyprlandOverviewLoader: null
    property bool systemTrayMenuOpen: false

    property alias leftWidgetsModel: leftWidgetsModel
    property alias centerWidgetsModel: centerWidgetsModel
    property alias rightWidgetsModel: rightWidgetsModel

    property string _leftWidgetsJson: JSON.stringify(WidgetModel.normalize(root.barConfig?.leftWidgets))
    property string _centerWidgetsJson: JSON.stringify(WidgetModel.normalize(root.barConfig?.centerWidgets))
    property string _rightWidgetsJson: JSON.stringify(WidgetModel.normalize(root.barConfig?.rightWidgets))

    ScriptModel {
        id: leftWidgetsModel
        objectProp: "id"
        values: JSON.parse(root._leftWidgetsJson)
    }

    ScriptModel {
        id: centerWidgetsModel
        objectProp: "id"
        values: JSON.parse(root._centerWidgetsJson)
    }

    ScriptModel {
        id: rightWidgetsModel
        objectProp: "id"
        values: JSON.parse(root._rightWidgetsJson)
    }

    function focusedBarInstance() {
        const screenName = CompositorService.getFocusedScreenName();
        if (!screenName)
            return barVariants.instances[0] || null;
        return barVariants.instances.find(instance => instance.modelData?.name === screenName) || null;
    }

    function triggerControlCenterOnFocusedScreen() {
        const instance = focusedBarInstance();
        if (!instance)
            return false;
        instance.triggerControlCenter();
        return true;
    }

    function triggerWallpaperBrowserOnFocusedScreen() {
        const instance = focusedBarInstance();
        if (!instance)
            return false;
        instance.triggerWallpaperBrowser();
        return true;
    }

    Variants {
        id: barVariants
        model: ShellLayout.hostedScreens(root.barConfig?.id)

        delegate: DBarWindow {
            rootWindow: root
            barConfig: root.barConfig
            leftWidgetsModel: root.leftWidgetsModel
            centerWidgetsModel: root.centerWidgetsModel
            rightWidgetsModel: root.rightWidgetsModel
        }
    }
}
