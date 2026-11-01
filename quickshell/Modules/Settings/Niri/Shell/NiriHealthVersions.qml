pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// Saved versions of the page config, newest first; a failed one is the version niri refused.
Column {
    id: root

    readonly property var versions: NiriPageService.history

    spacing: Theme.spacingS

    NiriHealthHeading {
        text: I18n.tr("Versions", "niri health popover section, saved versions of the page config")
    }

    StyledText {
        visible: root.versions.length === 0
        text: I18n.tr("No version saved yet", "niri health versions, empty list")
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
    }

    Repeater {
        model: root.versions

        Item {
            id: version

            required property var modelData

            width: root.width
            height: Math.max(versionChip.height, versionText.implicitHeight) + Theme.spacingXS * 2

            StyledText {
                id: versionText
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("v%1 · %2", "niri health versions, version number and saved date").arg(version.modelData.n).arg(new Date(version.modelData.time).toLocaleString(Qt.locale(), Locale.ShortFormat))
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
            }

            NiriHealthChip {
                id: versionChip
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: version.modelData.failed
                text: I18n.tr("Failed", "niri health versions, niri refused this version")
                tone: Theme.error
            }
        }
    }
}
