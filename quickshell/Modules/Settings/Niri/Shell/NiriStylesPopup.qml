pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import qs.Common
import qs.DCommon.Widgets
import qs.Services
import qs.Widgets
import "../../../../Common/niri/presets.js" as Presets

// Styles: presets and saved profiles, applied in one go; hovering a thumbnail previews it on the mini desktop.
Popup {
    id: root

    readonly property var profiles: Array.isArray(SettingsData.niriPage["styles.profiles"]) ? SettingsData.niriPage["styles.profiles"] : []
    readonly property var presetNames: ({
            "compact": [I18n.tr("Compact", "niri style preset"), I18n.tr("Tight, thin ring", "niri style preset description")],
            "niri": [I18n.tr("niri default", "niri style preset"), I18n.tr("As niri ships", "niri style preset description")],
            "comfort": [I18n.tr("Comfortable", "niri style preset"), I18n.tr("Round, soft shadow", "niri style preset description")],
            "focus": [I18n.tr("Focus", "niri style preset"), I18n.tr("Centered column", "niri style preset description")]
        })
    readonly property real thumbWidth: {
        const w = width - leftPadding - rightPadding;
        const cols = Math.max(1, Math.floor((w + Theme.spacingS) / (150 + Theme.spacingS)));
        return (w - Theme.spacingS * (cols - 1)) / cols;
    }

    property bool saving: false

    function current(key) {
        return NiriPageService.get(key);
    }

    // Each set restarts the service's debounce, so the whole style lands in one apply.
    // Only style keys: a stored profile or a file never reaches custom KDL or other settings.
    function apply(values) {
        for (const key of Presets.styleKeys) {
            if (values[key] !== undefined)
                NiriPageService.set(key, values[key]);
        }
    }

    function saveProfile(name) {
        const trimmed = name.trim();
        if (!trimmed)
            return;
        NiriPageService.set("styles.profiles", profiles.concat([
            {
                "name": trimmed.slice(0, Presets.NAME_MAX),
                "values": Presets.snapshot(current)
            }
        ]));
        saving = false;
    }

    function deleteProfile(index) {
        NiriPageService.set("styles.profiles", profiles.filter((_, i) => i !== index));
    }

    y: (parent?.height ?? 0) + Theme.spacingXS
    width: Math.min(600, (parent?.Window.window?.width ?? 600) - Theme.spacingL * 2)
    height: Math.min(implicitHeight, (parent?.Window.window?.height ?? 700) * 0.8)
    margins: Theme.spacingL
    padding: Theme.spacingL
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
    // The popup is created during the click that opens it, so focus: true alone lands before it can
    // hold focus and the first Escape would fall through to the page: close it from a window shortcut
    // instead of taking focus on open (the forceActiveFocus attempt was reverted)
    Shortcut {
        sequence: "Escape"
        enabled: root.visible
        onActivated: root.close()
    }
    onClosed: {
        SettingsUiState.niriPreviewState = null;
        saving = false;
        transfer.reset();
    }

    background: Rectangle {
        color: Theme.surfaceContainerHigh
        radius: Theme.cornerRadiusL
        border.width: Theme.outlineWidth
        border.color: Theme.outlineVariant
    }

    component Heading: StyledText {
        topPadding: Theme.spacingM
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Theme.fontWeightBold
        font.capitalization: Font.AllUppercase
        color: Theme.surfaceVariantText
    }

    contentItem: DFlickable {
        implicitHeight: body.implicitHeight
        contentHeight: body.implicitHeight
        clip: true

        Column {
            id: body

            width: parent.width
            spacing: Theme.spacingS

            Row {
                width: parent.width
                spacing: Theme.spacingS

                DIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "palette"
                    size: Theme.iconSize
                    color: Theme.primary
                }

                StyledText {
                    id: titleText
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("Styles", "niri page header button, presets and saved profiles")
                    font.pixelSize: Theme.fontSizeLarge
                    font.weight: Theme.fontWeightBold
                    color: Theme.surfaceText
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - titleText.width - closeButton.width - Theme.iconSize - Theme.spacingS * 3
                    text: I18n.tr("Hover to preview", "niri styles popover hint")
                    elide: Text.ElideRight
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }

                DButton {
                    id: closeButton
                    anchors.verticalCenter: parent.verticalCenter
                    iconName: "close"
                    minimumWidth: Theme.iconButtonSize
                    backgroundColor: "transparent"
                    textColor: Theme.surfaceText
                    Accessible.name: I18n.tr("Close Styles", "niri styles popover close button")
                    onClicked: root.close()
                }
            }

            Heading {
                text: I18n.tr("Presets", "niri styles popover heading")
            }

            Flow {
                width: parent.width
                spacing: Theme.spacingS

                Repeater {
                    model: Presets.presets

                    NiriStylesThumb {
                        required property var modelData
                        width: root.thumbWidth
                        values: modelData.values
                        title: root.presetNames[modelData.id][0]
                        subtitle: root.presetNames[modelData.id][1]
                        selected: Presets.matches(modelData.values, root.current)
                        onActivated: root.apply(modelData.values)
                    }
                }
            }

            Heading {
                text: I18n.tr("Yours", "niri styles popover heading, saved profiles")
            }

            Flow {
                width: parent.width
                spacing: Theme.spacingS

                Repeater {
                    model: root.profiles

                    Column {
                        id: profile

                        required property var modelData
                        required property int index

                        width: root.thumbWidth

                        NiriStylesThumb {
                            width: parent.width
                            values: profile.modelData.values ?? {}
                            title: profile.modelData.name ?? ""
                            subtitle: I18n.tr("%1 settings", "niri saved style, number of settings").arg(Object.keys(values).length)
                            icon: "bookmark"
                            onActivated: root.apply(values)
                        }

                        DButton {
                            anchors.right: parent.right
                            iconName: "delete"
                            minimumWidth: Theme.iconButtonSize
                            backgroundColor: "transparent"
                            textColor: Theme.surfaceVariantText
                            Accessible.name: I18n.tr("Delete profile %1", "niri saved style delete button").arg(profile.modelData.name ?? "")
                            onClicked: root.deleteProfile(profile.index)
                        }
                    }
                }

                NiriStylesThumb {
                    width: root.thumbWidth
                    adding: true
                    title: I18n.tr("Save current", "niri styles, save the current settings as a profile")
                    subtitle: I18n.tr("As a new profile", "niri styles, save current hint")
                    onActivated: {
                        root.saving = true;
                        nameField.forceActiveFocus();
                    }
                }
            }

            Row {
                visible: root.saving
                width: parent.width
                spacing: Theme.spacingS

                DTextField {
                    id: nameField
                    width: parent.width - saveButton.width - cancelButton.width - Theme.spacingS * 2
                    placeholderText: I18n.tr("Name", "niri saved style name field")
                    maximumLength: Presets.NAME_MAX
                    onAccepted: root.saveProfile(text)
                }

                DButton {
                    id: saveButton
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("Save")
                    enabled: nameField.text.trim() !== ""
                    backgroundColor: Theme.primary
                    textColor: Theme.onPrimary
                    onClicked: root.saveProfile(nameField.text)
                }

                DButton {
                    id: cancelButton
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("Cancel")
                    backgroundColor: "transparent"
                    textColor: Theme.surfaceText
                    onClicked: {
                        nameField.text = "";
                        root.saving = false;
                    }
                }
            }

            NiriStylesTransfer {
                id: transfer
                width: parent.width
                onApplyRequested: values => root.apply(values)
            }
        }
    }
}
