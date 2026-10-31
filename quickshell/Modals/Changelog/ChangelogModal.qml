import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets

DFloatingWindow {
    id: root

    readonly property int modalWidth: 720
    readonly property int modalHeight: heightWithin(760, 80)

    signal changelogDismissed

    function show() {
        visible = true;
    }

    function dismiss() {
        ChangelogService.dismissChangelog();
        changelogDismissed();
        visible = false;
    }

    objectName: "changelogModal"
    title: I18n.tr("What's New", "changelog window title")
    implicitWidth: modalWidth
    implicitHeight: modalHeight
    minimumSize: Qt.size(modalWidth, modalHeight)
    maximumSize: Qt.size(modalWidth, modalHeight)
    visible: false

    onClosed: visible = false

    FocusScope {
        id: contentFocusScope
        anchors.fill: parent
        focus: true

        Keys.onEscapePressed: event => {
            root.dismiss();
            event.accepted = true;
        }

        Keys.onPressed: event => {
            switch (event.key) {
            case Qt.Key_Return:
            case Qt.Key_Enter:
                root.dismiss();
                event.accepted = true;
                break;
            }
        }

        DWindowHeader {
            id: headerRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            controls: windowControls
            title: root.title
            onCloseRequested: root.dismiss()
        }

        DFlickable {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: headerRow.bottom
            anchors.bottom: parent.bottom
            clip: true
            contentHeight: mainColumn.height + fabBar.height + Theme.spacingL * 2
            contentWidth: width

            ChangelogContent {
                id: mainColumn
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(640, parent.width - Theme.spacingXL * 2)
            }
        }

        Row {
            id: fabBar
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.spacingL
            z: 2
            spacing: Theme.spacingM
            LayoutMirroring.enabled: I18n.isRtl

            DButton {
                id: notesButton
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("Release notes", "settings page and card title, notes for a DMS release")
                iconName: "article"
                buttonHeight: Theme.buttonHeightM
                backgroundColor: Theme.secondaryContainer
                textColor: Theme.onSecondaryContainer
                onClicked: PopoutService.openSettingsWithTab("updater_changelog")

                Loader {
                    anchors.fill: parent
                    z: -1
                    active: Theme.elevationEnabled
                    sourceComponent: ElevationShadow {
                        level: Theme.elevationLevel3
                        targetColor: notesButton.color
                        targetRadius: notesButton.radius
                    }
                }
            }

            DFab {
                anchors.verticalCenter: parent.verticalCenter
                text: "Let's go"
                iconName: "check"
                colorRole: "primary"
                onClicked: root.dismiss()
            }
        }
    }

    FloatingWindowControls {
        id: windowControls
        targetWindow: root
    }
}
