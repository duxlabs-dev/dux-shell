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
    property Item anchorItem: null
    property rect anchorRect: Qt.rect(0, 0, 0, 0)

    readonly property bool opened: root.player.live && root.player.panel === "playback"
    readonly property bool shown: opened || card.opacity > 0
    readonly property bool animationsEnabled: !SettingsData.reduceMotion && Theme.currentAnimationSpeed !== SettingsData.AnimationSpeed.None
    readonly property var sinks: shown ? AudioService.getAvailableSinks() : []
    readonly property var players: shown ? root.player.selectablePlayers() : []
    readonly property var focusTargets: {
        const targets = [];
        for (const repeater of [playerRows, deviceRows]) {
            for (let i = 0; i < repeater.count; i++)
                targets.push(...(repeater.itemAt(i)?.focusTargets ?? []));
        }
        return targets.concat(closeButton);
    }
    readonly property Item focusTarget: focusTargets[0]
    readonly property real margin: Theme.spacingM
    readonly property real gap: Theme.spacingS
    readonly property bool below: anchorRect.y + anchorRect.height + gap + card.height <= height - margin || anchorRect.y - gap - card.height < margin

    onOpenedChanged: {
        if (!opened) {
            if (FocusNavigation.containsFocus(root))
                FocusNavigation.focusItem(anchorItem, false);
            return;
        }
        if (anchorItem) {
            const origin = anchorItem.mapToItem(root, 0, 0);
            anchorRect = Qt.rect(origin.x, origin.y, anchorItem.width, anchorItem.height);
        }
        flickable.contentY = 0;
        root.forceActiveFocus(Qt.OtherFocusReason);
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

    MouseArea {
        anchors.fill: parent
        enabled: root.opened
        acceptedButtons: Qt.AllButtons
        onPressed: root.close()
        onWheel: wheel => wheel.accepted = true
    }

    Item {
        id: card

        // The list's edge fade reads this to blend into the card instead of a darker ancestor.
        readonly property color surfaceColor: Theme.surfaceContainerHigh

        width: Math.min(DashMetrics.mediaPopupWidth, root.width - root.margin * 2)
        height: Math.min(content.implicitHeight + Theme.spacingL * 2, root.height - root.margin * 2)
        x: Math.max(root.margin, Math.min(root.width - width - root.margin, root.anchorRect.x + (root.anchorRect.width - width) / 2))
        y: Math.max(root.margin, Math.min(root.height - height - root.margin, root.below ? root.anchorRect.y + root.anchorRect.height + root.gap : root.anchorRect.y - root.gap - height))
        opacity: root.opened ? 1 : 0
        scale: root.opened ? 1 : Theme.popupEnterScale
        transformOrigin: root.below ? Item.Top : Item.Bottom

        Behavior on opacity {
            enabled: root.animationsEnabled
            NumberAnimation {
                duration: Theme.expressiveDurations.expressiveEffects
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
            }
        }

        Behavior on scale {
            enabled: root.animationsEnabled
            NumberAnimation {
                duration: Theme.expressiveDurations.expressiveFastSpatial
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveCurves.expressiveFastSpatial
            }
        }

        ElevationShadow {
            anchors.fill: parent
            level: Theme.elevationLevel2
            targetRadius: Theme.cornerRadiusXL
            targetColor: card.surfaceColor
        }

        // Keeps a press on the card's own padding from reaching the dismiss area.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
        }

        DFlickable {
            id: flickable

            anchors.fill: parent
            anchors.margins: Theme.spacingL
            contentHeight: content.implicitHeight
            clip: true

            Column {
                id: content

                width: flickable.width
                spacing: Theme.spacingS

                Item {
                    width: parent.width
                    height: closeButton.height

                    StyledText {
                        anchors.left: parent.left
                        anchors.right: closeButton.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("Playback", "Media player popup listing the players and output devices")
                        color: Theme.onSurface
                        font.pixelSize: Theme.fontSizeXLarge
                        font.weight: Theme.fontWeightMedium
                        elide: Text.ElideRight
                    }

                    DActionButton {
                        id: closeButton
                        anchors.right: parent.right
                        Keys.onTabPressed: root.cycleFocus(false)
                        Keys.onBacktabPressed: root.cycleFocus(true)
                        iconName: "close"
                        tooltipText: I18n.tr("Close")
                        onClicked: root.close()
                    }
                }

                SettingsSectionLabel {
                    text: I18n.tr("Players", "Media player selection")
                }

                SettingsGroup {
                    width: parent.width
                    slotColor: DashMetrics.cardColor
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

                SettingsSectionLabel {
                    text: I18n.tr("Play on", "Audio output selection sheet title")
                }

                SettingsGroup {
                    width: parent.width
                    visible: root.sinks.length > 0
                    slotColor: DashMetrics.cardColor
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
                    visible: root.sinks.length === 0
                    text: I18n.tr("No output devices found")
                    color: Theme.onSurfaceVariant
                    wrapMode: Text.Wrap
                }
            }
        }
    }

    // The active row has nothing to do on click, so the selected output is reached through its volume controls.
    component ListRow: SettingsRow {
        id: listRow

        property var focusTargets: clickable ? [listRow] : []

        paddingH: Theme.spacingL
        paddingV: Theme.spacingM
        rowColor: DashMetrics.cardColor
        clickable: !active
        Accessible.selected: active
    }
}
