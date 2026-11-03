import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Widgets

Column {
    id: root

    property var release: null
    property bool showTitle: true

    readonly property bool hasRelease: release !== null && release !== undefined
    readonly property var counts: hasRelease ? (release.counts || {}) : ({})
    readonly property var highlights: hasRelease ? (release.highlights || []) : []
    // A feed string only reaches a URL handler as a plain https link.
    readonly property string blogUrl: webUrl(hasRelease ? release.blogUrl : "")
    readonly property string releaseUrl: webUrl(hasRelease ? release.url : "")

    function webUrl(u) {
        return typeof u === "string" && /^https:\/\//.test(u) ? u : "";
    }

    spacing: Theme.spacingM

    Row {
        visible: root.showTitle && root.hasRelease
        spacing: Theme.spacingS

        StyledText {
            text: root.hasRelease ? "v" + root.release.version : ""
            font.pixelSize: Theme.fontSizeXLarge
            font.weight: Theme.fontWeightBold
            color: Theme.surfaceText
            anchors.verticalCenter: parent.verticalCenter
        }

        DBadge {
            visible: root.hasRelease && (root.release.codename || "") !== ""
            text: root.hasRelease ? root.release.codename || "" : ""
            color: Theme.primaryContainer
            textColor: Theme.accentOnPrimaryContainer
            anchors.verticalCenter: parent.verticalCenter
        }

        DBadge {
            visible: root.hasRelease && root.release.prerelease === true
            text: I18n.tr("Pre-release", "badge on a release that is not a stable version")
            color: Theme.chipSurface
            textColor: Theme.surfaceVariantText
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    StyledText {
        width: parent.width
        visible: root.hasRelease && (root.release.summary || "") !== ""
        text: root.hasRelease ? root.release.summary || "" : ""
        font.pixelSize: Theme.fontSizeMedium
        color: Theme.surfaceText
        wrapMode: Text.WordWrap
    }

    StyledText {
        width: parent.width
        visible: text !== ""
        text: {
            const parts = [];
            if (root.counts.breaking > 0)
                parts.push(I18n.tr("%1 breaking", "release counts, %1 is a number of breaking changes").arg(root.counts.breaking));
            if (root.counts.features > 0)
                parts.push(I18n.tr("%1 features", "release counts, %1 is a number").arg(root.counts.features));
            if (root.counts.fixes > 0)
                parts.push(I18n.tr("%1 fixes", "release counts, %1 is a number").arg(root.counts.fixes));
            if (root.counts.other > 0)
                parts.push(I18n.tr("%1 other", "release counts, %1 is a number of other changes").arg(root.counts.other));
            return parts.join(" · ");
        }
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    Column {
        width: parent.width
        visible: root.highlights.length > 0
        spacing: Theme.spacingS

        Repeater {
            model: root.highlights

            delegate: Row {
                id: highlightRow
                required property string modelData
                width: parent.width
                spacing: Theme.spacingS

                DIcon {
                    name: "arrow_right"
                    size: Theme.iconSizeSmall
                    color: Theme.primary
                    anchors.top: parent.top
                }

                StyledText {
                    width: parent.width - Theme.iconSizeSmall - Theme.spacingS
                    text: highlightRow.modelData
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceText
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    Flow {
        width: parent.width
        visible: root.hasRelease
        spacing: Theme.spacingS

        DButton {
            visible: root.blogUrl !== ""
            text: I18n.tr("Read the blog post", "release notes link")
            iconName: "article"
            backgroundColor: Theme.primary
            textColor: Theme.onPrimary
            onClicked: Qt.openUrlExternally(root.blogUrl)
        }

        DButton {
            visible: root.releaseUrl !== ""
            text: I18n.tr("View on GitHub", "link to the release on GitHub")
            iconName: "open_in_new"
            backgroundColor: Theme.chipSurface
            textColor: Theme.surfaceText
            onClicked: Qt.openUrlExternally(root.releaseUrl)
        }
    }
}
