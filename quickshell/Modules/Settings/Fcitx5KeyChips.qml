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
    property var heldModifierKeys: []
    property real maxWidth

    readonly property real singleRowWidth: {
        let total = -spacing;
        for (let i = 0; i < children.length; i++) {
            const item = children[i];
            if (item !== chips && (item !== recordingChip || recording))
                total += item.implicitWidth + spacing;
        }
        return total;
    }

    signal keysEdited(var keys)

    width: Math.min(maxWidth, singleRowWidth)
    spacing: Theme.spacingS

    function stopRecording() {
        recording = false;
        heldModifierKeys = [];
    }

    function commit(key) {
        stopRecording();
        if (key === "" || keys.includes(key))
            return;
        keysEdited(keys.concat(key));
    }

    function modifierKey(event) {
        const modifier = KeyUtils.modifierFromQtKey(event.key);
        // Qt can report key 0 for the second modifier of Alt+Shift.
        if (!modifier && event.key !== 0)
            return "";
        return Fcitx5Schema.modifierOnlyKey(modifier, event.nativeScanCode, event.modifiers & Qt.ShiftModifier);
    }

    function capture(event) {
        const heldKey = modifierKey(event);
        if (heldKey) {
            if (!heldModifierKeys.includes(heldKey))
                heldModifierKeys = heldModifierKeys.concat(heldKey);
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
        const token = KeyUtils.chordToken(event.key, event.modifiers, mods.filter(mod => mod !== "Shift"), event.nativeScanCode, "", "");
        if (!token)
            return;
        const key = Fcitx5Schema.fcitxKey(token, mods.includes("Shift"));
        if (allowModifierless || key.includes("+"))
            commit(key);
    }

    function captureRelease(event) {
        if (!allowModifierOnly || heldModifierKeys.length === 0 || !modifierKey(event))
            return;
        commit(Fcitx5Schema.modifierChord(heldModifierKeys));
    }

    Repeater {
        id: chips
        model: root.keys

        delegate: Rectangle {
            id: chip

            required property string modelData
            required property int index

            implicitWidth: chipRow.implicitWidth + Theme.spacingM + Theme.spacingXS
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

    DActionButton {
        id: addButton

        readonly property bool capturing: root.recording

        buttonSize: Theme.buttonHeightXS
        backgroundColor: root.recording ? "transparent" : Theme.secondaryContainer
        iconName: root.recording ? "close" : "add"
        iconColor: root.recording ? Theme.error : Theme.onSecondaryContainer
        tooltipText: root.recording ? I18n.tr("Stop") : I18n.tr("Add")
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
