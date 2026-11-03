pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modules.ControlCenter
import qs.Modules.ControlCenter.Details
import qs.Services
import qs.DCommon.Widgets

FocusScope {
    id: root

    default property alias detail: body.data
    readonly property Item page: body.children[0] ?? null
    readonly property string settingsTab: page?.headerActions?.settingsTab ?? ""

    signal closeRequested

    implicitHeight: CcMetrics.detailDialogPadding * 2 + header.height + (page?.implicitHeight ?? 0)
    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    function releasePortSelector() {
        if (portSelectorLoader.item?.shown)
            return;
        portSelectorLoader.active = false;
    }

    Item {
        id: header

        x: CcMetrics.detailDialogPadding
        y: CcMetrics.detailDialogPadding
        width: parent.width - CcMetrics.detailDialogPadding * 2
        height: CcMetrics.pageHeaderHeight

        StyledText {
            anchors.left: parent.left
            anchors.leftMargin: CcMetrics.rowPaddingH
            anchors.right: settingsButton.visible ? settingsButton.left : parent.right
            anchors.rightMargin: Theme.spacingM
            anchors.verticalCenter: parent.verticalCenter
            text: root.page?.title ?? ""
            font.pixelSize: CcMetrics.pageTitleSize
            color: Theme.surfaceText
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignLeft
        }

        DActionButton {
            id: settingsButton

            anchors.right: parent.right
            anchors.rightMargin: CcMetrics.headerEdgeInset
            anchors.verticalCenter: parent.verticalCenter
            visible: root.settingsTab !== ""
            buttonSize: CcMetrics.headerActionSize
            iconSize: CcMetrics.headerActionIconSize
            iconName: "settings"
            iconColor: Theme.surfaceText
            Accessible.name: I18n.tr("Settings")
            onClicked: {
                root.closeRequested();
                PopoutService.openSettingsWithTab(root.settingsTab);
            }
        }
    }

    Item {
        id: body

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        anchors.leftMargin: CcMetrics.detailDialogPadding
        anchors.rightMargin: CcMetrics.detailDialogPadding
        anchors.bottomMargin: CcMetrics.detailDialogPadding
        focus: true
    }

    Connections {
        target: root.page
        ignoreUnknownSignals: true

        function onShowPortSelector(node) {
            portSelectorLoader.active = true;
            portSelectorLoader.item?.show(node);
            if (!portSelectorLoader.item?.shown)
                portSelectorLoader.active = false;
        }
    }

    Loader {
        id: portSelectorLoader

        anchors.fill: parent
        z: CcMetrics.overlayZ
        active: false
        sourceComponent: AudioPortSelector {
            onDismissed: Qt.callLater(root.releasePortSelector)
        }
    }
}
