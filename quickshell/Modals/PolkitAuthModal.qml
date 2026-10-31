import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets

DFloatingWindow {
    id: root

    property var currentFlow: null

    function show() {
        currentFlow = PolkitService.agent?.flow ?? null;
        if (contentLoader.item)
            contentLoader.item.reset();
        visible = true;
    }

    function hide() {
        visible = false;
    }

    function cancelAuth() {
        const flow = currentFlow;
        currentFlow = null;
        hide();
        if (!flow || flow.isCompleted)
            return;
        flow.cancelAuthenticationRequest();
    }

    function focusContent() {
        if (contentLoader.item)
            contentLoader.item.focusPasswordField();
    }

    objectName: "polkitAuthModal"
    title: I18n.tr("Authentication", "noun, polkit dialog title and settings section title")
    minimumSize: Qt.size(Theme.dialogMaxWidth, Math.min((screen?.height ?? 1080) - Theme.spacingXL * 2, Math.max(220, contentLoader.item?.implicitHeight ?? 0)))
    maximumSize: minimumSize
    implicitWidth: minimumSize.width
    implicitHeight: minimumSize.height
    visible: false

    onClosed: cancelAuth()

    onVisibleChanged: {
        if (visible) {
            focusTimer.restart();
            return;
        }
        if (contentLoader.item)
            contentLoader.item.reset();
    }

    Timer {
        id: focusTimer
        interval: 0
        onTriggered: root.focusContent()
    }

    Connections {
        target: PolkitService.agent
        enabled: PolkitService.polkitAvailable

        function onIsActiveChanged() {
            if (!(PolkitService.agent?.isActive ?? false))
                root.hide();
        }
    }

    Loader {
        id: contentLoader
        anchors.fill: parent
        active: root.visible
        sourceComponent: PolkitAuthContent {
            currentFlow: root.currentFlow
            windowControls: authWindowControls
            onCancelRequested: root.cancelAuth()
            onCloseRequested: root.hide()
        }
    }

    FloatingWindowControls {
        id: authWindowControls
        targetWindow: root
    }
}
