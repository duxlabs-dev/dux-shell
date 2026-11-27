pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modules.ControlCenter
import qs.Modules.ControlCenter.Widgets
import qs.Services
import qs.DCommon.Widgets

Item {
    id: root

    signal screenshotRequested(string mode, bool keepOpen)

    property bool keepOpen: false
    readonly property string title: I18n.tr("Screenshot")

    function requestCapture(mode) {
        const stayOpen = root.keepOpen;
        root.keepOpen = false;
        root.screenshotRequested(mode, stayOpen);
    }

    readonly property Item headerActions: Row {
        spacing: Theme.spacingS

        DActionButton {
            buttonSize: CcMetrics.headerActionSize
            iconSize: CcMetrics.headerActionIconSize
            iconName: root.keepOpen ? "keep" : "keep_off"
            iconColor: root.keepOpen ? Theme.primary : Theme.surfaceText
            backgroundColor: root.keepOpen ? Theme.primarySelected : "transparent"
            tooltipText: I18n.tr("Keep Control Center open", "screenshot detail header action tooltip")
            Accessible.name: I18n.tr("Keep Control Center open", "screenshot detail header action tooltip")
            onClicked: root.keepOpen = !root.keepOpen
        }

        CcSettingsButton {
            settingsTab: "screenshot"
        }
    }

    implicitHeight: column.height

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    DFlickable {
        anchors.fill: parent
        contentHeight: column.height
        clip: true

        Column {
            id: column
            width: parent.width
            spacing: CcMetrics.detailContentGap

            CcGroup {
                CcListRow {
                    iconName: "fullscreen"
                    title: I18n.tr("Fullscreen", "screenshot capture mode")
                    clickable: true
                    onClicked: root.requestCapture("full")
                }

                CcListRow {
                    visible: CompositorService.isHyprland || CompositorService.isNiri || CompositorService.isMango
                    iconName: "web_asset"
                    title: I18n.tr("Window", "screenshot capture mode")
                    clickable: true
                    onClicked: root.requestCapture("window")
                }

                CcListRow {
                    iconName: "monitor"
                    title: I18n.tr("All screens", "screenshot capture mode")
                    clickable: true
                    onClicked: root.requestCapture("all")
                }

                CcListRow {
                    iconName: "unfold_more"
                    title: I18n.tr("Scroll", "screenshot capture mode")
                    clickable: true
                    onClicked: root.requestCapture("scroll")
                }
            }
        }
    }
}
