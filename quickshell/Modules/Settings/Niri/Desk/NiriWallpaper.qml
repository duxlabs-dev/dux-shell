import QtQuick
import qs.Common

// The user's wallpaper behind a drawn screen; the theme gradient while there is none or it is a plain color.
Item {
    id: root

    // Empty: the first screen's wallpaper
    property string screenName: ""

    readonly property string path: screenName ? SessionData.getMonitorWallpaper(screenName) : Theme.wallpaperPath

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop {
                position: 0
                color: Theme.primaryContainer
            }
            GradientStop {
                position: 1
                color: Theme.tertiaryContainer
            }
        }
    }

    Image {
        anchors.fill: parent
        source: {
            const wp = root.path;
            if (!wp || wp.startsWith("#"))
                return "";
            const path = wp.startsWith("file://") ? wp.substring(7) : wp;
            return "file://" + path.split('/').map(s => encodeURIComponent(s)).join('/');
        }
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: root.width
        asynchronous: true
    }
}
