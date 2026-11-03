import QtQuick
import qs.Common
import qs.Modals.Common
import qs.DCommon.Widgets

DModal {
    id: root

    property string outputName: ""
    property var changes: []
    property int countdown: 10

    signal confirmed
    signal reverted

    shouldBeVisible: false
    allowStacking: true
    useOverlayLayer: true
    modalWidth: 420
    modalHeight: contentLoader.item ? contentLoader.item.implicitHeight + Theme.spacingM * 2 : 200

    Timer {
        id: countdownTimer
        interval: 1000
        repeat: true
        running: root.shouldBeVisible
        onTriggered: {
            root.countdown--;
            if (root.countdown <= 0) {
                root.reverted();
                root.close();
            }
        }
    }

    onOpened: {
        countdown = 10;
        countdownTimer.start();
    }

    onDialogClosed: {
        countdownTimer.stop();
    }

    onBackgroundClicked: {
        root.reverted();
        root.close();
    }

    content: Component {
        FocusScope {
            id: confirmContent

            anchors.fill: parent
            focus: true
            implicitHeight: mainColumn.implicitHeight

            Keys.onEscapePressed: event => {
                root.reverted();
                root.close();
                event.accepted = true;
            }

            Keys.onReturnPressed: event => {
                root.confirmed();
                root.close();
                event.accepted = true;
            }

            Column {
                id: mainColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: Theme.spacingM
                anchors.rightMargin: Theme.spacingM
                anchors.topMargin: Theme.spacingM
                spacing: Theme.spacingM

                StyledText {
                    text: I18n.tr("Confirm Display Changes")
                    font.pixelSize: Theme.fontSizeLarge
                    color: Theme.surfaceText
                    font.weight: Theme.fontWeightMedium
                }

                Rectangle {
                    width: parent.width
                    height: 70
                    radius: Theme.cornerRadius
                    color: Theme.foregroundColor(Theme.cardSurface, Theme.isFloatingWindow(root))
                    border.width: Theme.layerOutlineWidth
                    border.color: Theme.outlineMedium

                    StyledText {
                        anchors.centerIn: parent
                        text: root.countdown + "s"
                        font.pixelSize: Theme.fontSizeXLarge * 1.5
                        color: Theme.primary
                        font.weight: Theme.fontWeightMedium
                    }
                }

                Column {
                    width: parent.width
                    spacing: Theme.spacingXS
                    visible: root.changes.length > 0

                    Repeater {
                        model: root.changes

                        StyledText {
                            required property var modelData
                            text: modelData
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: 36

                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacingS

                        Rectangle {
                            width: Math.max(70, revertText.contentWidth + Theme.spacingM * 2)
                            height: 36
                            radius: Theme.cornerRadius
                            color: revertArea.containsMouse ? Theme.surfaceTextHover : Theme.withAlpha(Theme.surfaceTextHover, 0)
                            border.color: Theme.surfaceVariantAlpha
                            border.width: 1

                            StyledText {
                                id: revertText

                                anchors.centerIn: parent
                                text: I18n.tr("Revert", "verb, undo display changes in confirmation dialog")
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.surfaceText
                                font.weight: Theme.fontWeightMedium
                            }

                            MouseArea {
                                id: revertArea

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.reverted();
                                    root.close();
                                }
                            }
                        }

                        Rectangle {
                            width: Math.max(80, confirmText.contentWidth + Theme.spacingM * 2)
                            height: 36
                            radius: Theme.cornerRadius
                            color: confirmArea.containsMouse ? Qt.darker(Theme.primary, 1.1) : Theme.primary

                            StyledText {
                                id: confirmText

                                anchors.centerIn: parent
                                text: I18n.tr("Keep Changes")
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.background
                                font.weight: Theme.fontWeightMedium
                            }

                            MouseArea {
                                id: confirmArea

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.confirmed();
                                    root.close();
                                }
                            }

                            Behavior on color {
                                ColorAnimation {
                                    duration: Theme.shortDuration
                                    easing.type: Theme.standardEasing
                                }
                            }
                        }
                    }
                }
            }

            DActionButton {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: Theme.spacingM
                anchors.rightMargin: Theme.spacingM
                iconName: "close"
                Accessible.name: I18n.tr("Close")
                iconSize: Theme.iconSize - 4
                iconColor: Theme.surfaceText
                onClicked: {
                    root.reverted();
                    root.close();
                }
            }
        }
    }
}
