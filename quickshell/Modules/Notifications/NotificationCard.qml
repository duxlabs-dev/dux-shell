import QtQuick
import Quickshell.Widgets
import Quickshell.Services.Notifications
import qs.Common
import qs.Services
import qs.DCommon.Widgets

Rectangle {
    id: root

    property color surfaceColor: Theme.foregroundColor(Theme.cardSurface, Theme.isFloatingWindow(root))
    property color chipColor: Theme.chipSurface
    property var notificationData: null
    property bool interactive: true
    property bool headerOnly: false
    property bool descriptionExpanded: false
    property bool privacyMode: false
    property bool showActions: true
    property bool showDismiss: true
    property bool showClose: false
    property bool revealControls: true
    property string dismissText: I18n.tr("Dismiss")
    property bool showTime: true
    property bool bodyInvokesAction: false
    property bool persistImage: false
    property bool keyboardSelected: false
    property bool keyboardHints: false
    property bool animateHeight: true
    property bool groupExpanded: false
    property int groupCount: 1
    property real outerRadius: Theme.groupedListOuterRadius
    property bool firstInGroup: true
    property bool lastInGroup: true
    property real topRoundness: 0
    property real bottomRoundness: 0
    property real contentOpacity: 1
    readonly property bool hasMoreText: bodyText.truncated || summaryText.truncated
    readonly property bool hasBody: (notificationData?.htmlBody || "").replace(/<[^>]*>/g, "").trim().length > 0
    readonly property string appIcon: NotificationService.notificationAppIcon(notificationData?.appIcon || "", notificationData?.desktopEntry || "")
    readonly property bool dmsIcon: appIcon === "dev.duxlabs.shell" || appIcon === "com.danklinux.dms"
    readonly property string contentImageSource: notificationData?.hasDisplayImage ? notificationData?.displayImage || "" : ""
    readonly property bool hasContentImage: contentImageSource.length > 0 && contentImage.status !== Image.Error
    readonly property bool contentVisible: !headerOnly && (!privacyMode || descriptionExpanded)
    readonly property bool canExpand: !headerOnly && (hasMoreText || hasContentImage || descriptionExpanded || (hasBody && privacyMode))
    readonly property real targetHeight: Math.max(NotificationMetrics.appIconSize, content.implicitHeight) + NotificationMetrics.cardPadding * 2
    readonly property bool isAnimating: heightAnimation.running

    signal closeRequested
    signal dismissRequested
    signal actionRequested(var action)
    signal expandRequested
    signal groupToggleRequested
    signal bodyClicked
    signal contextMenuRequested(real x, real y)

    function saveDisplayImage() {
        const data = root.notificationData;
        if (!root.persistImage || !data?.notification || !data.hasDisplayImage || data.persistedImagePath)
            return;
        const image = data.image || "";
        if (!image.startsWith("image://qsimage/") && !NotificationService.notificationIconFromImage(image).startsWith("/"))
            return;
        const path = NotificationService.getImageCachePath(data);
        contentImage.grabToImage(result => {
            if (root.notificationData !== data || data.image !== image || !result.saveToFile(path))
                return;
            data.persistedImagePath = path;
            const id = data.notification?.id?.toString() || "";
            if (id)
                NotificationService.updateHistoryImage(id, path);
        }, Qt.size(Math.max(1, contentImage.implicitWidth), Math.max(1, contentImage.implicitHeight)));
    }

    implicitHeight: targetHeight
    height: targetHeight
    radius: Theme.groupedListInnerRadius
    topLeftRadius: radius + (outerRadius - radius) * (firstInGroup ? 1 : topRoundness)
    topRightRadius: topLeftRadius
    bottomLeftRadius: radius + (outerRadius - radius) * (lastInGroup ? 1 : bottomRoundness)
    bottomRightRadius: bottomLeftRadius
    color: keyboardSelected ? Theme.selectedContainer : surfaceColor
    border.width: Theme.layerOutlineWidth
    border.color: Theme.outlineMedium
    clip: true
    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true
    Accessible.role: Accessible.ListItem
    Accessible.name: headerOnly ? notificationData?.appName || "" : [notificationData?.appName, notificationData?.summary].filter(Boolean).join(". ")
    Accessible.description: headerOnly ? "" : privacyMode && !descriptionExpanded ? I18n.tr("Message Content", "notification privacy mode placeholder") : (notificationData?.body || "")
    Accessible.onPressAction: {
        if (interactive)
            root.bodyClicked();
    }

    Behavior on height {
        enabled: root.animateHeight && NotificationMetrics.animationsEnabled
        NumberAnimation {
            id: heightAnimation
            duration: root.descriptionExpanded ? Theme.notificationInlineExpandDuration : Theme.notificationInlineCollapseDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: NotificationMetrics.expandCurve
        }
    }

    Behavior on color {
        enabled: NotificationMetrics.animationsEnabled
        ColorAnimation {
            duration: Theme.expressiveDurations.expressiveEffects
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        topLeftRadius: root.topLeftRadius
        topRightRadius: root.topRightRadius
        bottomLeftRadius: root.bottomLeftRadius
        bottomRightRadius: root.bottomRightRadius
        color: "transparent"
        border.width: Theme.focusRingWidth
        border.color: Theme.focusRingColor
        visible: root.keyboardSelected
        z: 1
    }

    Rectangle {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.outlineWidthFocused
        height: parent.height - NotificationMetrics.cardPadding * 2
        radius: Theme.fullRadius(width, height)
        color: Theme.primary
        opacity: root.contentOpacity
        visible: root.notificationData?.urgency === NotificationUrgency.Critical
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.interactive
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                root.contextMenuRequested(mouse.x, mouse.y);
                return;
            }
            root.bodyClicked();
        }
    }

    Item {
        id: iconBox
        width: NotificationMetrics.appIconSize
        height: width
        anchors.left: parent.left
        anchors.leftMargin: NotificationMetrics.cardPadding
        y: NotificationMetrics.cardPadding
        opacity: root.contentOpacity

        Image {
            id: appImage
            anchors.fill: parent
            asynchronous: true
            smooth: true
            fillMode: Image.PreserveAspectFit
            sourceSize: Qt.size(NotificationMetrics.appIconSize * 2, NotificationMetrics.appIconSize * 2)
            source: NotificationService.notificationImageSource("", root.appIcon)
            visible: status === Image.Ready
        }

        AppIconRenderer {
            anchors.fill: parent
            visible: !appImage.visible
            iconValue: root.dmsIcon ? "svg:" + Theme.shellDir + "/assets/danklogonormal.svg" : NotificationService.notificationFallbackIcon(root.headerOnly ? "" : root.notificationData?.image || "", root.appIcon)
            iconSize: NotificationMetrics.appIconSize
            iconColor: Theme.onSurfaceVariant
            colorOverride: root.dmsIcon ? Theme.primary : "transparent"
            fallbackText: (root.notificationData?.appName || "?").charAt(0).toUpperCase()
            fallbackRadius: Theme.fullRadius(width, height)
            fallbackBackgroundColor: Theme.secondaryContainer
            fallbackTextColor: Theme.onSecondaryContainer
        }
    }

    Column {
        id: content
        anchors.left: iconBox.right
        anchors.leftMargin: NotificationMetrics.iconSpacing
        anchors.right: parent.right
        anchors.rightMargin: NotificationMetrics.cardPadding
        y: NotificationMetrics.cardPadding
        spacing: NotificationMetrics.contentSpacing
        opacity: root.contentOpacity

        Item {
            id: messageBlock
            readonly property real thumbnailReserve: !root.descriptionExpanded && imagePreview.visible ? imagePreview.width + Theme.spacingM : 0
            readonly property real thumbnailTop: header.height + Theme.spacingS
            readonly property real textHeight: header.height + (root.headerOnly ? 0 : NotificationMetrics.contentSpacing + messageText.implicitHeight)
            width: parent.width
            height: root.descriptionExpanded ? textHeight + (imagePreview.visible ? NotificationMetrics.contentSpacing + imagePreview.height : 0) : Math.max(textHeight, imagePreview.visible ? thumbnailTop + imagePreview.height : 0)

            Item {
                id: header
                anchors.left: parent.left
                anchors.right: parent.right
                height: NotificationMetrics.controlSize

                StyledText {
                    anchors.left: parent.left
                    anchors.right: controls.left
                    anchors.rightMargin: Theme.spacingXS
                    anchors.verticalCenter: parent.verticalCenter
                    text: (root.notificationData?.appName || "") + (root.showTime && root.notificationData?.timeStr ? " · " + root.notificationData.timeStr : "")
                    horizontalAlignment: Text.AlignLeft
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.onSurfaceVariant
                    elide: Text.ElideRight
                }

                Row {
                    id: controls
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingXXS
                    opacity: root.revealControls ? 1 : 0
                    visible: opacity > 0

                    Behavior on opacity {
                        enabled: NotificationMetrics.animationsEnabled
                        NumberAnimation {
                            duration: Theme.shortDuration
                            easing.type: Theme.standardEasing
                        }
                    }

                    Rectangle {
                        visible: !root.interactive && root.groupCount > 1
                        width: notificationCount.implicitWidth + Theme.spacingS * 2
                        height: Theme.iconSize
                        radius: Theme.fullRadius(width, height)
                        color: root.chipColor

                        StyledText {
                            id: notificationCount
                            anchors.centerIn: parent
                            text: root.groupCount.toString()
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.onSurfaceVariant
                        }
                    }

                    DButton {
                        visible: root.interactive && root.groupCount > 1
                        text: root.groupCount.toString()
                        iconName: root.groupExpanded ? "expand_less" : "expand_more"
                        buttonHeight: NotificationMetrics.controlSize
                        horizontalPadding: Theme.spacingS
                        backgroundColor: root.chipColor
                        textColor: Theme.onSurfaceVariant
                        Accessible.name: root.groupExpanded ? I18n.tr("Collapse") : I18n.tr("Expand")
                        onClicked: root.groupToggleRequested()
                    }

                    DActionButton {
                        visible: root.interactive && root.canExpand && root.groupCount <= 1
                        iconName: root.descriptionExpanded ? "expand_less" : "expand_more"
                        backgroundColor: root.chipColor
                        width: NotificationMetrics.controlSize + Theme.spacingS
                        buttonSize: NotificationMetrics.controlSize
                        iconSize: Theme.iconSizeSmall
                        Accessible.name: root.descriptionExpanded ? I18n.tr("Collapse") : I18n.tr("Expand")
                        onClicked: root.expandRequested()
                    }

                    DActionButton {
                        visible: root.interactive && root.showClose
                        iconName: "close"
                        buttonSize: NotificationMetrics.controlSize
                        iconSize: Theme.iconSizeSmall
                        Accessible.name: I18n.tr("Dismiss")
                        onClicked: root.closeRequested()
                    }
                }
            }

            Column {
                id: messageText
                anchors.left: parent.left
                y: header.height + NotificationMetrics.contentSpacing
                width: Math.max(0, parent.width - messageBlock.thumbnailReserve)
                visible: !root.headerOnly
                spacing: NotificationMetrics.contentSpacing

                StyledText {
                    id: summaryText
                    width: parent.width
                    visible: !root.headerOnly && text.length > 0
                    text: root.notificationData?.summary || ""
                    horizontalAlignment: Text.AlignLeft
                    font.pixelSize: NotificationMetrics.summarySize
                    font.weight: Theme.fontWeightMedium
                    color: Theme.onSurface
                    elide: root.descriptionExpanded ? Text.ElideNone : Text.ElideRight
                    maximumLineCount: root.descriptionExpanded ? -1 : 1
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                }

                StyledText {
                    id: bodyText
                    width: parent.width
                    visible: !root.headerOnly && text.length > 0 && (!root.privacyMode || root.descriptionExpanded)
                    text: root.interactive ? root.notificationData?.htmlBody || "" : (root.notificationData?.body || "").replace(/<[^>]*>/g, '')
                    textFormat: root.interactive ? Text.StyledText : Text.PlainText
                    horizontalAlignment: Text.AlignLeft
                    font.pixelSize: NotificationMetrics.bodySize
                    color: Theme.onSurfaceVariant
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    maximumLineCount: root.descriptionExpanded ? -1 : NotificationMetrics.collapsedLines
                    elide: root.descriptionExpanded ? Text.ElideNone : Text.ElideRight
                    linkColor: Theme.primary
                    onLinkActivated: link => {
                        if (root.interactive)
                            Qt.openUrlExternally(link);
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: root.interactive
                        cursorShape: Qt.PointingHandCursor
                        onPressed: mouse => {
                            if (bodyText.hoveredLink)
                                mouse.accepted = false;
                        }
                        onClicked: mouse => {
                            if (bodyText.hoveredLink)
                                return;
                            if (root.bodyInvokesAction) {
                                root.bodyClicked();
                                return;
                            }
                            if (root.canExpand)
                                root.expandRequested();
                        }
                    }
                }

                StyledText {
                    width: parent.width
                    visible: !root.headerOnly && root.privacyMode && !root.descriptionExpanded && root.hasBody
                    text: I18n.tr("Message Content", "notification privacy mode placeholder")
                    horizontalAlignment: Text.AlignLeft
                    font.pixelSize: NotificationMetrics.bodySize
                    color: Theme.onSurfaceVariant
                }
            }

            ClippingRectangle {
                id: imagePreview
                readonly property bool alignRight: root.descriptionExpanded ? I18n.isRtl : !I18n.isRtl
                x: alignRight ? parent.width - width : 0
                y: root.descriptionExpanded ? messageBlock.textHeight + NotificationMetrics.contentSpacing : messageBlock.thumbnailTop
                width: root.descriptionExpanded ? Math.min(parent.width, NotificationMetrics.imageMaxHeight * contentImage.aspectRatio) : Math.min(NotificationMetrics.thumbnailSize, NotificationMetrics.thumbnailSize * contentImage.aspectRatio)
                height: width / contentImage.aspectRatio
                radius: Theme.cornerRadiusM
                color: "transparent"
                visible: root.contentVisible && contentImage.implicitWidth > 0 && contentImage.status !== Image.Error

                Image {
                    id: contentImage
                    readonly property real aspectRatio: implicitWidth > 0 && implicitHeight > 0 ? implicitWidth / implicitHeight : 1
                    readonly property real decodeSize: root.persistImage || root.descriptionExpanded ? NotificationMetrics.imageDecodeSize : NotificationMetrics.thumbnailSize * 2
                    anchors.fill: parent
                    source: root.contentVisible || root.persistImage ? root.contentImageSource : ""
                    sourceSize: Qt.size(decodeSize, decodeSize)
                    asynchronous: true
                    retainWhileLoading: true
                    cache: !root.persistImage
                    smooth: true
                    fillMode: Image.Stretch
                    onStatusChanged: {
                        if (status === Image.Ready)
                            root.saveDisplayImage();
                    }
                }
            }
        }

        Item {
            width: parent.width
            height: actions.implicitHeight
            visible: root.interactive && !root.headerOnly && (root.showActions || root.showDismiss)

            Flow {
                id: actions
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: -NotificationMetrics.actionPadding
                spacing: Theme.spacingXS

                Repeater {
                    model: root.showActions ? (root.notificationData?.actions || []) : []
                    DButton {
                        required property var modelData
                        required property int index
                        text: (modelData.text || I18n.tr("Open")) + (root.keyboardHints && index < 9 ? " (" + (index + 1) + ")" : "")
                        maximumWidth: actions.width
                        wrapText: true
                        buttonHeight: NotificationMetrics.actionHeight
                        horizontalPadding: NotificationMetrics.actionPadding
                        minimumWidth: 0
                        backgroundColor: "transparent"
                        textColor: Theme.primary
                        onClicked: root.actionRequested(modelData)
                    }
                }

                DButton {
                    visible: root.showDismiss
                    text: root.dismissText
                    maximumWidth: actions.width
                    wrapText: true
                    buttonHeight: NotificationMetrics.actionHeight
                    horizontalPadding: NotificationMetrics.actionPadding
                    minimumWidth: 0
                    backgroundColor: "transparent"
                    textColor: Theme.primary
                    onClicked: root.dismissRequested()
                }
            }
        }
    }
}
