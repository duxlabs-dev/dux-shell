import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.Common
import qs.DCommon.Common as DCommon
import qs.DCommon.Widgets

Item {
    id: root

    property string appId: ""
    property real iconSize: Theme.iconSize
    readonly property int iconRequestSize: DCommon.Style.iconRasterSize(iconSize)
    property int _desktopEntriesRevision: 0

    implicitWidth: iconSize
    implicitHeight: iconSize

    Connections {
        target: DesktopEntries

        function onApplicationsChanged() {
            root._desktopEntriesRevision++;
        }
    }

    IconImage {
        id: image

        property string paintedFor: ""
        readonly property bool holdsCurrentIcon: paintedFor !== "" && paintedFor === root.appId
        readonly property bool showsFrame: status === Image.Ready || (holdsCurrentIcon && status === Image.Loading)

        anchors.fill: parent
        source: {
            root._desktopEntriesRevision;
            return root.appId ? Paths.getAppIcon(root.appId, DesktopEntries.heuristicLookup(root.appId)) : "";
        }
        backer.sourceSize: Qt.size(root.iconRequestSize, root.iconRequestSize)
        backer.retainWhileLoading: true
        smooth: true
        mipmap: true
        asynchronous: true
        visible: showsFrame
        onStatusChanged: {
            if (status !== Image.Ready)
                return;
            paintedFor = root.appId;
        }
    }

    DIcon {
        anchors.centerIn: parent
        name: "apps"
        size: root.iconSize
        color: Theme.onSurfaceVariant
        visible: image.status === Image.Error || image.source.toString() === ""
    }
}
