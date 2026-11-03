import QtQuick
import qs.Common
import qs.Modules.Plugins
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets

BasePill {
    id: root

    property bool isHovered: clickArea.containsMouse

    signal toggleVpnPopup

    content: Component {
        Item {
            implicitWidth: icon.width
            implicitHeight: root.contentThickness

            DIcon {
                id: icon

                name: DMSNetworkService.connected ? "vpn_lock" : "vpn_key_off"
                size: Theme.barIconSize(root.barThickness, -4, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
                color: DMSNetworkService.connected ? Theme.primary : Theme.widgetIconColor
                opacity: DMSNetworkService.isBusy ? 0.5 : 1.0
                anchors.centerIn: parent

                Behavior on opacity {
                    NumberAnimation {
                        duration: Theme.shortDuration
                        easing.type: Easing.InOutQuad
                    }
                }
            }
        }
    }

    Loader {
        id: tooltipLoader
        active: false
        sourceComponent: DTooltip {}
    }

    MouseArea {
        id: clickArea

        x: -root.leftMargin
        y: -root.topMargin
        width: root.width + root.leftMargin + root.rightMargin
        height: root.height + root.topMargin + root.bottomMargin
        hoverEnabled: true
        cursorShape: DMSNetworkService.isBusy ? Qt.BusyCursor : Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        enabled: !DMSNetworkService.isBusy
        onPressed: event => {
            root.triggerRipple(this, event.x, event.y);
            switch (event.button) {
            case Qt.RightButton:
                DMSNetworkService.toggleVpn();
                return;
            case Qt.LeftButton:
                root.toggleVpnPopup();
                return;
            }
        }
        onEntered: {
            if (!root.parentScreen || (popoutTarget?.shouldBeVisible))
                return;
            tooltipLoader.active = true;
            if (!tooltipLoader.item)
                return;
            let tooltipText = "";
            if (!DMSNetworkService.connected) {
                tooltipText = "VPN Disconnected";
            } else {
                const names = DMSNetworkService.activeNames || [];
                if (names.length <= 1) {
                    const name = names[0] || "";
                    const maxLength = 25;
                    const displayName = name.length > maxLength ? name.substring(0, maxLength) + "..." : name;
                    tooltipText = "VPN Connected • " + displayName;
                } else {
                    const name = names[0];
                    const maxLength = 20;
                    const displayName = name.length > maxLength ? name.substring(0, maxLength) + "..." : name;
                    tooltipText = "VPN Connected • " + displayName + " +" + (names.length - 1);
                }
            }

            if (root.isVerticalOrientation) {
                const localPos = mapToItem(null, width / 2, height / 2);
                const currentScreen = root.parentScreen || Screen;
                const adjustedY = localPos.y + root.minTooltipY;
                const tooltipX = root.axis?.edge === "left" ? (root.barThickness + root.barSpacing + Theme.spacingXS) : (currentScreen.width - root.barThickness - root.barSpacing - Theme.spacingXS);
                const isLeft = root.axis?.edge === "left";
                tooltipLoader.item.show(tooltipText, tooltipX, adjustedY, currentScreen, isLeft, !isLeft);
            } else {
                const isBottom = root.axis?.edge === "bottom";
                const localPos = mapToItem(null, width / 2, 0);
                const currentScreen = root.parentScreen || Screen;

                let tooltipY;
                if (isBottom) {
                    const tooltipHeight = Theme.fontSizeSmall * 1.5 + Theme.spacingS * 2;
                    tooltipY = currentScreen.height - root.barThickness - root.barSpacing - Theme.spacingXS - tooltipHeight;
                } else {
                    tooltipY = root.barThickness + root.barSpacing + Theme.spacingXS;
                }

                tooltipLoader.item.show(tooltipText, localPos.x, tooltipY, currentScreen, false, false);
            }
        }
        onExited: {
            if (tooltipLoader.item) {
                tooltipLoader.item.hide();
            }
            tooltipLoader.active = false;
        }
    }
}
