pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.DDash
import qs.Modules.Settings.Widgets
import "../../../DCommon/Common/FocusNavigation.js" as FocusNavigation

// Qt moves a focused control along the whole window's tab chain before its parents see Tab, so every
// control in here hands Tab to cycleFocus itself.
FocusScope {
    id: root

    required property var player
    property Item returnFocusItem: null
    property string shownPanel: ""
    property bool closedByKey: false

    readonly property string requestedPanel: root.player.panel
    readonly property bool opened: root.player.live && (requestedPanel === "players" || requestedPanel === "devices")
    readonly property bool shown: opened || progress > 0
    readonly property bool animationsEnabled: !SettingsData.reduceMotion && Theme.currentAnimationSpeed !== SettingsData.AnimationSpeed.None
    // Material's shared axis: the controls slide out and fade first, then the sheet slides in from the
    // other side and fades in, so the two never show at once. Closing plays it backwards.
    readonly property real progress: motion.value
    readonly property real slideDistance: DashMetrics.mediaSheetSlideDistance * (I18n.isRtl ? -1 : 1)
    readonly property real controlsOpacity: Math.max(0, 1 - progress / DashMetrics.mediaSheetFadeThreshold)
    readonly property real controlsShift: -slideDistance * progress
    readonly property real pageOpacity: Math.max(0, Math.min(1, (progress - DashMetrics.mediaSheetFadeThreshold) / (1 - DashMetrics.mediaSheetFadeThreshold)))
    readonly property real pageShift: slideDistance * (1 - progress)
    readonly property var spring: Theme.springPreset("default", Theme.expressiveDurations.expressiveDefaultSpatial)
    readonly property var sinks: shown && shownPanel === "devices" ? AudioService.getAvailableSinks() : []
    readonly property var players: shown && shownPanel === "players" ? root.player.selectablePlayers() : []
    readonly property var focusTargets: {
        const targets = [backButton];
        const repeater = shownPanel === "devices" ? deviceRows : playerRows;
        for (let i = 0; i < repeater.count; i++)
            targets.push(...(repeater.itemAt(i)?.focusTargets ?? []));
        return targets;
    }
    readonly property Item focusTarget: focusTargets[0]
    // The list's edge fade reads this to blend into the sheet instead of a darker ancestor.
    readonly property color surfaceColor: Theme.surfaceContainer

    visible: shown
    enabled: opened

    onRequestedPanelChanged: {
        if (requestedPanel !== "players" && requestedPanel !== "devices")
            return;
        shownPanel = requestedPanel;
        flickable.contentY = 0;
    }

    onOpenedChanged: {
        motion.retarget(opened ? 1 : 0);
        if (opened) {
            closedByKey = false;
            root.forceActiveFocus(Qt.OtherFocusReason);
            return;
        }
        if (!FocusNavigation.containsFocus(root))
            return;
        // Only a sheet left by keyboard hands back a focus ring, and the controls it returns to turn
        // usable only once this change has gone through.
        const keyboard = closedByKey || (Window.activeFocusItem?.visualFocus ?? false);
        Qt.callLater(() => {
            if (keyboard)
                FocusNavigation.focusItem(returnFocusItem, false);
            else
                returnFocusItem?.forceActiveFocus(Qt.OtherFocusReason);
        });
    }

    function close() {
        root.player.panel = "";
    }

    function cycleFocus(backwards) {
        if (FocusNavigation.moveFocus(focusTargets, backwards))
            return;
        const targets = focusTargets.filter(item => item?.visible && item.enabled);
        FocusNavigation.focusItem(backwards ? targets[targets.length - 1] : targets[0], backwards);
    }

    Keys.onPressed: event => {
        switch (event.key) {
        case Qt.Key_Escape:
            closedByKey = true;
            close();
            break;
        case Qt.Key_Tab:
        case Qt.Key_Backtab:
            cycleFocus(event.key === Qt.Key_Backtab);
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    SpringMotion {
        id: motion
        enabled: !Theme.springMotionDisabled
        reducedMotion: !root.animationsEnabled
        stiffness: root.spring.stiffness
        damping: root.spring.damping
        positionEpsilon: DashMetrics.mediaSheetSettleProgress
    }

    // The card stays put and only fades, since with the controls container it is the same surface.
    Rectangle {
        anchors.fill: parent
        radius: Theme.cornerRadiusXL
        color: root.surfaceColor
        opacity: Math.min(1, root.progress)
    }

    Item {
        id: header

        x: Theme.spacingL
        y: Theme.spacingL
        width: parent.width - Theme.spacingL * 2
        height: backButton.height
        opacity: root.pageOpacity
        transform: Translate {
            x: root.pageShift
        }

        DIconButton {
            id: backButton
            width: buttonSize
            variant: "tonal"
            round: false
            iconName: I18n.isRtl ? "arrow_forward" : "arrow_back"
            containerColor: Theme.surfaceContainerHighest
            contentColor: Theme.onSurfaceVariant
            tooltipText: I18n.tr("Back")
            Keys.onTabPressed: root.cycleFocus(false)
            Keys.onBacktabPressed: root.cycleFocus(true)
            onClicked: root.close()
        }

        StyledText {
            anchors.left: backButton.right
            anchors.leftMargin: Theme.spacingM
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.shownPanel === "devices" ? I18n.tr("Play on", "Audio output selection sheet title") : I18n.tr("Players", "Media player selection")
            color: Theme.onSurface
            font.pixelSize: Theme.fontSizeXLarge
            font.weight: Theme.fontWeightMedium
            elide: Text.ElideRight
        }
    }

    DFlickable {
        id: flickable

        anchors.fill: parent
        anchors.margins: Theme.spacingL
        anchors.topMargin: header.y + header.height + Theme.spacingM
        opacity: root.pageOpacity
        transform: Translate {
            x: root.pageShift
        }
        contentHeight: content.implicitHeight
        clip: true

        Column {
            id: content

            width: flickable.width

            SettingsGroup {
                width: parent.width
                visible: root.shownPanel === "players" && root.players.length > 0
                slotColor: Theme.surfaceContainerHigh
                customPaddingH: Theme.spacingL
                customPaddingV: Theme.spacingM

                Repeater {
                    id: playerRows

                    model: root.players

                    ListRow {
                        required property var modelData

                        iconName: "music_note"
                        title: modelData?.identity ?? ""
                        subtitle: [modelData?.trackTitle, modelData?.trackArtist].filter(Boolean).join(" · ")
                        active: modelData === root.player.activePlayer
                        onClicked: MprisController.setActivePlayer(modelData)
                        Keys.onTabPressed: root.cycleFocus(false)
                        Keys.onBacktabPressed: root.cycleFocus(true)
                    }
                }
            }

            SettingsGroup {
                width: parent.width
                visible: root.shownPanel === "devices" && root.sinks.length > 0
                slotColor: Theme.surfaceContainerHigh
                customPaddingH: Theme.spacingL
                customPaddingV: Theme.spacingM

                Repeater {
                    id: deviceRows

                    model: root.sinks

                    ListRow {
                        id: deviceRow

                        required property var modelData

                        iconName: AudioService.sinkIcon(modelData)
                        title: AudioService.displayName(modelData)
                        subtitle: root.player.outputStatus(modelData)
                        active: modelData === AudioService.sink
                        onClicked: AudioService.setSink(modelData)
                        Keys.onTabPressed: root.cycleFocus(false)
                        Keys.onBacktabPressed: root.cycleFocus(true)

                        focusTargets: clickable ? [deviceRow] : volumeLoader.item?.focusTargets ?? []

                        body: Loader {
                            id: volumeLoader
                            width: parent.width
                            active: deviceRow.active && !!deviceRow.modelData?.audio
                            visible: active

                            sourceComponent: MediaSinkVolume {
                                node: deviceRow.modelData
                                hostCyclesFocus: true
                                onCycleFocusRequested: backwards => root.cycleFocus(backwards)
                                label: deviceRow.title
                                contentColor: deviceRow.titleColor
                            }
                        }
                    }
                }
            }

            StyledText {
                width: parent.width
                visible: root.shownPanel === "devices" ? root.sinks.length === 0 : root.players.length === 0
                text: root.shownPanel === "devices" ? I18n.tr("No output devices found") : I18n.tr("No Active Players")
                color: Theme.onSurfaceVariant
                wrapMode: Text.Wrap
            }
        }
    }

    // The active row has nothing to do on click, so the selected output is reached through its volume controls.
    component ListRow: SettingsRow {
        id: listRow

        property var focusTargets: clickable ? [listRow] : []

        paddingH: Theme.spacingL
        paddingV: Theme.spacingM
        rowColor: Theme.surfaceContainerHigh
        clickable: !active
        Accessible.selected: active
    }
}
