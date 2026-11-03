pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Modules.ControlCenter
import qs.Modules.ControlCenter.Widgets
import qs.DCommon.Widgets

Item {
    id: root

    implicitHeight: column.height

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    readonly property string title: I18n.tr("Running apps")
    property var toplevels: []
    readonly property int count: toplevels.length
    property int _desktopEntriesRevision: 0

    signal closeRequested
    signal dismissRequested

    onCountChanged: {
        if (count === 0)
            dismissRequested();
    }

    Connections {
        target: DesktopEntries

        function onApplicationsChanged() {
            root._desktopEntriesRevision++;
        }
    }

    DFlickable {
        anchors.fill: parent
        contentHeight: column.height
        clip: true

        Column {
            id: column
            width: parent.width
            spacing: CcMetrics.detailContentGap

            CcGroup {
                Repeater {
                    model: ScriptModel {
                        values: root.toplevels
                        objectProp: CompositorService.toplevelKey
                    }

                    CcListRow {
                        id: row

                        required property var modelData
                        readonly property string appId: modelData?.appId ?? ""
                        readonly property string appName: {
                            root._desktopEntriesRevision;
                            return Paths.getAppName(appId, DesktopEntries.heuristicLookup(appId));
                        }
                        readonly property var placement: CompositorService.toplevelPlacement(modelData)
                        readonly property string workspaceLabel: placement.workspace ? I18n.tr("Workspace %1", "control center running app row, %1 is a workspace number or name").arg(placement.workspace) : ""
                        readonly property string outputLabel: Quickshell.screens.length > 1 ? (SettingsData.getScreenDisplayName(Quickshell.screens.find(screen => screen.name === placement.output)) || placement.output) : ""

                        title: modelData?.title || appName
                        subtitle: [modelData?.title ? appName : "", workspaceLabel, outputLabel].filter(text => text !== "").join(" · ")
                        clickable: true
                        onClicked: {
                            modelData?.activate();
                            root.closeRequested();
                        }

                        leading: CcAppIcon {
                            appId: row.appId
                            iconSize: Theme.iconSizeLarge
                        }

                        DActionButton {
                            anchors.verticalCenter: parent.verticalCenter
                            iconName: "close"
                            iconColor: Theme.onSurfaceVariant
                            Accessible.name: I18n.tr("Close")
                            onClicked: row.modelData?.close()
                        }
                    }
                }
            }
        }
    }
}
