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
    // The sheet a chrome shows its panels in, laid out by the chrome itself.
    property Item inlinePanel: null

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
    readonly property bool panelOpen: !!inlinePanel?.opened
    readonly property bool scrolling: root.player.live && !!presentation?.playing && !panelOpen
    readonly property var availableFocusTargets: root.player.lyricsFocusTarget ? [root.player.lyricsFocusTarget].concat(focusTargets) : focusTargets

    readonly property Item focusTarget: panelOpen ? inlinePanel.focusTarget : availableFocusTargets.find(item => item?.visible && item.enabled) ?? null
    readonly property Item previousFocusTarget: panelOpen ? inlinePanel.focusTarget : availableFocusTargets.filter(item => item?.visible && item.enabled).slice(-1)[0] ?? null

    implicitHeight: root.baseHeight

    function cycleFocus(backwards) {
        if (panelOpen)
            return FocusNavigation.moveFocus(inlinePanel.focusTargets, backwards);
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
}
