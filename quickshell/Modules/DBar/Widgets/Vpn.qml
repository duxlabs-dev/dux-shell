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
                        duration: Theme.expressiveDurations.expressiveFastEffects
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.expressiveCurves.expressiveFastEffects
                    }
                }
            }
        }
    }

    PillTooltip {
        id: tooltip
        pill: root
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

            tooltip.show(tooltipText, clickArea);
        }
        onExited: tooltip.hide()
    }
}
