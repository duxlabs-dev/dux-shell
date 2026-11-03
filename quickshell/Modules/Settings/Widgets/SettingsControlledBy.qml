pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets

StyledRect {
    id: root

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    property string target: ""
    property string section: ""
    property string settingLabel: ""
    property string reason: ""
    property var parentModal: null

    readonly property string resolvedTarget: target || "frame"
    readonly property string iconName: {
        switch (resolvedTarget) {
        case "surfaces":
            return "layers";
        case "shadows":
            return "tonality";
        default:
            return "frame_source";
        }
    }
    readonly property string buttonText: {
        switch (resolvedTarget) {
        case "surfaces":
            return I18n.tr("Interface style");
        case "shadows":
            return I18n.tr("Shadows");
        default:
            return I18n.tr("Open Frame", "settings: button that opens the Frame tab");
        }
    }
    readonly property string tabName: {
        switch (resolvedTarget) {
        case "surfaces":
            return "theme_surfaces";
        case "shadows":
            return "surface_shadows";
        default:
            return section === "frameConnectedOptions" ? "dankbar_settings" : "dankbar_appearance";
        }
    }

    width: parent?.width ?? 0
    height: contentRow.implicitHeight + Theme.spacingM * 2
    radius: Theme.cornerRadius
    color: Theme.withAlpha(Theme.primary, Theme.stateLayerHover)
    border.color: Theme.withAlpha(Theme.primary, Theme.stateLayerDrag)
    border.width: Theme.outlineWidth

    Row {
        id: contentRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Theme.spacingM
        anchors.rightMargin: Theme.spacingM
        spacing: Theme.spacingM

        DIcon {
            name: root.iconName
            size: Theme.iconSize
            color: Theme.primary
            anchors.verticalCenter: parent.verticalCenter
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - Theme.iconSize - openButton.width - Theme.spacingM * 2
            spacing: Theme.spacingXXS

            StyledText {
                text: root.settingLabel
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Theme.fontWeightMedium
                color: Theme.surfaceText
                width: parent.width
                wrapMode: Text.WordWrap
            }

            StyledText {
                text: root.reason
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                width: parent.width
                wrapMode: Text.WordWrap
                visible: root.reason !== ""
            }
        }

        DButton {
            id: openButton
            anchors.verticalCenter: parent.verticalCenter
            text: root.buttonText
            backgroundColor: Theme.primary
            textColor: Theme.primaryText
            buttonHeight: Theme.buttonHeightXS
            horizontalPadding: Theme.spacingM
            onClicked: {
                if (!root.parentModal)
                    return;
                if (root.section)
                    SettingsSearchService.navigateToSection(root.section);
                root.parentModal.navigateTo(root.tabName);
            }
        }
    }
}
