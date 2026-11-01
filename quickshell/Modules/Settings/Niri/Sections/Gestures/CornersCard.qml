pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Niri.Components
import "../../../../../Common/niri/sections/corners.js" as Corners

NiriCard {
    id: root

    readonly property var actions: [
        {
            "id": "overview",
            "icon": "grid_view",
            "text": I18n.tr("Overview"),
            "dms": false
        },
        {
            "id": "notifications",
            "icon": "notifications",
            "text": I18n.tr("Notifications"),
            "dms": true
        },
        {
            "id": "launcher",
            "icon": "apps",
            "text": I18n.tr("Launcher"),
            "dms": true
        },
        {
            "id": "controlCenter",
            "icon": "tune",
            "text": I18n.tr("Control Center"),
            "dms": true
        },
        {
            "id": "screenshot",
            "icon": "screenshot_region",
            "text": I18n.tr("Screenshot"),
            "dms": true
        },
        {
            "id": "none",
            "icon": "block",
            "text": I18n.tr("Nothing"),
            "dms": false
        }
    ]
    readonly property var cornerInfo: ({
            "top-left": {
                "icon": "north_west",
                "text": I18n.tr("Top Left")
            },
            "top-right": {
                "icon": "north_east",
                "text": I18n.tr("Top Right")
            },
            "bottom-left": {
                "icon": "south_west",
                "text": I18n.tr("Bottom Left")
            },
            "bottom-right": {
                "icon": "south_east",
                "text": I18n.tr("Bottom Right")
            }
        })
    readonly property var current: Corners.globalCorners(NiriPageService.state)
    readonly property int cornerCount: Object.values(current).filter(a => a !== "none").length
    readonly property string openCorner: menu.visible ? menu.corner : ""

    function actionOf(id) {
        return actions.find(a => a.id === id) ?? actions[actions.length - 1];
    }

    function pick(corner, action) {
        menu.close();
        NiriPageService.set("corners." + corner, action);
    }

    function openMenu(button, corner) {
        menu.parent = button;
        menu.corner = corner;
        menu.open();
    }

    icon: "select"
    title: I18n.tr("Hot corners")
    aside: I18n.tr("Click a corner")

    // The count of corners that run something; the card is global-only since per-screen corners live in Displays
    Item {
        width: parent.width
        height: countPill.height

        Rectangle {
            id: countPill

            anchors.right: parent.right
            width: countText.implicitWidth + Theme.spacingS * 2
            height: Theme.buttonHeightXS
            radius: height / 2
            color: "transparent"
            border.width: Theme.outlineWidth
            border.color: Theme.outlineVariant

            StyledText {
                id: countText
                anchors.centerIn: parent
                text: root.cornerCount === 1 ? I18n.tr("1 hot corner", "niri hot corners card: active corners") : I18n.tr("%1 hot corners", "niri hot corners card: active corners").arg(root.cornerCount)
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Theme.fontWeightMedium
                color: Theme.surfaceText
            }
        }
    }

    Flow {
        width: parent.width
        spacing: Theme.spacingL

        CornersPad {
            card: root
        }

        CornersLegend {
            card: root
        }
    }

    StyledText {
        width: parent.width
        visible: NiriPageService.expert
        topPadding: Theme.spacingS
        text: I18n.tr("KDL: only Overview corners go to gestures.hot-corners. DMS runs the others.")
        wrapMode: Text.WordWrap
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
    }

    CornersMenu {
        id: menu

        property string corner: ""

        y: (parent?.height ?? 0) + Theme.spacingXS
        title: corner ? root.cornerInfo[corner].text : ""
        current: corner ? (root.current[corner] ?? "none") : ""
        actions: root.actions
        onPicked: action => root.pick(corner, action)
    }
}
