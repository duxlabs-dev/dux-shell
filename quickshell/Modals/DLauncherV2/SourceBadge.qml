import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.Common

Item {
    id: root

    property string source: ""
    property int glyphSize: Theme.iconSizeSmall
    property bool badgeVisible: true

    readonly property var sourceAsset: ({
            "flatpak": "../../assets/package-sources/flatpak.svg",
            "snap": "../../assets/package-sources/snap.svg",
            "appimage": "../../assets/package-sources/appimage.svg",
            "nix": "../../assets/package-sources/nix.svg"
        })

    readonly property var themeIcon: ({
            "steam": "steam",
            "waydroid": "waydroid"
        })

    readonly property string iconSource: {
        if (sourceAsset[source])
            return Qt.resolvedUrl(sourceAsset[source]);
        if (themeIcon[source])
            return Quickshell.iconPath(themeIcon[source], true);
        return "";
    }

    visible: badgeVisible && SettingsData.dankLauncherV2ShowSourceBadges && iconSource.length > 0
    implicitWidth: glyphSize
    implicitHeight: glyphSize

    IconImage {
        anchors.fill: parent
        source: root.iconSource
        implicitSize: root.glyphSize * 2
        backer.sourceSize: Qt.size(root.glyphSize * 2, root.glyphSize * 2)
        smooth: true
        mipmap: true
        asynchronous: true
    }
}
