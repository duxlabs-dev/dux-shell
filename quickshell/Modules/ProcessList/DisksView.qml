pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets
import "Drives.js" as Drives

Item {
    id: root

    readonly property var drives: DriveService.drives ?? []
    readonly property bool hasDrives: drives.length > 0
    readonly property var mounts: DgopService.diskMounts ?? []
    // With drive data, only mounts outside every drive; without it (old core, no UDisks), all of them
    readonly property var looseMounts: hasDrives ? mounts.filter(m => !Drives.driveByMount(m.mount, drives)) : mounts

    Ref {
        service: DgopService
        modules: ["diskmounts"]
        active: root.visible
    }

    // Held until the first drive reply, so the cards do not shuffle in one by one on the first visit.
    readonly property bool ready: DriveService.loaded || !DriveService.polling

    DSpinner {
        anchors.centerIn: parent
        size: Theme.iconSize * 2
        visible: !root.ready
    }

    DFlickable {
        id: scroll
        anchors.fill: parent
        visible: root.ready
        contentWidth: width
        contentHeight: column.implicitHeight

        ColumnLayout {
            id: column
            width: scroll.width
            spacing: Theme.spacingL

            Repeater {
                model: root.drives.length

                DriveCard {
                    required property int index
                    Layout.fillWidth: true
                    expanded: index === 0
                    drive: root.drives[index]
                    mounts: root.mounts
                    onInstallRequested: DriveService.install()
                }
            }

            // Spacing 0 like SettingsCard: the label's own bottom gap sets the distance to the list.
            ColumnLayout {
                Layout.fillWidth: true
                visible: root.looseMounts.length > 0
                spacing: 0

                SettingsSectionLabel {
                    Layout.fillWidth: true
                    topGap: 0
                    text: I18n.tr("Mount Points", "mount points header in system monitor")
                }

                SettingsGroup {
                    Layout.fillWidth: true
                    customPaddingV: 0
                    customPaddingH: Theme.spacingL

                    Repeater {
                        model: root.looseMounts.length

                        RowLayout {
                            id: mountRow

                            required property int index
                            readonly property var mount: root.looseMounts[index] ?? ({})
                            readonly property real usedRatio: (parseFloat(mount.percent) || 0) / 100

                            width: parent?.width ?? 0
                            height: Theme.buttonHeightS
                            spacing: Theme.spacingL

                            DIcon {
                                name: "folder"
                                size: Theme.iconSizeSmall
                                color: Theme.surfaceVariantText
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: mountRow.mount.mount ?? ""
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.surfaceText
                                wrapMode: Text.NoWrap
                                elide: Text.ElideMiddle
                            }

                            StyledText {
                                Layout.preferredWidth: Theme.fontSizeMedium * 10
                                text: mountRow.mount.device ?? ""
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                wrapMode: Text.NoWrap
                                elide: Text.ElideMiddle
                            }

                            StyledText {
                                Layout.preferredWidth: Theme.fontSizeMedium * 7
                                text: mountRow.mount.fstype ?? ""
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                wrapMode: Text.NoWrap
                                elide: Text.ElideRight
                            }

                            Rectangle {
                                Layout.preferredWidth: Theme.fontSizeMedium * 10
                                Layout.preferredHeight: Theme.spacingS
                                radius: height / 2
                                color: Theme.surfaceContainerHighest

                                Rectangle {
                                    width: parent.width * Math.min(1, mountRow.usedRatio)
                                    height: parent.height
                                    radius: height / 2
                                    color: mountRow.usedRatio > 0.95 ? Theme.error : mountRow.usedRatio > 0.85 ? Theme.warning : Theme.primary
                                }
                            }

                            NumericText {
                                Layout.preferredWidth: Theme.fontSizeMedium * 12
                                horizontalAlignment: Text.AlignRight
                                text: (mountRow.mount.used ?? "") + " / " + (mountRow.mount.size ?? "")
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceText
                            }
                        }
                    }
                }
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Theme.spacingXL
                visible: !root.hasDrives && root.mounts.length === 0
                text: I18n.tr("No mount points found", "empty state in disk mounts list")
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceVariantText
            }
        }
    }
}
