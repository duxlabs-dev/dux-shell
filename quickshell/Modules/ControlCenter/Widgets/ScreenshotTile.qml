pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services

CcTile {
    id: root

    iconName: "screenshot_region"
    title: I18n.tr("Screenshot")
    showExpand: true

    onClicked: host?.screenshotRequested("region")
    expandedContent: Component {
        CcTileActions {
            actions: {
                const items = [
                    {
                        text: I18n.tr("Fullscreen", "screenshot capture mode"),
                        icon: "fullscreen",
                        trigger: () => root.host?.screenshotRequested("full")
                    }
                ];
                if (CompositorService.isHyprland || CompositorService.isNiri || CompositorService.isMango) {
                    items.push({
                        text: I18n.tr("Window", "screenshot capture mode"),
                        icon: "web_asset",
                        trigger: () => root.host?.screenshotRequested("window")
                    });
                }
                items.push({
                    text: I18n.tr("All screens", "screenshot capture mode"),
                    icon: "monitor",
                    trigger: () => root.host?.screenshotRequested("all")
                });
                items.push({
                    text: I18n.tr("Scroll", "screenshot capture mode"),
                    icon: "unfold_more",
                    trigger: () => root.host?.screenshotRequested("scroll")
                });
                return items;
            }
        }
    }
}
