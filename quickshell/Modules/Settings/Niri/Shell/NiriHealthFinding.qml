import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Widgets

// One doctor finding: severity, what it means, the files involved, and the fix when there is one.
Item {
    id: root

    required property var health
    required property var finding

    readonly property bool isError: finding.severity === "error"

    function findingText(f) {
        const sameFile = f.files.every(file => file === f.files[0]);
        switch (f.kind) {
        case "duplicate-bind":
            return I18n.tr("%1 bound twice", "niri health finding, %1 is a key combo").arg(f.subject);
        case "override":
            return sameFile ? I18n.tr("%1 set twice", "niri health finding, %1 is a config option").arg(f.subject) : I18n.tr("%1 · a later file hides yours", "niri health finding, %1 is a key combo").arg(f.subject);
        case "replaced":
            return I18n.tr("%1 replaces yours", "niri health finding, %1 is a config block replaced whole").arg(f.subject);
        case "missing-include":
            return I18n.tr("%1 is missing", "niri health finding, %1 is an included file").arg(f.subject);
        case "not-included":
            return I18n.tr("%1 is not included: its settings are not applied", "niri health finding, %1 is a DMS config file").arg(f.subject);
        case "unused-rule":
            return I18n.tr("Rule %1 matches no app", "niri health finding, %1 is an app-id pattern").arg(f.subject);
        case "obsolete":
            return I18n.tr("%1 is obsolete", "niri health finding, %1 is a config option").arg(f.subject);
        case "duplicate-startup":
            return I18n.tr("%1 starts twice, from Autostart and this page", "niri health finding, %1 is an app started at startup").arg(f.subject);
        }
        return I18n.tr("%1 could not be read", "niri health finding, %1 is a config file").arg(f.subject);
    }

    height: Math.max(Theme.iconButtonSize, texts.implicitHeight) + Theme.spacingS * 2

    DIcon {
        id: severityIcon
        anchors.verticalCenter: parent.verticalCenter
        name: root.isError ? "error" : "warning"
        size: Theme.iconSizeMedium
        color: root.health.legible(root.isError ? Theme.error : Theme.warning, Theme.surfaceContainerHigh)
        Accessible.name: root.isError ? I18n.tr("Error") : I18n.tr("Warning")
    }

    Column {
        id: texts
        anchors.verticalCenter: parent.verticalCenter
        x: severityIcon.width + Theme.spacingM
        width: parent.width - x - (fixButton.visible ? fixButton.width + Theme.spacingM : 0)

        StyledText {
            width: parent.width
            text: root.findingText(root.finding)
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.surfaceText
            wrapMode: Text.WrapAnywhere
        }

        StyledText {
            width: parent.width
            visible: root.finding.files.length > 1 || root.finding.files[0] !== root.finding.subject
            text: root.finding.files.join(" → ")
            font.family: Theme.monoFontFamily
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WrapAnywhere
        }
    }

    DButton {
        id: fixButton
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        visible: root.finding.fix === "add-include"
        enabled: !root.health.checking
        text: I18n.tr("Add include", "niri health fix, adds the include line to config.kdl")
        onClicked: root.health.fix(root.finding)
    }
}
