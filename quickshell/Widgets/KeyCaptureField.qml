pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import "../Common/KeyUtils.js" as KeyUtils

FocusScope {
    id: root

    readonly property var log: Log.scoped("KeyCaptureField")

    property string key: ""
    property bool recording: false
    property string modKey: ""
    property string modSymbol: ""
    property bool capturesLoneModifiers: false
    property bool capturesWheel: false
    property bool keepsFormKeys: false
    property var _loneModifiers: []
    property bool _altShiftGhost: false

    signal captured(string key, bool loneModifier)

    implicitHeight: Theme.iconButtonSize
    Accessible.role: Accessible.Button
    Accessible.name: I18n.tr("Key", "noun, keybind editor row label for the key combination")
    Accessible.description: captureHint.visible ? captureHint.text : key
    Accessible.onPressAction: startRecording()

    function startRecording() {
        _loneModifiers = [];
        recording = true;
    }

    function stopRecording() {
        _loneModifiers = [];
        recording = false;
    }

    function captureKey(event) {
        if (KeyUtils.modifierFromQtKey(event.key)) {
            if (capturesLoneModifiers)
                _loneModifiers = KeyUtils.heldModifiers(event.key, event.modifiers, _loneModifiers);
            return;
        }
        switch (event.key) {
        // lock keys are toggles; NumLock picks the numpad keysym (KP_7 vs KP_Home) and must not become the bind
        case Qt.Key_NumLock:
        case Qt.Key_CapsLock:
        case Qt.Key_ScrollLock:
            return;
        }

        if (event.key === 0 && (event.modifiers & Qt.AltModifier)) {
            _altShiftGhost = true;
            if (_loneModifiers.length)
                _loneModifiers = KeyUtils.heldModifiers(Qt.Key_Shift, event.modifiers, _loneModifiers);
            return;
        }
        _loneModifiers = [];

        const mods = KeyUtils.modsFromEvent(event.modifiers);

        if (_altShiftGhost && (event.modifiers & Qt.AltModifier) && !mods.includes("Shift"))
            mods.push("Shift");
        _altShiftGhost = false;

        const token = KeyUtils.chordToken(event.key, event.modifiers, mods, event.nativeScanCode, modKey, modSymbol);
        if (!token) {
            log.warn("Unknown key:", event.key, "mods:", event.modifiers);
            return;
        }

        stopRecording();
        captured(token, false);
    }

    function isFormKey(event) {
        const chordModifiers = Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier;
        switch (event.key) {
        case Qt.Key_Escape:
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Tab:
            return (event.modifiers & (chordModifiers | Qt.ShiftModifier)) === 0;
        case Qt.Key_Backtab:
            return (event.modifiers & chordModifiers) === 0;
        }
        return false;
    }

    function captureKeyRelease(event) {
        if (_loneModifiers.length === 0 || !KeyUtils.modifierFromQtKey(event.key))
            return;
        const token = KeyUtils.bareModifierToken(_loneModifiers, modKey, modSymbol);
        stopRecording();
        captured(token, true);
    }

    function captureWheel(wheel) {
        let mods = [];
        if (wheel.modifiers & Qt.ControlModifier)
            mods.push("Ctrl");
        if (wheel.modifiers & Qt.ShiftModifier)
            mods.push("Shift");
        if (wheel.modifiers & Qt.AltModifier)
            mods.push("Alt");
        if (wheel.modifiers & Qt.MetaModifier)
            mods.push("Super");
        mods = KeyUtils.withSymbolicMod(mods, modKey, modSymbol);

        const wheelKey = wheelKeyName(wheel.angleDelta);
        if (!wheelKey)
            return;
        stopRecording();
        captured(KeyUtils.formatToken(mods, wheelKey), false);
    }

    function wheelKeyName(delta) {
        if (delta.y > 0)
            return "WheelScrollUp";
        if (delta.y < 0)
            return "WheelScrollDown";
        if (delta.x > 0)
            return "WheelScrollRight";
        if (delta.x < 0)
            return "WheelScrollLeft";
        return "";
    }

    onRecordingChanged: {
        if (recording)
            forceActiveFocus();
    }

    onActiveFocusChanged: {
        if (!activeFocus)
            stopRecording();
    }

    Keys.onPressed: event => {
        if (!recording)
            return;
        if (keepsFormKeys && isFormKey(event)) {
            stopRecording();
            event.accepted = event.key === Qt.Key_Escape;
            return;
        }
        event.accepted = true;
        captureKey(event);
    }

    Keys.onReleased: event => {
        if (!recording)
            return;
        event.accepted = true;
        captureKeyRelease(event);
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.cornerRadiusXS
        color: "transparent"
        border.color: root.recording ? Theme.primary : Theme.outline
        border.width: root.recording ? Theme.outlineWidthFocused : Theme.outlineWidth
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: root.recording ? Qt.CrossCursor : Qt.PointingHandCursor
        onClicked: {
            if (!root.recording)
                root.startRecording();
        }
        onWheel: wheel => {
            if (!root.recording || !root.capturesWheel) {
                wheel.accepted = false;
                return;
            }
            wheel.accepted = true;
            root.captureWheel(wheel);
        }
    }

    Row {
        anchors.left: parent.left
        anchors.leftMargin: Theme.spacingM
        anchors.right: recordButton.left
        anchors.rightMargin: Theme.spacingS
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacingM

        DIcon {
            name: "keyboard"
            size: Theme.iconSize
            color: Theme.surfaceVariantText
            anchors.verticalCenter: parent.verticalCenter
        }

        DKeycap {
            text: root.key
            visible: root.key !== "" && !root.recording
            anchors.verticalCenter: parent.verticalCenter
        }

        StyledText {
            id: captureHint
            text: root.recording ? I18n.tr("Press key...") : I18n.tr("Click to capture")
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.surfaceVariantText
            visible: root.key === "" || root.recording
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    DActionButton {
        id: recordButton
        anchors.right: parent.right
        anchors.rightMargin: Theme.spacingXS
        anchors.verticalCenter: parent.verticalCenter
        focusPolicy: Qt.TabFocus
        iconName: root.recording ? "close" : "radio_button_checked"
        iconColor: root.recording ? Theme.error : Theme.primary
        tooltipText: root.recording ? I18n.tr("Stop") : I18n.tr("Record", "verb, tooltip on button that captures a key combination")
        onClicked: root.recording ? root.stopRecording() : root.startRecording()
    }
}
