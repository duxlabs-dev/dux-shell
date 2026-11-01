import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets
import qs.Modules.Settings.Niri.Components
import "../../../../../Common/niri/sections/workspaces.js" as Ws
import "../../../../../Common/niri/bulk.js" as Bulk

// One bulk action at a time: pick it, fill its one or two captioned pickers, press the button.
NiriCard {
    id: root

    property BoardCard board: null

    readonly property var apps: Ws.apps(NiriService.windows)
    readonly property var appNames: apps.map(a => a.app)
    readonly property var laneNames: (board?.lanes ?? []).map(l => l.name || I18n.tr("%1 on %2").arg(l.idx).arg(l.output))

    property string action: "group"
    property string leftPick: ""
    property string rightPick: ""
    property bool confirming: false
    property string done: ""

    readonly property var steps: ({
            "group": {
                "title": I18n.tr("Group an app"),
                "tip": I18n.tr("Every window of the app goes to one workspace"),
                "leftName": I18n.tr("App"),
                "rightName": I18n.tr("To workspace"),
                "button": I18n.tr("Move")
            },
            "move": {
                "title": I18n.tr("Move a workspace"),
                "tip": I18n.tr("Every window of one workspace goes to another"),
                "leftName": I18n.tr("From"),
                "rightName": I18n.tr("To"),
                "button": I18n.tr("Move")
            },
            "close": {
                "title": I18n.tr("Close an app"),
                "tip": I18n.tr("Every window, every workspace"),
                "leftName": I18n.tr("App"),
                "rightName": "",
                "button": I18n.tr("Close all")
            }
        })
    readonly property var titles: Bulk.actions.map(a => steps[a].title)
    readonly property var step: steps[action]
    readonly property var choices: Bulk.choices(action, appNames, laneNames)
    readonly property string leftValue: Bulk.pick(leftPick, choices.left)
    readonly property string rightValue: Bulk.pick(rightPick, choices.right)
    readonly property bool ready: Bulk.ready(action, leftValue, rightValue, appNames, laneNames)
    readonly property int closeCount: Bulk.plan("close", NiriService.windows, leftValue, null, null).ids.length
    readonly property bool closing: action === "close"
    readonly property int pickCount: closing ? 1 : 2
    // The pickers share what the button leaves, never narrower than before (long app ids).
    readonly property real pickWidth: Math.max(Theme.iconButtonSize * 3.5, (pickArea.width - runButton.width - Theme.spacingM * pickCount) / pickCount)

    onActionChanged: {
        leftPick = "";
        rightPick = "";
        confirming = false;
        done = "";
    }

    function laneOf(label) {
        return board.lanes[laneNames.indexOf(label)] ?? null;
    }

    function run() {
        if (!ready)
            return;
        if (closing) {
            confirming = true;
            return;
        }
        const p = Bulk.plan(action, NiriService.windows, leftValue, laneOf(leftValue), laneOf(rightValue));
        if (!p.ids.length) {
            done = action === "group" ? I18n.tr("Every %1 window is already there").arg(leftValue) : I18n.tr("No windows to move");
            return;
        }
        board.moveWindows(p.ids, p.to);
        done = I18n.tr("%1 windows moved").arg(p.ids.length);
    }

    function cancel() {
        confirming = false;
        runButton.forceActiveFocus();
    }

    function closeAll() {
        confirming = false;
        const ids = Bulk.plan("close", NiriService.windows, leftValue, null, null).ids;
        board.closeWindows(ids);
        done = I18n.tr("Closed %1 windows").arg(ids.length);
    }

    component Pick: Column {
        property alias caption: captionText.text
        property alias options: drop.options
        property string value
        property alias emptyText: drop.emptyText
        signal picked(string value)

        spacing: Theme.spacingXXS
        // DDropdown writes currentValue itself on a pick, which would break a binding: push the value instead.
        onValueChanged: drop.currentValue = value

        StyledText {
            id: captionText
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
        }

        DDropdown {
            id: drop
            currentValue: parent.value
            compactMode: true
            dropdownWidth: root.pickWidth
            width: dropdownWidth
            backgroundColor: SettingsMetrics.controlSurface
            Accessible.name: captionText.text
            onValueChanged: value => parent.picked(value)
        }
    }

    icon: "select_all"
    title: I18n.tr("Bulk actions", "niri page card")

    Keys.onEscapePressed: event => {
        event.accepted = confirming;
        if (confirming)
            cancel();
    }

    DButtonGroup {
        id: segments
        // Too narrow for every title whole: the dropdown below takes over, never a cut label.
        visible: naturalWidth <= parent.width
        arrowKeysSelect: false
        model: root.titles
        currentIndex: Bulk.actions.indexOf(root.action)
        Accessible.name: root.title
        onSelectionChanged: (index, selected) => {
            if (selected)
                root.action = Bulk.actions[index];
        }
    }

    DDropdown {
        visible: !segments.visible
        compactMode: true
        dropdownWidth: parent.width
        width: dropdownWidth
        focusPolicy: Qt.StrongFocus
        backgroundColor: SettingsMetrics.controlSurface
        options: root.titles
        currentValue: root.step.title
        Accessible.name: root.title
        onValueChanged: value => root.action = Bulk.actions[root.titles.indexOf(value)] ?? root.action
    }

    StyledText {
        width: parent.width
        topPadding: Theme.spacingXS
        text: root.step.tip
        wrapMode: Text.WordWrap
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
    }

    Item {
        id: pickArea
        width: parent.width
        height: picks.height + Theme.spacingS

        Row {
            id: picks
            y: Theme.spacingS
            spacing: Theme.spacingM

            Pick {
                caption: root.step.leftName
                options: root.choices.left
                value: root.leftValue
                emptyText: root.action === "move" ? "" : I18n.tr("No windows")
                onPicked: value => root.leftPick = value
            }

            Pick {
                visible: !root.closing
                caption: root.step.rightName
                options: root.choices.right
                value: root.rightValue
                onPicked: value => root.rightPick = value
            }
        }

        DButton {
            id: runButton
            anchors.right: parent.right
            anchors.bottom: picks.bottom
            text: root.step.button
            enabled: root.ready
            backgroundColor: root.closing ? Theme.error : Theme.buttonBg
            textColor: root.closing ? Theme.onError : Theme.buttonText
            onClicked: root.run()
        }
    }

    Rectangle {
        width: parent.width
        visible: root.confirming
        height: visible ? confirmRow.implicitHeight + Theme.spacingM * 2 : 0
        radius: Theme.cornerRadiusM
        color: Theme.withAlpha(Theme.error, Theme.stateLayerPressed)

        Row {
            id: confirmRow

            x: Theme.spacingM
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - Theme.spacingM * 2
            spacing: Theme.spacingS

            DIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: "warning"
                size: Theme.iconSize
                color: Theme.error
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - x - yes.width - no.width - Theme.spacingS * 2
                wrapMode: Text.WordWrap
                text: I18n.tr("Close %1 %2 windows? No undo.").arg(root.closeCount).arg(root.leftValue)
                color: Theme.surfaceText
            }

            DButton {
                id: yes
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("Close all")
                backgroundColor: Theme.error
                textColor: Theme.onError
                onClicked: root.closeAll()
            }

            DButton {
                id: no
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("Cancel")
                backgroundColor: "transparent"
                // primary on the 10 % error wash falls to 4.47:1 in the light theme; surfaceText keeps 11.85 / 8.78.
                textColor: Theme.surfaceText
                onClicked: root.cancel()
            }
        }
    }

    StyledText {
        width: parent.width
        visible: root.done !== ""
        text: root.done
        color: Theme.surfaceVariantText
        font.pixelSize: Theme.fontSizeSmall
        Accessible.role: Accessible.StaticText
    }
}
