pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import "../Common/WallpaperTransitions.js" as Transitions

// Freezes every output while a profile switch applies, then reveals the new screen with the wallpaper transition.
Scope {
    id: root

    property bool applied: false
    property bool revealing: false
    property bool ended: false
    property string revealType: "fade"
    property var revealParams: ({})
    property int revealDuration: SettingsData.configProfileSwitchDuration
    readonly property bool settled: !Theme.generatingTheme && !ConfigProfileService.switchHeld

    // Deferred: the change can arrive inside a hold report, and ending the switch from there would re-enter it.
    onSettledChanged: Qt.callLater(_checkSettled)

    function _windows() {
        return variants.instances;
    }

    function _checkFrozen() {
        if (applied || _windows().length < Quickshell.screens.length)
            return;
        if (_windows().every(w => w.ready))
            _apply();
    }

    function _apply() {
        if (applied)
            return;
        applied = true;
        freezeLimit.stop();
        for (const w of _windows())
            w.frozen = w.ready;
        revealLimit.start();
        ConfigProfileService.applySwitch();
        Qt.callLater(_checkSettled);
    }

    function _checkSettled() {
        if (applied && !revealing && settled)
            _reveal();
    }

    function _reveal() {
        if (revealing)
            return;
        revealing = true;
        revealLimit.stop();
        const setting = SettingsData.configProfileSwitchTransition;
        let type = Transitions.pick(setting === "wallpaper" ? SessionData.wallpaperTransition : setting, SessionData.includedTransitions);
        if (type !== "none" && Theme.reduceMotion)
            type = "fade";
        revealType = type;
        revealDuration = setting === "wallpaper" ? SessionData.wallpaperTransitionDuration : SettingsData.configProfileSwitchDuration;
        revealParams = Transitions.params(type);
        ConfigProfileService.revealSwitch(type === "none" ? 0 : revealDuration);
        if (type !== "none") {
            for (const w of _windows())
                w.inReveal = w.frozen;
        }
        _checkDone();
    }

    function _checkDone() {
        if (!revealing || ended || !_windows().every(w => !w.inReveal || w.finished))
            return;
        ended = true;
        ConfigProfileService.endSwitch();
    }

    component Stage: Item {
        id: stage

        required property ScreencopyView capture

        property bool finished: fx.status === ShaderEffect.Error
        // Pixelate distorts only the incoming image, which here is the live screen, so it runs backwards on the old one.
        readonly property bool reversed: root.revealType === "pixelate"

        Rectangle {
            id: clear

            width: 1
            height: 1
            visible: false
            color: "transparent"
        }

        ShaderEffectSource {
            id: frozenTexture

            sourceItem: stage.capture
            textureSize: stage.capture.sourceSize
            live: false
            hideSource: true
        }

        ShaderEffectSource {
            id: clearTexture

            sourceItem: clear
            hideSource: true
            live: false
        }

        WallpaperTransitionEffect {
            id: fx

            anchors.fill: parent
            type: root.revealType
            params: root.revealParams
            source1: stage.reversed ? clearTexture : frozenTexture
            source2: stage.reversed ? frozenTexture : clearTexture
            fillColor: Qt.vector4d(0, 0, 0, 0)
            progress: stage.reversed ? 1 : 0
            visible: status !== ShaderEffect.Error
        }

        UniformAnimator {
            id: animator

            target: fx
            uniform: "progress"
            from: stage.reversed ? 1 : 0
            to: stage.reversed ? 0 : 1
            duration: root.revealDuration
            easing.type: Easing.InOutCubic
            // Not gated on Compiled: Qt reports that only for the first effect to load a shader file.
            running: fx.status !== ShaderEffect.Error
            onStopped: stage.finished = true
        }
    }

    Timer {
        id: freezeLimit
        running: true
        interval: Timing.settleLong
        onTriggered: root._apply()
    }

    Timer {
        id: revealLimit
        interval: Timing.holdMedium
        onTriggered: root._reveal()
    }

    Variants {
        id: variants

        model: Quickshell.screens

        onInstancesChanged: Qt.callLater(() => {
            root._checkFrozen();
            root._checkDone();
        })

        delegate: PanelWindow {
            id: win

            required property ShellScreen modelData
            readonly property bool ready: shot.hasContent && drawn
            property bool drawn: false
            property bool swapped: false
            property bool frozen: false
            property bool inReveal: false
            readonly property bool finished: !inReveal || ((reveal.item as Stage)?.finished ?? false)

            onReadyChanged: root._checkFrozen()
            onFinishedChanged: root._checkDone()

            screen: modelData
            color: "transparent"

            WlrLayershell.namespace: "dms:profile-switch"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusiveZone: -1
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            Item {
                id: content

                anchors.fill: parent

                readonly property var backing: Window.window

                Connections {
                    target: content.backing

                    // A second swap waits for the compositor's frame callback, so the first one is on screen.
                    function onFrameSwapped() {
                        if (!shot.hasContent || win.drawn)
                            return;
                        if (win.swapped)
                            win.drawn = true;
                        else
                            content.backing.update();
                        win.swapped = true;
                    }
                }

                ScreencopyView {
                    id: shot

                    anchors.fill: parent
                    captureSource: win.screen
                    live: false
                    paintCursor: false
                    visible: !root.applied || win.frozen
                }

                Loader {
                    id: reveal

                    anchors.fill: parent
                    active: win.inReveal

                    sourceComponent: Stage {
                        capture: shot
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                    hoverEnabled: true
                    cursorShape: Qt.ArrowCursor
                    onWheel: wheel => wheel.accepted = true
                }
            }
        }
    }
}
