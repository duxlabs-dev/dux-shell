pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modules.Plugins

BasePill {
    id: root
    property var widgetData: null
    property var surfaceContext: null
    readonly property string titleMode: SettingsData.widgetOption("music", widgetData, "mediaTitleMode")
    property bool titleFlashing: false
    enableBackgroundHover: true

    function flashTitle() {
        if (titleMode !== "changes" || !source.available)
            return;
        titleFlashing = true;
        titleTimer.restart();
    }

    MediaActivitySource {
        id: source
        onTitleChanged: root.flashTitle()
        onAvailableChanged: root.flashTitle()
    }
    Timer {
        id: titleTimer
        interval: SettingsData.widgetOption("music", root.widgetData, "mediaTitleDuration")
        running: root.titleFlashing && root.surfaceLive
        onTriggered: root.titleFlashing = false
    }
    content: Component {
        MediaActivityFace {
            mediaModel: source
            dense: true
            isVertical: root.isVerticalOrientation
            contentScale: root.surfaceContext?.kind === "dock" ? root.widgetThickness / 40 : 1
            artworkSize: Math.min(root.widgetThickness, Theme.iconSizeLarge * contentScale)
            artworkVisible: SettingsData.widgetOption("music", root.widgetData, "mediaShowCoverArt")
            artworkCircular: SettingsData.widgetOption("music", root.widgetData, "mediaArtworkCircular")
            visualizerEnabled: SettingsData.widgetOption("music", root.widgetData, "mediaVisualizerEnabled")
            visualizerIdle: SettingsData.widgetOption("music", root.widgetData, "mediaVisualizerIdle")
            titleVisible: source.available && (root.titleMode === "always" || root.titleMode === "changes" && root.titleFlashing)
            titleMaxWidth: SettingsData.widgetOption("music", root.widgetData, "mediaTitleMaxWidth")
            enabled: root.surfaceLive
            onClockClicked: root.clicked()
            onMediaClicked: root.clicked()
        }
    }
}
