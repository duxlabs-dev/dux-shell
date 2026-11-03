pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Widgets
import qs.Common
import qs.Modules.Notifications as Notifications
import qs.Services
import qs.DCommon.Widgets
import qs.DCommon.Session

Item {
    id: root

    property var instanceData: null
    property var lockHost: null
    readonly property var cfg: instanceData?.config ?? ({})
    readonly property int notificationMode: cfg.mode ?? 1
    readonly property bool resizable: true
    readonly property real minWidth: Theme.listItemTwoLineHeight * 2
    readonly property real minHeight: Theme.buttonHeightXS
    readonly property real defaultWidth: LockMetrics.notificationCardWidth
    readonly property real defaultHeight: fullContent ? LockMetrics.notificationMaxHeight : Theme.buttonHeightS

    readonly property var notifications: NotificationService.groupedNotifications
    readonly property int totalCount: {
        let count = 0;
        for (const group of notifications)
            count += group.count || 0;
        return count;
    }
    readonly property bool hasNotifications: totalCount > 0
    readonly property var appNameGroups: {
        const groups = {};
        for (const group of notifications) {
            const appName = (group.appName || "Unknown").toLowerCase();
            if (!groups[appName]) {
                groups[appName] = {
                    appName: group.appName || I18n.tr("Unknown"),
                    count: 0,
                    latestNotification: group.latestNotification
                };
            }
            groups[appName].count += group.count || 0;
            if (group.latestNotification && (!groups[appName].latestNotification || group.latestNotification.time > groups[appName].latestNotification.time))
                groups[appName].latestNotification = group.latestNotification;
        }
        return Object.values(groups).sort((a, b) => b.count - a.count);
    }

    readonly property bool editPlaceholder: !hasNotifications && (lockHost?.demoMode ?? false)
    readonly property bool chips: notificationMode === 2 && !editPlaceholder
    readonly property bool fullContent: notificationMode === 3 && !editPlaceholder
    readonly property var visibleGroups: appNameGroups.slice(0, LockMetrics.notificationLimit)

    implicitWidth: contentLoader.implicitWidth
    implicitHeight: hasNotifications || editPlaceholder ? contentLoader.implicitHeight : 0
    clip: true

    Loader {
        id: contentLoader
        anchors.fill: parent
        active: root.hasNotifications || root.editPlaceholder
        sourceComponent: {
            if (root.chips)
                return chipRowComponent;
            if (root.fullContent)
                return notificationListComponent;
            return countOnlyComponent;
        }
    }

    component Chip: Rectangle {
        default property alias content: chipContent.data
        readonly property real contentWidth: chipContent.implicitWidth
        height: Theme.buttonHeightXS
        width: contentWidth + Theme.spacingM * 2
        radius: Theme.cornerRadiusM
        color: Theme.notificationFloatingSurface
        border.width: Theme.layerOutlineWidth
        border.color: Theme.outlineVariant

        Row {
            id: chipContent
            anchors.centerIn: parent
            spacing: Theme.spacingXS
        }
    }

    Component {
        id: chipRowComponent

        Item {
            id: chipHost

            property int fitCount: root.visibleGroups.length
            // One width for every app chip keeps the row symmetric about the centre whatever the label lengths.
            property real chipWidth: 0
            property bool moreFits: true
            readonly property int hiddenCount: root.appNameGroups.length - fitCount
            implicitWidth: chipRow.implicitWidth
            implicitHeight: chipRow.implicitHeight

            function measure() {
                let widest = 0;
                for (let i = 0; i < chipRepeater.count; i++)
                    widest = Math.max(widest, chipRepeater.itemAt(i)?.contentWidth ?? 0);
                chipWidth = widest + Theme.spacingM * 2;
                const total = count => count * chipWidth + Math.max(0, count - 1) * chipRow.spacing;
                const overflow = count => root.appNameGroups.length > count ? moreMetrics.width + Theme.spacingM * 2 + chipRow.spacing : 0;
                let count = chipRepeater.count;
                while (count > 1 && total(count) + overflow(count) > width)
                    count--;
                fitCount = count;
                moreFits = total(count) + overflow(count) <= width;
            }

            onWidthChanged: Qt.callLater(measure)
            Component.onCompleted: measure()

            TextMetrics {
                id: moreMetrics
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Theme.fontWeightMedium
                text: I18n.tr("+ %1 more", "lock screen notification list overflow, %1 is a count of hidden apps").arg(root.appNameGroups.length)
                onWidthChanged: Qt.callLater(chipHost.measure)
            }

            Row {
                id: chipRow
                anchors.centerIn: parent
                spacing: Theme.spacingS

                Repeater {
                    id: chipRepeater
                    model: root.visibleGroups
                    onItemAdded: Qt.callLater(chipHost.measure)
                    onItemRemoved: Qt.callLater(chipHost.measure)

                    Chip {
                        id: chip

                        required property var modelData
                        required property int index
                        readonly property string appIcon: NotificationService.notificationAppIcon(modelData.latestNotification?.appIcon || "", modelData.latestNotification?.desktopEntry || "")

                        visible: index < chipHost.fitCount
                        width: chipHost.chipWidth
                        Accessible.name: modelData.appName
                        onContentWidthChanged: Qt.callLater(chipHost.measure)

                        Item {
                            width: Theme.iconSizeSmall
                            height: width
                            anchors.verticalCenter: parent.verticalCenter

                            Image {
                                id: appImage
                                anchors.fill: parent
                                asynchronous: true
                                smooth: true
                                fillMode: Image.PreserveAspectFit
                                sourceSize: Qt.size(width * 2, height * 2)
                                source: NotificationService.notificationImageSource("", chip.appIcon)
                                visible: status === Image.Ready
                            }

                            AppIconRenderer {
                                anchors.fill: parent
                                visible: !appImage.visible
                                iconValue: NotificationService.notificationFallbackIcon("", chip.appIcon)
                                iconSize: Theme.iconSizeSmall
                                iconColor: Theme.onSurfaceVariant
                                colorOverride: "transparent"
                                fallbackText: (chip.modelData.appName || "?").charAt(0).toUpperCase()
                                fallbackRadius: Theme.fullRadius(width, height)
                                fallbackBackgroundColor: Theme.secondaryContainer
                                fallbackTextColor: Theme.onSecondaryContainer
                            }
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: chip.modelData.appName
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Theme.fontWeightMedium
                            color: Theme.onSurface
                        }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: chip.modelData.count > 1
                            width: Math.max(height, countText.implicitWidth + Theme.spacingXS * 2)
                            height: Theme.iconSizeSmall
                            radius: Theme.fullRadius(width, height)
                            color: Theme.primary

                            StyledText {
                                id: countText
                                anchors.centerIn: parent
                                text: chip.modelData.count
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Theme.fontWeightMedium
                                color: Theme.onPrimary
                            }
                        }
                    }
                }

                Chip {
                    visible: chipHost.hiddenCount > 0 && chipHost.moreFits

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("+ %1 more", "lock screen notification list overflow, %1 is a count of hidden apps").arg(chipHost.hiddenCount)
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Theme.fontWeightMedium
                        color: Theme.onSurfaceVariant
                    }
                }
            }
        }
    }

    Component {
        id: countOnlyComponent

        Item {
            implicitWidth: countPill.width
            implicitHeight: countPill.height

            Rectangle {
                id: countPill
                anchors.centerIn: parent
                width: countRow.implicitWidth + Theme.spacingL * 2
                height: Theme.buttonHeightS
                radius: Theme.fullRadius(width, height)
                color: Theme.notificationFloatingSurface
                border.width: Theme.layerOutlineWidth
                border.color: Theme.outlineVariant
                scale: Math.min(1, parent.width / width, parent.height / height)
                Accessible.name: countLabel.text

                Row {
                    id: countRow
                    anchors.centerIn: parent
                    spacing: Theme.spacingS

                    DIcon {
                        name: "notifications"
                        size: Theme.iconSizeSmall + Theme.spacingXXS
                        color: Theme.onSurfaceVariant
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        id: countLabel
                        text: root.editPlaceholder ? I18n.tr("Notifications") : root.totalCount === 1 ? I18n.tr("1 notification") : I18n.tr("%1 notifications").arg(root.totalCount)
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Theme.fontWeightMedium
                        color: Theme.onSurface
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }
    }

    Component {
        id: notificationListComponent

        Item {
            implicitWidth: LockMetrics.notificationCardWidth
            implicitHeight: Math.min(notificationColumn.implicitHeight, LockMetrics.notificationMaxHeight)

            ClippingRectangle {
                anchors.centerIn: parent
                width: parent.width
                height: Math.min(notificationColumn.implicitHeight, parent.height)
                radius: Theme.groupedListOuterRadius
                color: "transparent"

                DFlickable {
                    anchors.fill: parent
                    contentHeight: notificationColumn.implicitHeight
                    clip: true

                    Column {
                        id: notificationColumn
                        width: parent.width
                        spacing: Theme.groupedListGap

                        Repeater {
                            id: notificationRepeater
                            model: root.visibleGroups

                            Notifications.NotificationCard {
                                required property var modelData
                                required property int index
                                width: notificationColumn.width
                                notificationData: modelData.latestNotification
                                groupCount: modelData.count
                                interactive: false
                                headerOnly: false
                                showActions: false
                                showDismiss: false
                                showClose: false
                                showTime: !headerOnly
                                animateHeight: false
                                firstInGroup: index === 0
                                lastInGroup: index === notificationRepeater.count - 1
                            }
                        }

                        StyledText {
                            width: parent.width
                            visible: root.appNameGroups.length > LockMetrics.notificationLimit
                            text: I18n.tr("+ %1 more", "lock screen notification list overflow, %1 is a count of hidden apps").arg(root.appNameGroups.length - LockMetrics.notificationLimit)
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.lockScreenContentColor
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }
            }
        }
    }
}
