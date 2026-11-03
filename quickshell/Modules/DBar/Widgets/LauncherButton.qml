import QtQuick
import qs.Common
import qs.Modules.Plugins
import qs.Services
import qs.Widgets

BasePill {
    id: root

    property bool isActive: false
    property var hyprlandOverviewLoader: null
    property var widgetData: null

    function opt(key) {
        return SettingsData.widgetOption("launcherButton", root.widgetData, key);
    }

    content: Component {
        Item {
            implicitWidth: root.contentThickness
            implicitHeight: root.contentThickness

            LauncherLogo {
                anchors.centerIn: parent
                mode: root.opt("launcherLogoMode")
                size: Theme.barIconSize(root.barThickness, root.opt("launcherLogoSizeOffset"), root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
                appsIconSize: Theme.barIconSize(root.barThickness, -4, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
                appsIconColor: Theme.widgetIconColor
                colorOverride: root.opt("launcherLogoColorOverride")
                brightness: root.opt("launcherLogoBrightness")
                contrast: root.opt("launcherLogoContrast")
                customPath: root.opt("launcherLogoCustomPath")
            }
        }
    }

    onRightClicked: {
        if (CompositorService.isNiri) {
            NiriService.toggleOverview();
        } else if (CompositorService.isMango) {
            CompositorService.toggleOverview(root.parentScreen?.name);
        } else if (root.hyprlandOverviewLoader?.item) {
            root.hyprlandOverviewLoader.item.overviewOpen = !root.hyprlandOverviewLoader.item.overviewOpen;
        }
    }
}
