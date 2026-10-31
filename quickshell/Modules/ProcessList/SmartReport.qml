import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Settings.Widgets
import qs.DCommon.Widgets
import "Drives.js" as Drives

// A drive's full SMART report. It is read through the unlocked root helper, so one password prompt covers every drive.
Column {
    id: root

    property var drive: null
    property bool collapsed: true
    property bool wanted: false

    // "idle" | "running" | "done" | "error"
    property string state_: "idle"
    property var sections: []
    property string errorText: ""
    property int _gen: 0
    readonly property bool unlocked: DgopService.unlocked

    readonly property var sectionTitles: ({
            "health": I18n.tr("Health"),
            "errors": I18n.tr("Errors"),
            // smartctl's own JSON names; no translatable label
            "attributes": "ata_smart_attributes (value / worst / thresh / raw)",
            "selftest": "self_test_log"
        })

    function reportText() {
        if (state_ !== "done" && state_ !== "error")
            return "";
        return [I18n.tr("Full SMART report", "drive health report from smartctl")].concat(sections.map(sec => [sectionTitles[sec.id] || sec.id].concat(sec.rows.map(r => r.key + ": " + r.value)).join("\n")), errorText ? [errorText] : []).join("\n\n");
    }

    function run() {
        const gen = ++_gen;
        sections = [];
        errorText = "";
        if (!unlocked || !drive?.device) {
            state_ = "idle";
            return;
        }
        state_ = "running";
        DgopService.request("drives.smart", {
            "device": drive.device
        }, response => {
            if (gen !== _gen)
                return;
            if (!response.result) {
                state_ = response.error === "locked" ? "idle" : "error";
                errorText = response.error ?? "";
                return;
            }
            const r = Drives.parseReport(response.result.output ?? "");
            if (!r.sections.length && r.error) {
                errorText = r.error;
                state_ = "error";
                return;
            }
            sections = r.sections;
            errorText = r.error;
            state_ = "done";
        });
    }

    // Read when the card is open, not for every drive at once: smartctl wakes a sleeping disk.
    readonly property bool shouldRun: unlocked && wanted && !!drive?.device && !drive.asleep
    onShouldRunChanged: {
        if ((shouldRun && state_ === "idle") || !unlocked)
            run();
    }

    visible: state_ !== "idle"
    spacing: Theme.spacingS

    CollapsibleHeader {
        text: I18n.tr("Full SMART report", "drive health report from smartctl")
        collapsed: root.collapsed
        onToggled: root.collapsed = !root.collapsed
    }

    DSpinner {
        size: Theme.iconSize
        visible: !root.collapsed && root.state_ === "running"
        anchors.horizontalCenter: parent.horizontalCenter
    }

    SettingsNoteRow {
        width: parent.width
        visible: !root.collapsed && root.state_ === "done" && root.sections.length === 0 && root.errorText === ""
        text: I18n.tr("No results")
    }

    SettingsNoteRow {
        width: parent.width
        visible: !root.collapsed && (root.state_ === "error" || root.state_ === "done") && root.errorText !== ""
        text: root.errorText
        monospace: true
        maxHeight: 160
    }

    Repeater {
        model: !root.collapsed && root.state_ === "done" ? root.sections : []

        SettingsGroup {
            id: group
            required property var modelData
            width: parent.width
            customPaddingV: 0
            customPaddingH: 0

            Item {
                width: group.width
                height: heading.implicitHeight + Theme.spacingS * 2

                StyledText {
                    id: heading
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.sectionTitles[group.modelData.id] || group.modelData.id
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Theme.fontWeightMedium
                    font.family: group.modelData.id === "attributes" || group.modelData.id === "selftest" ? Theme.monoFontFamily : Theme.fontFamily
                    color: Theme.surfaceVariantText
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                }
            }

            Repeater {
                model: group.modelData.rows

                Item {
                    id: line
                    required property var modelData
                    width: group.width
                    height: Math.max(key.implicitHeight, val.implicitHeight) + Theme.spacingS * 2

                    StyledText {
                        id: key
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width * 0.45
                        text: line.modelData.key
                        font.family: Theme.monoFontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceText
                        wrapMode: Text.NoWrap
                        elide: Text.ElideRight
                    }

                    StyledText {
                        id: val
                        anchors.left: key.right
                        anchors.right: parent.right
                        anchors.margins: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        text: String(line.modelData.value)
                        font.pixelSize: Theme.fontSizeSmall
                        font.features: {
                            "tnum": 1
                        }
                        color: Theme.surfaceVariantText
                        horizontalAlignment: Text.AlignRight
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }
    }
}
