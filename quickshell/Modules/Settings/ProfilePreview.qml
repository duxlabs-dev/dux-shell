import QtQuick
import Quickshell.Widgets
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

ClippingRectangle {
    id: root

    // A profile or the editor's draft: anything with id, thumbnail and thumbnailUpdated.
    property var owner: null
    property var targetScreen: null

    readonly property real ultrawideRatio: 9 / 21
    readonly property real ratio: targetScreen && targetScreen.width > 0 ? Math.max(ultrawideRatio, Math.min(SettingsMetrics.choiceCardPreviewRatio, targetScreen.height / targetScreen.width)) : SettingsMetrics.choiceCardPreviewRatio
    readonly property real renderScale: Window.window?.devicePixelRatio ?? Screen.devicePixelRatio
    readonly property bool capturing: !!owner?.id && ConfigProfileService.capturingId === owner.id

    implicitHeight: Math.round(width * ratio)
    radius: Theme.cornerRadiusS
    color: SettingsMetrics.controlColor

    Image {
        id: preview
        anchors.fill: parent
        source: root.width > 0 ? ConfigProfileService.thumbnailSource(root.owner) : ""
        sourceSize: Qt.size(Math.ceil(root.width * root.renderScale), Math.ceil(root.height * root.renderScale))
        asynchronous: true
        retainWhileLoading: true
        fillMode: Image.PreserveAspectCrop
        visible: status === Image.Ready
    }

    DSVGIcon {
        anchors.centerIn: parent
        size: Math.round(parent.height * 0.45)
        source: Theme.shellDir + "/assets/danklogonormal.svg"
        colorOverride: Theme.onSurfaceVariant
        visible: !spinner.running && preview.status !== Image.Ready
    }

    DSpinner {
        id: spinner
        anchors.centerIn: parent
        running: root.capturing || preview.status === Image.Loading
        visible: running
    }
}
