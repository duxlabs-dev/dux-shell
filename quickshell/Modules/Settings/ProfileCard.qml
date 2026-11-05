import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

DCard {
    id: card

    required property var profile
    property bool compact: false
    property var targetScreen: null

    signal editRequested(string id)
    signal menuRequested(real x, real y, bool keyboard)

    readonly property bool isActive: profile.id === ConfigProfileService.activeProfileId

    implicitHeight: previewArea.height + nameRow.implicitHeight + Theme.spacingS * 2 + Theme.spacingXS
    pad: 0
    radius: Theme.cornerRadiusM
    color: SettingsMetrics.rowColor
    border.color: isActive ? Theme.primary : Theme.outlineMedium
    border.width: isActive ? Theme.outlineWidthFocused : Theme.layerOutlineWidth
    clickable: true
    Accessible.name: profile.name
    Accessible.description: !isActive ? "" : I18n.tr("Active") + (profile.sync ? ", " + I18n.tr("Synchronized", "config profile, screen reader: setting changes are saved into the active profile") : "")
    onClicked: ConfigProfileService.activate(profile.id)
    Keys.onPressed: event => {
        if (event.key !== Qt.Key_Menu && !(event.key === Qt.Key_F10 && event.modifiers & Qt.ShiftModifier))
            return;
        card.menuRequested(width / 2, height / 2, true);
        event.accepted = true;
    }

    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: eventPoint => card.menuRequested(eventPoint.position.x, eventPoint.position.y, false)
    }

    Item {
        id: previewArea
        z: 1
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.spacingS
        height: preview.implicitHeight

        ProfilePreview {
            id: preview
            anchors.fill: parent
            owner: card.profile
            targetScreen: card.targetScreen
        }

        PluginBadge {
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            anchors.margins: Theme.spacingXS
            iconName: "sync"
            tone: Theme.primary
            visible: card.isActive && !!card.profile.sync
        }
    }

    Row {
        id: nameRow
        z: 1
        anchors.top: previewArea.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Theme.spacingXS
        anchors.leftMargin: card.compact ? Theme.spacingS : Theme.spacingM
        anchors.rightMargin: Theme.spacingS
        spacing: Theme.spacingS

        StyledText {
            width: parent.width - (editButton.visible ? editButton.width + parent.spacing : 0)
            text: card.profile.name
            font.pixelSize: card.compact ? Theme.fontSizeSmall : Theme.fontSizeMedium
            font.weight: Theme.fontWeightMedium
            color: card.isActive ? Theme.primary : Theme.surfaceText
            elide: Text.ElideRight
            maximumLineCount: 1
            anchors.verticalCenter: parent.verticalCenter
        }

        DIconButton {
            id: editButton
            visible: !card.compact
            iconName: "edit"
            variant: "tonal"
            tooltipText: I18n.tr("Edit")
            anchors.verticalCenter: parent.verticalCenter
            onClicked: card.editRequested(card.profile.id)
        }
    }
}
