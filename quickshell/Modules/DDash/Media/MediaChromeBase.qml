pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.DDash
import "../../../DCommon/Common/FocusNavigation.js" as FocusNavigation

Item {
    id: root

    default property alias content: cardBody.data

    required property var player
    property real artSize: DashMetrics.mediaArtSizeDash
    property real backdropRadius: DashMetrics.surfaceRadius
    property color surfaceColor: DashMetrics.cardColor
    property real baseHeight: DashMetrics.tabMinHeight
    property var focusTargets: []
    property var panelButtons: []
    property bool inlineVolume: false

    readonly property var activePlayer: root.player.activePlayer
    readonly property var presentation: root.player.presentation
    readonly property string title: presentation?.title || I18n.tr("Unknown Track")
    readonly property string artist: presentation?.artist || I18n.tr("Unknown Artist")
    readonly property string album: presentation?.album ?? ""
    readonly property string artUrl: presentation?.artUrl ?? ""
    readonly property real padding: DashMetrics.mediaCardMargin
    readonly property string titleFontToken: root.player.options?.titleFont ?? MediaOptions.defaultTitleFont
    readonly property bool seekbarEnabled: root.player.options?.seekbar ?? MediaOptions.defaults.seekbar
    readonly property bool hasSeekbar: seekbarEnabled && !!presentation && presentation.length > 0
    readonly property bool panelOpen: panel.opened || playbackPopup.opened
    readonly property bool scrolling: root.player.live && !!presentation?.playing && !panel.opened
    readonly property var availableFocusTargets: root.player.lyricsFocusTarget ? [root.player.lyricsFocusTarget].concat(focusTargets) : focusTargets

    readonly property Item focusTarget: panel.opened ? panel.focusTarget : playbackPopup.opened ? playbackPopup.focusTarget : availableFocusTargets.find(item => item?.visible && item.enabled) ?? null
    readonly property Item previousFocusTarget: panel.opened ? panel.focusTarget : playbackPopup.opened ? playbackPopup.focusTarget : availableFocusTargets.filter(item => item?.visible && item.enabled).slice(-1)[0] ?? null

    implicitHeight: root.baseHeight

    function cycleFocus(backwards) {
        if (panel.opened)
            return panel.cycleFocus(backwards);
        if (playbackPopup.opened)
            return FocusNavigation.moveFocus(playbackPopup.focusTargets, backwards);
        return FocusNavigation.moveFocus(availableFocusTargets, backwards);
    }

    function buttonForPanel(panelId) {
        const usable = panelButtons.filter(button => button?.visible && button.enabled);
        const opener = root.player.panelOpener;
        if (opener?.panelId === panelId && usable.includes(opener))
            return opener;
        return usable.find(button => button.panelId === panelId) ?? usable[0] ?? null;
    }

    function focusPanelButton(panelId) {
        return FocusNavigation.focusItem(buttonForPanel(panelId), false);
    }

    // The backdrop clips itself to the corners, so the card needs no clip of its own.
    Rectangle {
        anchors.fill: parent
        radius: root.backdropRadius
        color: root.surfaceColor
        border.width: Theme.layerOutlineWidth
        border.color: Theme.outlineMedium

        Loader {
            anchors.fill: parent
            anchors.margins: Theme.layerOutlineWidth
            active: root.player.wallpaperEnabled && !!root.presentation

            sourceComponent: MediaArtBackdrop {
                radius: root.backdropRadius - Theme.layerOutlineWidth
                stableHeight: root.baseHeight
                activePlayer: root.activePlayer
                artUrl: root.artUrl
            }
        }

        Item {
            id: cardBody
            anchors.fill: parent
            anchors.margins: root.padding + Theme.layerOutlineWidth
        }
    }

    MediaPanel {
        id: panel
        parent: root.player.contentViewport || root
        z: DashMetrics.overlayZ
        player: root.player
        visible: root.visible && active
        scrimRadius: root.backdropRadius
        returnFocusItem: root.buttonForPanel(displayedPanel)
    }

    MediaPlaybackPopup {
        id: playbackPopup
        parent: root.player.contentViewport || root
        anchors.fill: parent
        z: DashMetrics.overlayZ
        player: root.player
        anchorItem: root.buttonForPanel("playback")
        visible: root.visible && playbackPopup.shown
    }
}
