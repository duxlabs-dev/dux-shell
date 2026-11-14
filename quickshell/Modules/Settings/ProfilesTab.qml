pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Modals.FileBrowser
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

Item {
    id: root

    property var parentModal: null

    readonly property var screenInfo: parentModal?.screen ?? Quickshell.screens[0] ?? null

    Component.onCompleted: ConfigProfileService.ensureDefault()

    Connections {
        target: ConfigProfileService
        function onProfileImported(id) {
            grid.openPage("profile_edit", id, true);
        }
    }

    SettingsPage {
        ProfileGrid {
            id: grid
            width: parent?.width ?? 0
            columns: width >= Theme.mediumBreakpoint ? 3 : width >= Theme.smallBreakpoint ? 2 : 1
            targetScreen: root.screenInfo
            parentModal: root.parentModal
        }

        SettingsFabBar {
            shown: ConfigProfileService.ready

            DFab {
                text: I18n.tr("Import")
                iconName: "download"
                colorRole: "secondaryContainer"
                onClicked: {
                    importBrowserLoader.active = true;
                    (importBrowserLoader.item as FileBrowserModal)?.open();
                }
            }

            DFab {
                text: I18n.tr("New profile")
                iconName: "add"
                onClicked: grid.openPage("profile_edit", "")
            }
        }
    }

    LazyLoader {
        id: importBrowserLoader
        active: false

        FileBrowserModal {
            parentModal: root.parentModal
            bucket: "profile_export"
            browserTitle: I18n.tr("Import")
            filters: ["*.tar.gz"]
            onAccepted: paths => ConfigProfileService.importProfile(paths[0])
        }
    }
}
