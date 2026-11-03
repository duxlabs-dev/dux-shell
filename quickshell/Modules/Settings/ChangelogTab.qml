import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import qs.Modules.Settings.Widgets

Item {
    id: root

    Ref {
        service: SystemUpdateService
        modules: ["releases"]
    }

    readonly property var releases: SystemUpdateService.releases?.releases ?? []
    property int selectedIndex: Math.max(0, releases.indexOf(SystemUpdateService.notesRelease))
    readonly property var selectedRelease: releases.length > selectedIndex ? releases[selectedIndex] : null
    readonly property bool feedMissing: releases.length === 0

    SettingsPage {
        SettingsCard {
            width: parent.width
            settingKey: "softwareUpdatesChangelog"
            tags: ["changelog", "release", "notes", "highlights"]

            // Reachable with an empty feed via search or `settings openWith`.
            SettingsRow {
                visible: root.feedMissing
                iconName: "cloud_off"
                title: I18n.tr("Release notes are unavailable", "empty state title when no release notes are loaded")
                subtitle: I18n.tr("They load with the next update check. Release notes are also published on GitHub.", "release notes empty state description")

                DButton {
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("Retry")
                    iconName: "refresh"
                    busy: SystemUpdateService.isChecking
                    enabled: !SystemUpdateService.isChecking
                    backgroundColor: SettingsMetrics.controlSurface
                    textColor: Theme.surfaceText
                    onClicked: SystemUpdateService.loadReleases(true)
                }

                DButton {
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("View on GitHub", "link to the release on GitHub")
                    iconName: "open_in_new"
                    backgroundColor: SettingsMetrics.controlSurface
                    textColor: Theme.surfaceText
                    onClicked: Qt.openUrlExternally("https://github.com/duxlabs-dev/dux-shell/releases")
                }
            }

            SettingsRow {
                visible: !root.feedMissing
                body: DFilterChips {
                    width: parent.width
                    model: root.releases.map(r => "v" + r.version)
                    currentIndex: root.selectedIndex
                    showCheck: false
                    showCounts: false
                    onSelectionChanged: index => root.selectedIndex = index
                }
            }

            SettingsRow {
                visible: !root.feedMissing
                paddingV: SettingsMetrics.heroPadding
                body: ReleaseNotesCard {
                    width: parent.width
                    release: root.selectedRelease
                }
            }
        }
    }
}
