import QtQuick
import qs.Common
import qs.Modules.DBar.Widgets
import qs.Modules.Notifications
import qs.DCommon.Widgets
import qs.Widgets

DPopout {
    id: root

    property var triggerScreen: null
    property string triggerSource: "dndDuration"
    readonly property var presets: triggerSource === "idleInhibit" ? IdleInhibitPresets : DndPresets

    layerNamespace: "dms:duration"
    popupWidth: 340
    popupHeight: contentLoader.item ? contentLoader.item.implicitHeight : 0
    triggerWidth: 40
    positioning: ""
    screen: triggerScreen
    shouldBeVisible: false

    function prepareForTrigger(source) {
        triggerSource = source;
    }

    onBackgroundClicked: close()

    Timer {
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: root.shouldBeVisible && root.presets === IdleInhibitPresets && IdleInhibitPresets.timed
        onTriggered: IdleInhibitPresets.syncNow()
    }

    content: Component {
        Item {
            implicitHeight: contentColumn.implicitHeight + PopoutMetrics.contentPadding * 2
            focus: true

            Keys.onPressed: event => {
                if (event.key !== Qt.Key_Escape)
                    return;
                root.close();
                event.accepted = true;
            }

            Column {
                id: contentColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: PopoutMetrics.contentPadding
                spacing: PopoutMetrics.contentGap

                Column {
                    id: optionList
                    width: parent.width
                    spacing: Theme.groupedListGap

                    Repeater {
                        id: optionRepeater
                        model: root.presets.presetOptions

                        DListItem {
                            required property var modelData
                            required property int index

                            width: optionList.width
                            firstInGroup: index === 0
                            lastInGroup: index === optionRepeater.count - 1 && !root.presets.active
                            Accessible.name: modelData.label
                            onClicked: {
                                root.presets.selectPreset(modelData);
                                root.close();
                            }

                            StyledText {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: Theme.spacingL
                                anchors.rightMargin: Theme.spacingL
                                anchors.verticalCenter: parent.verticalCenter
                                text: parent.modelData.label
                                font.pixelSize: Theme.fontSizeMedium
                                color: parent.contentColor
                                elide: Text.ElideRight
                            }
                        }
                    }

                    DListItem {
                        id: turnOffRow
                        width: optionList.width
                        implicitHeight: Theme.listItemTwoLineHeight
                        visible: root.presets.active
                        firstInGroup: false
                        lastInGroup: true
                        Accessible.name: I18n.tr("Turn off now")
                        onClicked: {
                            root.presets.turnOff();
                            root.close();
                        }

                        Row {
                            id: turnOffContent
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: Theme.spacingL
                            anchors.rightMargin: Theme.spacingL
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spacingS

                            DIcon {
                                id: turnOffIcon
                                name: "power_settings_new"
                                size: Theme.iconSizeSmall
                                color: Theme.error
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Column {
                                width: turnOffContent.width - turnOffIcon.width - turnOffContent.spacing
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.spacingXXS

                                StyledText {
                                    text: I18n.tr("Turn off now")
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Theme.fontWeightMedium
                                    color: Theme.error
                                }

                                StyledText {
                                    width: parent.width
                                    text: root.presets.status
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: turnOffRow.supportingContentColor
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
