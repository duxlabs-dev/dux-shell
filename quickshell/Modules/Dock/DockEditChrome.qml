import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets

Rectangle {
    id: root

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    property string title: ""
    property bool canAdd: true
    readonly property var focusTargets: [addButton, settingsButton, finishButton]

    signal addRequested(var anchor)
    signal settingsRequested
    signal finished

    implicitWidth: content.implicitWidth + Theme.spacingL * 2
    implicitHeight: content.implicitHeight + Theme.spacingM * 2
    radius: Theme.cornerRadiusXL
    color: Theme.readableSurface
    border.color: BlurService.borderColor
    border.width: BlurService.borderWidth

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: mouse => mouse.accepted = true
    }

    Row {
        id: content
        anchors.centerIn: parent
        spacing: Theme.spacingM

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: root.title
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Theme.fontWeightMedium
            color: Theme.surfaceText
            elide: Text.ElideRight
        }

        DButton {
            id: addButton
            anchors.verticalCenter: parent.verticalCenter
            buttonHeight: Theme.buttonHeightS
            iconName: "add"
            text: I18n.tr("Add widget")
            backgroundColor: Theme.secondaryContainer
            textColor: Theme.onSecondaryContainer
            enabled: root.canAdd
            KeyNavigation.tab: settingsButton
            KeyNavigation.backtab: finishButton
            onClicked: root.addRequested(addButton)
        }

        DActionButton {
            id: settingsButton
            anchors.verticalCenter: parent.verticalCenter
            buttonSize: Theme.buttonHeightS
            iconName: "settings"
            Accessible.name: I18n.tr("Settings")
            KeyNavigation.tab: finishButton
            KeyNavigation.backtab: addButton
            onClicked: root.settingsRequested()
        }

        DButton {
            id: finishButton
            anchors.verticalCenter: parent.verticalCenter
            buttonHeight: Theme.buttonHeightS
            iconName: "check"
            text: I18n.tr("Finish")
            backgroundColor: Theme.primary
            textColor: Theme.onPrimary
            KeyNavigation.tab: addButton
            KeyNavigation.backtab: settingsButton
            onClicked: root.finished()
        }
    }
}
