import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets

FocusScope {
    id: root

    property var editingApp: null
    property string editAppId: ""
    property var transientSurfaceTracker: null
    property string editFolderId: ""

    readonly property string noFolderLabel: I18n.tr("None")
    // DDropdown selects by label; names can collide with generated suffixes.
    readonly property var folderChoices: {
        const folders = SessionData.launcherFolders;
        const names = new Set(folders.map(folder => folder.name));
        const used = new Set([noFolderLabel]);
        return folders.map(folder => {
            let label = folder.name;
            for (let n = 2; used.has(label) || (label !== folder.name && names.has(label)); n++)
                label = folder.name + " " + n;
            used.add(label);
            return {
                id: folder.id,
                label: label
            };
        });
    }

    signal closeRequested

    implicitHeight: headerRow.height + editFieldsColumn.height + buttonsRow.height + Theme.outlineWidth + Theme.spacingM * 3

    function loadOverride() {
        var existing = SessionData.getAppOverride(editAppId);
        editNameField.text = existing?.name || "";
        editIconField.text = existing?.icon || "";
        editCommentField.text = existing?.comment || "";
        editEnvVarsField.text = existing?.envVars || "";
        editExtraFlagsField.text = existing?.extraFlags || "";
        editFolderId = SessionData.launcherFolderForApp(editAppId)?.id ?? "";
        Qt.callLater(() => editNameField.forceActiveFocus());
    }

    function saveAppOverride() {
        var override = {};
        if (editNameField.text.trim())
            override.name = editNameField.text.trim();
        if (editIconField.text.trim())
            override.icon = editIconField.text.trim();
        if (editCommentField.text.trim())
            override.comment = editCommentField.text.trim();
        if (editEnvVarsField.text.trim())
            override.envVars = editEnvVarsField.text.trim();
        if (editExtraFlagsField.text.trim())
            override.extraFlags = editExtraFlagsField.text.trim();
        SessionData.setAppOverride(editAppId, override);
        saveFolder();
        closeRequested();
    }

    function saveFolder() {
        if (editFolderId === (SessionData.launcherFolderForApp(editAppId)?.id ?? ""))
            return;
        if (!editFolderId)
            SessionData.removeAppFromLauncherFolder(editAppId);
        else if (SessionData.getLauncherFolder(editFolderId))
            SessionData.addAppToLauncherFolder(editFolderId, editAppId);
    }

    function resetAppOverride() {
        SessionData.clearAppOverride(editAppId);
        closeRequested();
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            closeRequested();
            event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (event.modifiers & Qt.ControlModifier) {
                saveAppOverride();
                event.accepted = true;
            }
        } else if (event.key === Qt.Key_S && event.modifiers & Qt.ControlModifier) {
            saveAppOverride();
            event.accepted = true;
        }
    }

    Column {
        anchors.fill: parent
        spacing: Theme.spacingM

        Row {
            id: headerRow
            width: parent.width
            spacing: Theme.spacingM

            Rectangle {
                Accessible.role: Accessible.Button
                Accessible.name: I18n.tr("Back")
                width: Theme.buttonHeightS
                height: Theme.buttonHeightS
                radius: Theme.cornerRadius
                color: backButtonArea.containsMouse ? Theme.surfaceHover : Theme.withAlpha(Theme.surfaceHover, 0)

                DIcon {
                    anchors.centerIn: parent
                    name: "arrow_back"
                    size: Theme.iconSizeMedium
                    color: Theme.onSurface
                }

                MouseArea {
                    id: backButtonArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.closeRequested()
                }
            }

            Image {
                width: Theme.buttonHeightS
                height: Theme.buttonHeightS
                source: Paths.resolveIconUrl(root.editingApp?.icon || "application-x-executable")
                sourceSize.width: Theme.buttonHeightS
                sourceSize.height: Theme.buttonHeightS
                fillMode: Image.PreserveAspectFit
                anchors.verticalCenter: parent.verticalCenter
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXXS

                StyledText {
                    text: I18n.tr("Edit App")
                    font.pixelSize: Theme.fontSizeLarge
                    color: Theme.onSurface
                    font.weight: Theme.fontWeightMedium
                }

                StyledText {
                    text: root.editingApp?.name || ""
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.onSurfaceVariant
                }
            }
        }

        Rectangle {
            width: parent.width
            height: Theme.outlineWidth
            color: Theme.outlineMedium
        }

        DFlickable {
            width: parent.width
            height: parent.height - y - buttonsRow.height - Theme.spacingM
            contentHeight: editFieldsColumn.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: editFieldsColumn
                width: parent.width
                spacing: Theme.spacingS

                Column {
                    width: parent.width
                    spacing: Theme.spacingXS

                    StyledText {
                        text: I18n.tr("Name")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.onSurface
                        font.weight: Theme.fontWeightMedium
                    }

                    DTextField {
                        id: editNameField
                        width: parent.width
                        placeholderText: root.editingApp?.name || ""
                        keyNavigationTab: editIconField
                        keyNavigationBacktab: folderDropdown
                    }
                }

                Column {
                    width: parent.width
                    spacing: Theme.spacingXS

                    StyledText {
                        text: I18n.tr("Icon")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.onSurface
                        font.weight: Theme.fontWeightMedium
                    }

                    DTextField {
                        id: editIconField
                        width: parent.width
                        placeholderText: root.editingApp?.icon || ""
                        keyNavigationTab: editCommentField
                        keyNavigationBacktab: editNameField
                    }
                }

                Column {
                    width: parent.width
                    spacing: Theme.spacingXS

                    StyledText {
                        text: I18n.tr("Description", "noun, text field label")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.onSurface
                        font.weight: Theme.fontWeightMedium
                    }

                    DTextField {
                        id: editCommentField
                        width: parent.width
                        placeholderText: root.editingApp?.comment || ""
                        keyNavigationTab: editEnvVarsField
                        keyNavigationBacktab: editIconField
                    }
                }

                Column {
                    width: parent.width
                    spacing: Theme.spacingXS

                    StyledText {
                        text: I18n.tr("Environment Variables")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.onSurface
                        font.weight: Theme.fontWeightMedium
                    }

                    StyledText {
                        text: "KEY=value KEY2=value2"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.onSurfaceVariant
                    }

                    DTextField {
                        id: editEnvVarsField
                        width: parent.width
                        placeholderText: "VAR=value"
                        keyNavigationTab: editExtraFlagsField
                        keyNavigationBacktab: editCommentField
                    }
                }

                Column {
                    width: parent.width
                    spacing: Theme.spacingXS

                    StyledText {
                        text: I18n.tr("Extra Arguments")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.onSurface
                        font.weight: Theme.fontWeightMedium
                    }

                    DTextField {
                        id: editExtraFlagsField
                        width: parent.width
                        placeholderText: "--flag --option=value"
                        keyNavigationTab: folderDropdown
                        keyNavigationBacktab: editEnvVarsField
                    }
                }

                Column {
                    width: parent.width
                    spacing: Theme.spacingXS

                    StyledText {
                        text: I18n.tr("Folder")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.onSurface
                        font.weight: Theme.fontWeightMedium
                    }

                    DDropdown {
                        id: folderDropdown
                        width: parent.width
                        dropdownWidth: width
                        triggerHeight: editNameField.height
                        maxPopupHeight: Theme.menuMaxHeight
                        transientSurfaceTracker: root.transientSurfaceTracker
                        KeyNavigation.tab: editNameField
                        KeyNavigation.backtab: editExtraFlagsField
                        options: [root.noFolderLabel].concat(root.folderChoices.map(choice => choice.label))
                        currentValue: root.folderChoices.find(choice => choice.id === root.editFolderId)?.label ?? root.noFolderLabel
                        onValueChanged: value => root.editFolderId = root.folderChoices.find(choice => choice.label === value)?.id ?? ""
                    }
                }
            }
        }

        Row {
            id: buttonsRow
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.spacingM

            DButton {
                text: I18n.tr("Reset", "verb, button that restores defaults")
                backgroundColor: Theme.chipSurface
                textColor: Theme.error
                visible: SessionData.getAppOverride(root.editAppId) !== null
                onClicked: root.resetAppOverride()
            }

            DButton {
                text: I18n.tr("Cancel")
                backgroundColor: Theme.chipSurface
                textColor: Theme.onSurface
                onClicked: root.closeRequested()
            }

            DButton {
                text: I18n.tr("Save")
                onClicked: root.saveAppOverride()
            }
        }
    }
}
