import QtQuick
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
            text: "Quick Notes Settings"
            font.pixelSize: 18
            font.weight: Theme.fontWeightMedium
            color: "#FFFFFF"
        }

        Text {
            text: "Demonstrates the plugin state API — notes are stored in a separate state file (quickNotesExample_state.json) rather than plugin_settings.json."
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

            Row {
                spacing: Theme.spacingM
                anchors.left: parent.left
                anchors.right: parent.right

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
                    text: loadSettings("trigger", "n")
                    placeholderText: "n"
                    backgroundColor: "#30FFFFFF"
                    textColor: "#FFFFFF"

                    onTextEdited: {
                        saveSettings("trigger", text.trim() || "n");
                    }
                }
            }
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
                text: "Storage"
                font.pixelSize: 16
                font.weight: Theme.fontWeightMedium
                color: "#FFFFFF"
            }

            Row {
                spacing: Theme.spacingM

                Text {
                    text: "Max notes:"
                    font.pixelSize: 14
                    color: "#FFFFFF"
                    anchors.verticalCenter: parent.verticalCenter
                }

                DTextField {
                    id: maxNotesField
                    width: 80
                    height: 40
                    text: loadSettings("maxNotes", 50).toString()
                    placeholderText: "50"
                    backgroundColor: "#30FFFFFF"
                    textColor: "#FFFFFF"

                    onTextEdited: {
                        const val = parseInt(text);
                        if (!isNaN(val) && val > 0)
                            saveSettings("maxNotes", val);
                    }
                }
            }

            Text {
                text: {
                    const count = loadState("notes", []).length;
                    return "Currently storing " + count + " note(s)";
                }
                font.pixelSize: 12
                color: "#AAFFFFFF"
            }

            Rectangle {
                width: clearRow.implicitWidth + 24
                height: clearRow.implicitHeight + 16
                radius: 8
                color: clearMouseArea.containsMouse ? "#40FF5252" : "#30FF5252"

                Row {
                    id: clearRow
                    anchors.centerIn: parent
                    spacing: Theme.spacingS

                    Text {
                        text: "🗑"
                        font.pixelSize: 14
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: "Clear all notes"
                        font.pixelSize: 14
                        color: "#FF5252"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    id: clearMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (pluginService) {
                            pluginService.clearPluginState("quickNotesExample");
                        }
                    }
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
                text: "API Usage (for plugin developers):"
                font.pixelSize: 14
                font.weight: Theme.fontWeightMedium
                color: "#FFFFFF"
            }

            Column {
                spacing: Theme.spacingXS
                leftPadding: 16
                bottomPadding: 24

                Text {
                    text: "• pluginService.savePluginState(id, key, value)"
                    font.pixelSize: 12
                    color: "#CCFFFFFF"
                    font.family: "monospace"
                }

                Text {
                    text: "  Writes to ~/.local/state/.../id_state.json"
                    font.pixelSize: 11
                    color: "#AAFFFFFF"
                }

                Text {
                    text: "• pluginService.loadPluginState(id, key, default)"
                    font.pixelSize: 12
                    color: "#CCFFFFFF"
                    font.family: "monospace"
                }

                Text {
                    text: "  Reads from the per-plugin state file"
                    font.pixelSize: 11
                    color: "#AAFFFFFF"
                }

                Text {
                    text: "• pluginService.clearPluginState(id)"
                    font.pixelSize: 12
                    color: "#CCFFFFFF"
                    font.family: "monospace"
                }

                Text {
                    text: "  Clears all state for a plugin"
                    font.pixelSize: 11
                    color: "#AAFFFFFF"
                }

                Text {
                    text: "• pluginService.removePluginStateKey(id, key)"
                    font.pixelSize: 12
                    color: "#CCFFFFFF"
                    font.family: "monospace"
                }

                Text {
                    text: "  Removes a single key from plugin state"
                    font.pixelSize: 11
                    color: "#AAFFFFFF"
                }
            }
        }
    }

    function saveSettings(key, value) {
        if (pluginService)
            pluginService.savePluginData("quickNotesExample", key, value);
    }

    function loadSettings(key, defaultValue) {
        if (pluginService)
            return pluginService.loadPluginData("quickNotesExample", key, defaultValue);
        return defaultValue;
    }

    function loadState(key, defaultValue) {
        if (pluginService)
            return pluginService.loadPluginState("quickNotesExample", key, defaultValue);
        return defaultValue;
    }
}
