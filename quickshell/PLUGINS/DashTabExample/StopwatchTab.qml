import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Plugins
import qs.Modules.DDash
import qs.Modules.DDash.Overview

DashTabComponent {
    id: root

    property bool running: false
    property real startedAt: 0
    property real banked: 0
    property var laps: []
    property real now: 0

    readonly property real elapsed: banked + (running ? Math.max(0, now - startedAt) : 0)
    readonly property bool showHundredths: options.hundredths !== false
    readonly property var visibleLaps: laps.slice(0, options.laps ?? 5)

    focusTarget: startButton
    implicitHeight: Math.max(DashMetrics.tabMinHeight, content.implicitHeight + Theme.spacingL * 2)
    menuActions: [
        {
            label: I18n.trFor("dashTabExample", "Reset"),
            iconName: "restart_alt",
            enabled: root.elapsed > 0,
            action: () => root.reset()
        }
    ]

    onPluginIdChanged: restore()
    onPluginServiceChanged: restore()

    function restore() {
        if (!pluginService || !pluginId)
            return;
        const saved = pluginService.loadPluginState(pluginId, "stopwatch", null);
        if (!saved)
            return;
        running = saved.running === true;
        startedAt = Number(saved.startedAt) || 0;
        banked = Number(saved.banked) || 0;
        laps = Array.isArray(saved.laps) ? saved.laps : [];
        now = Date.now();
    }

    function save() {
        pluginService?.savePluginState(pluginId, "stopwatch", {
            running: running,
            startedAt: startedAt,
            banked: banked,
            laps: laps
        });
    }

    function toggle() {
        now = Date.now();
        if (running) {
            banked += now - startedAt;
            running = false;
        } else {
            startedAt = now;
            running = true;
        }
        save();
    }

    function lap() {
        if (!running)
            return;
        now = Date.now();
        laps = [elapsed].concat(laps).slice(0, 99);
        save();
    }

    function reset() {
        running = false;
        startedAt = 0;
        banked = 0;
        laps = [];
        save();
    }

    function pad2(value) {
        return String(value).padStart(2, "0");
    }

    function format(ms) {
        const centis = Math.floor(ms / 10);
        const seconds = Math.floor(centis / 100);
        const minutes = Math.floor(seconds / 60);
        const hours = Math.floor(minutes / 60);
        const clock = (hours > 0 ? hours + ":" : "") + pad2(minutes % 60) + ":" + pad2(seconds % 60);
        return showHundredths ? clock + "." + pad2(centis % 100) : clock;
    }

    function restoreFocus() {
        startButton.forceActiveFocus(Qt.OtherFocusReason);
    }

    function handleKeyEvent(event) {
        if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier))
            return false;
        switch (event.key) {
        case Qt.Key_Space:
            toggle();
            return true;
        case Qt.Key_L:
            lap();
            return true;
        case Qt.Key_R:
            reset();
            return true;
        }
        return false;
    }

    Timer {
        interval: root.showHundredths ? 40 : 200
        repeat: true
        triggeredOnStart: true
        running: root.live && root.running
        onTriggered: root.now = Date.now()
    }

    Column {
        id: content
        anchors.centerIn: parent
        width: Math.min(parent.width, DashMetrics.gridRowUnit * 5)
        spacing: Theme.spacingL

        NumericText {
            anchors.horizontalCenter: parent.horizontalCenter
            isMonospace: false
            text: root.format(root.elapsed)
            font.pixelSize: Theme.fontSizeDisplayLarge
            font.weight: Theme.fontWeightMedium
            color: root.running ? Theme.primary : Theme.surfaceText
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.spacingS

            DButton {
                text: root.running ? I18n.trFor("dashTabExample", "Lap") : I18n.trFor("dashTabExample", "Reset")
                reserveText: I18n.trFor("dashTabExample", "Reset")
                iconName: root.running ? "flag" : "restart_alt"
                enabled: root.running || root.elapsed > 0
                backgroundColor: Theme.secondaryContainer
                textColor: Theme.onSecondaryContainer
                onClicked: root.running ? root.lap() : root.reset()
            }

            DButton {
                id: startButton
                text: root.running ? I18n.trFor("dashTabExample", "Pause") : root.elapsed > 0 ? I18n.trFor("dashTabExample", "Resume") : I18n.trFor("dashTabExample", "Start")
                reserveText: I18n.trFor("dashTabExample", "Resume")
                iconName: root.running ? "pause" : "play_arrow"
                onClicked: root.toggle()
            }
        }

        Card {
            id: lapCard
            width: parent.width
            height: lapList.implicitHeight + pad * 2
            visible: root.visibleLaps.length > 0

            Column {
                id: lapList
                width: parent.width

                Repeater {
                    model: root.visibleLaps

                    Item {
                        id: lapRow

                        required property int index
                        required property real modelData

                        width: lapList.width
                        height: Theme.buttonHeightXS

                        StyledText {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: I18n.trFor("dashTabExample", "Lap %1").arg(root.laps.length - lapRow.index)
                            font.pixelSize: Theme.fontSizeMedium
                            color: lapCard.mutedColor
                        }

                        NumericText {
                            anchors.right: total.left
                            anchors.rightMargin: Theme.spacingXL
                            anchors.verticalCenter: parent.verticalCenter
                            isMonospace: false
                            text: root.format(lapRow.modelData - (root.laps[lapRow.index + 1] ?? 0))
                            font.pixelSize: Theme.fontSizeMedium
                            color: lapCard.contentColor
                        }

                        NumericText {
                            id: total
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            isMonospace: false
                            text: root.format(lapRow.modelData)
                            font.pixelSize: Theme.fontSizeMedium
                            color: lapCard.mutedColor
                        }
                    }
                }
            }
        }
    }
}
