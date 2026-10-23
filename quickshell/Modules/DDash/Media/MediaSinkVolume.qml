pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.DCommon.Widgets

RowLayout {
    id: root

    required property var node
    property string label: AudioService.displayName(node)
    property color contentColor: Theme.onSelectedContainer
    readonly property var focusTargets: [muteButton, volumeSlider]
    // A host that cycles its own focus takes Tab from the slider before Qt's window wide tab chain does.
    property bool hostCyclesFocus: false

    signal cycleFocusRequested(bool backwards)

    function handleTab(event, backwards) {
        event.accepted = hostCyclesFocus;
        if (event.accepted)
            cycleFocusRequested(backwards);
    }

    spacing: Theme.spacingS

    DActionButton {
        id: muteButton
        buttonSize: Theme.iconButtonSize
        iconName: volumeSlider.volumeIcon
        iconColor: root.contentColor
        Accessible.name: volumeSlider.muteLabel
        onClicked: volumeSlider.muteRequested()
        Keys.onTabPressed: event => root.handleTab(event, false)
        Keys.onBacktabPressed: event => root.handleTab(event, true)
    }

    MediaVolumeSlider {
        id: volumeSlider
        Layout.fillWidth: true
        size: "xs"
        insetIcon: ""
        volume: root.node?.audio?.volume ?? 0
        muted: root.node?.audio?.muted ?? false
        maximumVolume: AudioService.getMaxVolumePercent(root.node)
        fillColor: Theme.onSelectedContainer
        fillTextColor: Theme.selectedContainer
        trackColor: Theme.onPrimary
        trackTextColor: Theme.onSelectedContainer
        Accessible.name: I18n.tr("Volume") + ": " + root.label
        Keys.onTabPressed: event => root.handleTab(event, false)
        Keys.onBacktabPressed: event => root.handleTab(event, true)
        onVolumeChangedByUser: volume => {
            const audio = root.node?.audio;
            if (!audio)
                return;
            SessionData.suppressOSDTemporarily();
            audio.volume = volume;
            if (volume > 0)
                audio.muted = false;
        }
        onMuteRequested: {
            const audio = root.node?.audio;
            if (!audio)
                return;
            SessionData.suppressOSDTemporarily();
            audio.muted = !audio.muted;
        }
    }
}
