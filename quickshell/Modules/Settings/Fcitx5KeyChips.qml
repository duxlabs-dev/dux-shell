import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets
import "../../Common/KeyUtils.js" as KeyUtils
import "../../Common/fcitx5Schema.js" as Fcitx5Schema

Flow {
    id: root

    property var keys: []
    property bool allowModifierless: true
    property bool allowModifierOnly: false
    property bool recording: false
    property var heldMods: []
    property real maxWidth: 400
    property var chipWidths: []
    readonly property real singleRowWidth: {
        let total = addButton.implicitWidth + spacing * keys.length;
        for (let i = 0; i < keys.length; i++)
            total += chipWidths[i] ?? 0;
        if (recording)
            total += recordingChip.implicitWidth + spacing;
        return total;
    }

    signal keysEdited(var keys)

    width: Math.min(maxWidth, singleRowWidth)
    spacing: Theme.spacingS

    function setChipWidth(index, width) {
        const next = chipWidths.slice();
        next[index] = width;
        chipWidths = next;
    }

    function stopRecording() {
        recording = false;
        heldMods = [];
    }

    function commit(key) {
        stopRecording();
        if (key === "" || keys.includes(key))
            return;
        keysEdited(keys.concat(key));
    }

    function capture(event) {
        if (KeyUtils.modifierFromQtKey(event.key)) {
            heldMods = KeyUtils.heldModifiers(event.key, event.modifiers, heldMods);
            return;
        }
        switch (event.key) {
        case Qt.Key_NumLock:
        case Qt.Key_CapsLock:
        case Qt.Key_ScrollLock:
            return;
        case Qt.Key_Escape:
            if (!(event.modifiers & ~Qt.KeypadModifier)) {
                stopRecording();
                return;
            }
        }
        const mods = KeyUtils.modsFromEvent(event.modifiers);
        if (mods.length === 0 && !allowModifierless)
            return;
        const token = KeyUtils.chordToken(event.key, event.modifiers, mods, event.nativeScanCode, "", "");
        if (token)
            commit(Fcitx5Schema.fcitxKey(token));
    }

    // A modifier pressed and released alone is the key, e.g. Shift as the toggle.
    function captureRelease(event) {
        if (!allowModifierOnly || heldMods.length !== 1 || !KeyUtils.modifierFromQtKey(event.key))
            return;
        commit(Fcitx5Schema.modifierOnlyKey(event.nativeScanCode));
    }

    Repeater {
        model: root.keys

        delegate: Rectangle {
            id: chip

            required property string modelData
            required property int index

            implicitWidth: chipRow.implicitWidth + Theme.spacingM + Theme.spacingXS
            onImplicitWidthChanged: root.setChipWidth(index, implicitWidth)
            onIndexChanged: root.setChipWidth(index, implicitWidth)
            Component.onCompleted: root.setChipWidth(index, implicitWidth)
            implicitHeight: Theme.buttonHeightXS
            radius: Theme.cornerRadiusS
            color: SettingsMetrics.controlSurface
            border.width: Theme.outlineWidth
            border.color: Theme.outlineVariant

            Row {
                id: chipRow

                anchors.verticalCenter: parent.verticalCenter
                x: Theme.spacingM
                spacing: Theme.spacingXS

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: chip.modelData
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Theme.fontWeightMedium
                    color: Theme.surfaceText
                }

                DActionButton {
                    anchors.verticalCenter: parent.verticalCenter
                    buttonSize: Theme.iconSizeSmall + Theme.spacingS
                    iconSize: Theme.iconSizeSmall
                    iconName: "close"
                    iconColor: Theme.surfaceVariantText
                    tooltipText: I18n.tr("Remove")
                    onClicked: root.keysEdited(root.keys.filter((_, i) => i !== chip.index))
                }
            }
        }
    }

    Rectangle {
        id: recordingChip

        visible: root.recording
        implicitWidth: recordingLabel.implicitWidth + Theme.spacingM * 2
        implicitHeight: Theme.buttonHeightXS
        radius: Theme.cornerRadiusS
        color: Theme.selectedContainer
        border.width: Theme.outlineWidth
        border.color: Theme.primary

        StyledText {
            id: recordingLabel

            anchors.centerIn: parent
            text: I18n.tr("Press key...")
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Theme.fontWeightMedium
            color: Theme.primary
        }
    }

    // The focused control is the capture target, never a text input (the active input method would
    // swallow the combo). `capturing` tells the settings modal not to move focus away meanwhile.
    DActionButton {
        id: addButton

        readonly property bool capturing: root.recording

        buttonSize: Theme.buttonHeightXS
        backgroundColor: root.recording ? "transparent" : Theme.secondaryContainer
        iconName: root.recording ? "close" : "add"
        iconColor: root.recording ? Theme.error : Theme.onSecondaryContainer
        tooltipText: root.recording ? I18n.tr("Stop") : I18n.tr("Add")
        Keys.priority: Keys.BeforeItem
        onClicked: {
            if (root.recording) {
                root.stopRecording();
                return;
            }
            root.recording = true;
            forceActiveFocus();
        }
        onActiveFocusChanged: {
            if (!activeFocus)
                root.stopRecording();
        }
        Keys.onPressed: event => {
            if (!root.recording)
                return;
            event.accepted = true;
            root.capture(event);
        }
        Keys.onTabPressed: event => {
            event.accepted = root.recording;
            if (root.recording)
                root.capture(event);
        }
        Keys.onBacktabPressed: event => {
            event.accepted = root.recording;
            if (root.recording)
                root.capture(event);
        }
        Keys.onReleased: event => {
            if (!root.recording)
                return;
            event.accepted = true;
            root.captureRelease(event);
        }
    }
}
