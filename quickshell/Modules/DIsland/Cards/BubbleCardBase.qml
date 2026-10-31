import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Notifications
import qs.Modules.DIsland.Kit
import "../../../DCommon/Common/Contrast.js" as Contrast

// The open card of a bubble, on the notification popup's grid: the icon on the left, the title and,
// under it, the subtitle, all left aligned; then the kind's own body; then its actions, one full width row at the bottom.
// The wing gives it the popup's width and inner margin and grows to its implicitHeight.
Item {
    id: card

    // The wing's face: id, kind, icon (cardIcon first, else image), title, detail (the subtitle), progress, accent.
    property var bubble: null
    // The kind's controls go below the header.
    default property alias body: body.data
    // The card's IslandButton buttons, laid out as one row of equal parts (or their weights) at the bottom (C11).
    property alias actions: actionRow.data
    // A kind that draws its own header icon (the eye break's live eye) puts it in the icon box instead of the glyph.
    property Component iconComponent: null
    // Kept free at the header's end, left of the close button (a copied image's picture).
    property real headerEndRoom: 0
    // The hover tint's top corners: no rounder than the host's (a notch island's are square).
    property real headerTopLeftRadius: Theme.cornerRadius
    property real headerTopRightRadius: Theme.cornerRadius

    signal activated(var bubble)
    signal dismissed(var bubble)

    implicitHeight: column.implicitHeight

    Column {
        id: column

        width: parent.width
        spacing: Theme.spacingS

        Item {
            id: header

            readonly property string image: card.bubble?.cardIcon ? "" : card.bubble?.image ?? ""

            width: parent.width
            height: Math.max(iconBox.height, texts.implicitHeight)

            Rectangle {
                anchors.fill: parent
                anchors.margins: -Theme.spacingXS
                radius: Theme.cornerRadius
                topLeftRadius: card.headerTopLeftRadius
                topRightRadius: card.headerTopRightRadius
                color: headerMouse.containsMouse ? Theme.withAlpha(Theme.surfaceText, 0.08) : "transparent"
            }

            Item {
                id: iconBox

                width: NotificationMetrics.appIconSize
                height: width

                IslandAppIcon {
                    id: appIcon

                    anchors.fill: parent
                    visible: header.image !== "" && !card.iconComponent
                    size: parent.width
                    source: header.image
                    iconName: card.bubble?.icon || "apps"
                }

                DIcon {
                    anchors.centerIn: parent
                    visible: header.image === "" && !card.iconComponent
                    name: card.bubble?.cardIcon || card.bubble?.icon || ""
                    size: Theme.iconSize
                    // The bubble's accent where it keeps 3:1 on the island's surface (a light stock theme's pale error does not).
                    color: Contrast.readableOnAll([Theme.surface, Theme.surfaceContainer, Theme.surfaceContainerHigh, Theme.surfaceContainerHighest], [Theme[card.bubble?.accent ?? "primary"] ?? Theme.primary, Theme.surfaceText], 3)
                }

                Loader {
                    anchors.centerIn: parent
                    active: !!card.iconComponent
                    sourceComponent: card.iconComponent
                }
            }

            Column {
                id: texts

                anchors.left: iconBox.right
                anchors.leftMargin: NotificationMetrics.iconSpacing
                anchors.right: closeButton.left
                anchors.rightMargin: Theme.spacingXS + card.headerEndRoom
                // Centered on the icon while shorter than it, from the top once taller.
                y: Math.max(0, (iconBox.height - implicitHeight) / 2)
                spacing: NotificationMetrics.contentSpacing / 2

                StyledText {
                    id: title

                    width: parent.width
                    text: card.bubble?.title ?? ""
                    visible: text !== ""
                    wrapMode: Text.Wrap
                    maximumLineCount: NotificationMetrics.collapsedLines
                    elide: Text.ElideRight
                    font.pixelSize: NotificationMetrics.summarySize
                    font.weight: Theme.fontWeightMedium
                    color: Theme.surfaceText
                }

                StyledText {
                    width: parent.width
                    text: card.bubble?.detail ?? ""
                    visible: text !== ""
                    wrapMode: Text.Wrap
                    maximumLineCount: NotificationMetrics.collapsedLines
                    elide: Text.ElideRight
                    font.pixelSize: NotificationMetrics.bodySize
                    color: Theme.surfaceVariantText
                }
            }

            MouseArea {
                id: headerMouse

                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                Accessible.role: Accessible.Button
                Accessible.name: card.bubble?.title || card.bubble?.text || card.bubble?.app || I18n.tr("Island bubble", "island bubble: its accessible name when its face has no title")
                Accessible.description: I18n.tr("Right click to dismiss", "island bubble: what a right click on a bubble or its card does")
                Accessible.onPressAction: {
                    appIcon.poke();
                    card.activated(card.bubble);
                }
                onClicked: mouse => {
                    if (mouse.button === Qt.RightButton) {
                        card.dismissed(card.bubble);
                        return;
                    }
                    appIcon.poke();
                    card.activated(card.bubble);
                }
            }

            // Every open card closes from here: the card shuts and its info goes, the bubble leaving the normal way.
            IslandButton {
                id: closeButton

                anchors.right: parent.right
                // On the title's first line.
                y: texts.y + Math.round((title.implicitHeight / Math.max(1, title.lineCount) - height) / 2)
                role: "quiet"
                iconName: "close"
                buttonHeight: Theme.iconSize + Theme.spacingXS
                activeFocusOnTab: true
                Accessible.name: I18n.tr("Close", "island bubble card: close the card and dismiss its info")
                onClicked: card.dismissed(card.bubble)
            }
        }

        Column {
            id: body

            width: parent.width
            spacing: Theme.spacingS
            visible: children.length > 0
        }

        IslandButtonRow {
            id: actionRow

            width: parent.width
            visible: children.length > 0
        }
    }
}
