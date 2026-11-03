import QtQuick
import QtQuick.Controls
import qs.Common
import qs.DCommon.Widgets

FocusScope {
    id: root

    property var pluginService: null

    implicitHeight: settingsColumn.implicitHeight
    height: implicitHeight

    Column {
        id: settingsColumn
        anchors.fill: parent
        anchors.margins: 16
        spacing: Theme.spacingL

        Text {
            text: "Launcher Example Plugin Settings"
            font.pixelSize: 18
            font.weight: Theme.fontWeightMedium
            color: "#FFFFFF"
        }

        Text {
            text: "This plugin demonstrates the launcher plugin system with example items and actions."
            font.pixelSize: 14
            color: "#CCFFFFFF"
            wrapMode: Text.WordWrap
            width: parent.width - 32
        }

        Rectangle {
            width: parent.width - 32
            height: 1
            color: "#30FFFFFF"
        }

        Column {
            spacing: Theme.spacingM
            width: parent.width - 32

            Text {
                text: "Trigger Configuration"
                font.pixelSize: 16
                font.weight: Theme.fontWeightMedium
                color: "#FFFFFF"
            }

            Text {
                text: noTriggerToggle.checked ? "Items will always show in the launcher (no trigger needed)." : "Set the trigger text to activate this plugin. Type the trigger in the launcher to filter to this plugin's items."
                font.pixelSize: 12
                color: "#CCFFFFFF"
                wrapMode: Text.WordWrap
                width: parent.width
            }

            Row {
                spacing: Theme.spacingM

                CheckBox {
                    id: noTriggerToggle
                    text: "No trigger (always show)"
                    checked: loadSettings("noTrigger", false)

                    contentItem: Text {
                        text: noTriggerToggle.text
                        font.pixelSize: 14
                        color: "#FFFFFF"
                        leftPadding: noTriggerToggle.indicator.width + 8
                        verticalAlignment: Text.AlignVCenter
                    }

                    indicator: Rectangle {
                        implicitWidth: 20
                        implicitHeight: 20
                        radius: 4
                        border.color: noTriggerToggle.checked ? "#4CAF50" : "#60FFFFFF"
                        border.width: 2
                        color: noTriggerToggle.checked ? "#4CAF50" : "transparent"

                        Rectangle {
                            width: 12
                            height: 12
                            anchors.centerIn: parent
                            radius: 2
                            color: "#FFFFFF"
                            visible: noTriggerToggle.checked
                        }
                    }

                    onCheckedChanged: {
                        saveSettings("noTrigger", checked);
                        if (checked) {
                            saveSettings("trigger", "");
                        } else {
                            saveSettings("trigger", triggerField.text || "#");
                        }
                    }
                }
            }

            Row {
                spacing: Theme.spacingM
                anchors.left: parent.left
                anchors.right: parent.right
                visible: !noTriggerToggle.checked

                Text {
                    text: "Trigger:"
                    font.pixelSize: 14
                    color: "#FFFFFF"
                    anchors.verticalCenter: parent.verticalCenter
                }

                DTextField {
                    id: triggerField
                    width: 100
                    height: 40
                    text: loadSettings("trigger", "#")
                    placeholderText: "#"
                    backgroundColor: "#30FFFFFF"
                    textColor: "#FFFFFF"

                    onTextEdited: {
                        const newTrigger = text.trim();
                        saveSettings("trigger", newTrigger || "#");
                        saveSettings("noTrigger", newTrigger === "");
                    }
                }

                Text {
                    text: "Examples: #, !, @, !ex, etc."
                    font.pixelSize: 12
                    color: "#AAFFFFFF"
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        Rectangle {
            width: parent.width - 32
            height: 1
            color: "#30FFFFFF"
        }

        Column {
            spacing: Theme.spacingS
            width: parent.width - 32

            Text {
                text: "Example Items:"
                font.pixelSize: 14
                font.weight: Theme.fontWeightMedium
                color: "#FFFFFF"
            }

            Column {
                spacing: Theme.spacingXS
                leftPadding: 16

                Text {
                    text: "• Test Item 1, 2, 3 - Show toast notifications"
                    font.pixelSize: 12
                    color: "#CCFFFFFF"
                }

                Text {
                    text: "• Example Copy Action - Copy text to clipboard"
                    font.pixelSize: 12
                    color: "#CCFFFFFF"
                }

                Text {
                    text: "• Example Script Action - Demonstrate script execution"
                    font.pixelSize: 12
                    color: "#CCFFFFFF"
                }
            }
        }

        Rectangle {
            width: parent.width - 32
            height: 1
            color: "#30FFFFFF"
        }

        Column {
            spacing: Theme.spacingS
            width: parent.width - 32

            Text {
                text: "Usage:"
                font.pixelSize: 14
                font.weight: Theme.fontWeightMedium
                color: "#FFFFFF"
            }

            Column {
                spacing: Theme.spacingXS
                leftPadding: 16
                bottomPadding: 24

                Text {
                    text: "1. Open Launcher (Ctrl+Space or click launcher button)"
                    font.pixelSize: 12
                    color: "#CCFFFFFF"
                }

                Text {
                    text: noTriggerToggle.checked ? "2. Items are always visible in the launcher" : "2. Type your trigger (default: #) to filter to this plugin"
                    font.pixelSize: 12
                    color: "#CCFFFFFF"
                }

                Text {
                    text: noTriggerToggle.checked ? "3. Search works normally with plugin items included" : "3. Optionally add search terms: '# test' to find test items"
                    font.pixelSize: 12
                    color: "#CCFFFFFF"
                }

                Text {
                    text: "4. Select an item and press Enter to execute its action"
                    font.pixelSize: 12
                    color: "#CCFFFFFF"
                }
            }
        }
    }

    function saveSettings(key, value) {
        if (pluginService) {
            pluginService.savePluginData("launcherExample", key, value);
        }
    }

    function loadSettings(key, defaultValue) {
        if (pluginService) {
            return pluginService.loadPluginData("launcherExample", key, defaultValue);
        }
        return defaultValue;
    }
}
