import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import "../Common/Format.js" as Format

PanelWindow {
    id: root

    WlrLayershell.namespace: "dms:toast"

    property var modelData
    property bool shouldBeVisible: false
    property bool _surfaceFrameReady: false
    readonly property bool presented: shouldBeVisible && _surfaceFrameReady
    property real frozenWidth: 0
    readonly property string copiedText: I18n.tr("Copied!", "toast feedback after copying text to clipboard")

    readonly property real dpr: modelData ? CompositorService.getScreenScale(modelData) : 1
    readonly property real shadowBuffer: 5
    // Toasts always drop from the top edge, so they clear whichever chrome owns it.
    readonly property real islandTopOffset: SettingsData.dankIslandEdgeOffset(modelData, "top")
    readonly property real toastY: islandTopOffset > 0 ? islandTopOffset + Theme.spacingS : Theme.barHeight - 4 + (SettingsData.getPrimaryBarConfig()?.spacing ?? 4) + 2

    readonly property bool serviceToastVisible: ToastService.toastVisible

    onServiceToastVisibleChanged: {
        if (serviceToastVisible) {
            shouldBeVisible = true;
            visible = true;
        } else {
            frozenWidth = toast.width;
            shouldBeVisible = false;
            closeTimer.restart();
        }
    }

    Timer {
        id: closeTimer
        interval: Theme.mediumDuration + 50
        onTriggered: {
            if (!shouldBeVisible) {
                visible = false;
            }
        }
    }

    screen: modelData
    visible: shouldBeVisible
    onVisibleChanged: {
        if (!visible)
            _surfaceFrameReady = false;
    }

    Connections {
        target: toast.Window.window
        enabled: root.visible && !root._surfaceFrameReady

        function onFrameSwapped() {
            root._surfaceFrameReady = true;
        }
    }
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    color: "transparent"

    readonly property real toastWidth: shouldBeVisible ? Theme.px(Math.min(900, messageText.implicitWidth + statusIcon.width + Theme.spacingM + ((ToastService.hasDetails || ToastService.isStickyCategory(ToastService.currentCategory)) ? (expandButton.width + closeButton.width + 4) : (ToastService.currentLevel === ToastService.levelError ? closeButton.width + Theme.spacingS : 0)) + Theme.spacingL * 2 + Theme.spacingM * 2), dpr) : frozenWidth
    readonly property real toastHeight: Theme.px(toastContent.height + Theme.spacingL * 2, dpr)

    anchors {
        top: true
        left: true
    }

    WlrLayershell.margins {
        left: Math.max(0, Theme.snap((modelData?.width ?? 1920) / 2 - toastWidth / 2 - shadowBuffer, dpr))
        top: Math.max(0, Theme.snap(toastY - shadowBuffer, dpr))
    }

    implicitWidth: Theme.px(toastWidth + (shadowBuffer * 2), dpr)
    implicitHeight: Theme.px(toastHeight + (shadowBuffer * 2), dpr)

    Rectangle {
        id: toast

        property bool expanded: false

        function linkify(text) {
            if (!text)
                return "";
            const escaped = Format.escapeHtml(text);
            const linked = escaped.replace(/(https?:\/\/[^\s<]+)/g, '<a href="$1">$1</a>');
            return linked.replace(/\n/g, "<br>");
        }

        Connections {
            target: ToastService
            function onResetToastState() {
                toast.expanded = false;
            }
        }

        x: shadowBuffer
        y: shadowBuffer
        width: root.toastWidth
        height: root.toastHeight
        readonly property color surfaceColor: {
            switch (ToastService.currentLevel) {
            case ToastService.levelError:
                return Theme.error;
            case ToastService.levelWarn:
                return Theme.warning;
            case ToastService.levelInfo:
                return Theme.readableSurface;
            default:
                return Theme.readableSurface;
            }
        }
        color: "transparent"
        radius: Theme.windowRadius
        opacity: presented ? 1 : 0

        Column {
            id: toastContent

            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: Theme.spacingL
            anchors.leftMargin: Theme.spacingL
            anchors.rightMargin: Theme.spacingL
            spacing: Theme.spacingS

            Item {
                width: parent.width
                height: Math.max(Theme.iconSize + 8, messageText.implicitHeight)

                DIcon {
                    id: statusIcon
                    name: {
                        switch (ToastService.currentLevel) {
                        case ToastService.levelError:
                            return "error";
                        case ToastService.levelWarn:
                            return "warning";
                        case ToastService.levelInfo:
                            return "info";
                        default:
                            return "info";
                        }
                    }
                    size: Theme.iconSize
                    color: {
                        switch (ToastService.currentLevel) {
                        case ToastService.levelError:
                        case ToastService.levelWarn:
                            return SessionData.isLightMode ? Theme.surfaceText : Theme.background;
                        default:
                            return Theme.surfaceText;
                        }
                    }
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    id: messageText
                    text: ToastService.currentMessage
                    font.pixelSize: Theme.fontSizeMedium
                    color: {
                        switch (ToastService.currentLevel) {
                        case ToastService.levelError:
                        case ToastService.levelWarn:
                            return SessionData.isLightMode ? Theme.surfaceText : Theme.background;
                        default:
                            return Theme.surfaceText;
                        }
                    }
                    anchors.left: statusIcon.right
                    anchors.leftMargin: Theme.spacingM
                    anchors.right: ToastService.hasDetails ? expandButton.left : parent.right
                    anchors.rightMargin: ToastService.hasDetails ? Theme.spacingS : 0
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                }

                DActionButton {
                    id: expandButton
                    iconName: toast.expanded ? "expand_less" : "expand_more"
                    Accessible.name: toast.expanded ? I18n.tr("Collapse", "verb, button that collapses an expanded item or section") : I18n.tr("Expand", "verb, button that expands a collapsed item or section")
                    iconSize: Theme.iconSize
                    iconColor: {
                        switch (ToastService.currentLevel) {
                        case ToastService.levelError:
                        case ToastService.levelWarn:
                            return SessionData.isLightMode ? Theme.surfaceText : Theme.background;
                        default:
                            return Theme.surfaceText;
                        }
                    }
                    buttonSize: Theme.iconSize + 8
                    anchors.right: closeButton.left
                    anchors.rightMargin: 2
                    anchors.verticalCenter: parent.verticalCenter
                    visible: ToastService.hasDetails

                    onClicked: {
                        toast.expanded = !toast.expanded;
                        if (toast.expanded) {
                            ToastService.stopTimer();
                        } else {
                            ToastService.restartTimer();
                        }
                    }
                }

                DActionButton {
                    id: closeButton
                    iconName: "close"
                    Accessible.name: I18n.tr("Close")
                    iconSize: Theme.iconSize
                    iconColor: {
                        switch (ToastService.currentLevel) {
                        case ToastService.levelError:
                        case ToastService.levelWarn:
                            return SessionData.isLightMode ? Theme.surfaceText : Theme.background;
                        default:
                            return Theme.surfaceText;
                        }
                    }
                    buttonSize: Theme.iconSize + 8
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: ToastService.hasDetails || ToastService.currentLevel === ToastService.levelError || ToastService.isStickyCategory(ToastService.currentCategory)

                    onClicked: {
                        ToastService.hideToast();
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: detailsColumn.height + Theme.spacingS * 2
                color: ToastService.currentDetails.length > 0 ? Qt.rgba(0, 0, 0, 0.2) : "transparent"
                radius: Theme.cornerRadiusS
                visible: toast.expanded && ToastService.hasDetails
                anchors.horizontalCenter: parent.horizontalCenter

                Column {
                    id: detailsColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Theme.spacingS
                    spacing: Theme.spacingS

                    Item {
                        width: parent.width - Theme.spacingS * 2
                        height: detailsText.implicitHeight
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: ToastService.currentDetails.length > 0

                        StyledText {
                            id: detailsText
                            readonly property bool hasLink: /https?:\/\//.test(ToastService.currentDetails)
                            text: hasLink ? toast.linkify(ToastService.currentDetails) : ToastService.currentDetails
                            textFormat: hasLink ? Text.StyledText : Text.PlainText
                            linkColor: {
                                switch (ToastService.currentLevel) {
                                case ToastService.levelError:
                                case ToastService.levelWarn:
                                    return SessionData.isLightMode ? Theme.surfaceText : Theme.background;
                                default:
                                    return Theme.primary;
                                }
                            }
                            font.pixelSize: Theme.fontSizeSmall
                            color: {
                                switch (ToastService.currentLevel) {
                                case ToastService.levelError:
                                case ToastService.levelWarn:
                                    return SessionData.isLightMode ? Theme.surfaceText : Theme.background;
                                default:
                                    return Theme.surfaceText;
                                }
                            }
                            anchors.left: parent.left
                            anchors.right: copyDetailsButton.left
                            anchors.rightMargin: Theme.spacingS
                            wrapMode: Text.Wrap
                            onLinkActivated: url => Qt.openUrlExternally(url)

                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.NoButton
                                cursorShape: detailsText.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor
                            }
                        }

                        DActionButton {
                            id: copyDetailsButton
                            iconName: "content_copy"
                            Accessible.name: I18n.tr("Copy")
                            iconSize: Theme.iconSizeSmall
                            iconColor: {
                                switch (ToastService.currentLevel) {
                                case ToastService.levelError:
                                case ToastService.levelWarn:
                                    return SessionData.isLightMode ? Theme.surfaceText : Theme.background;
                                default:
                                    return Theme.surfaceText;
                                }
                            }
                            buttonSize: Theme.iconSizeSmall + 8
                            anchors.right: parent.right
                            anchors.top: parent.top

                            property bool showTooltip: false

                            onClicked: {
                                Quickshell.execDetached(["dms", "cl", "copy", ToastService.currentDetails]);
                                showTooltip = true;
                                detailsTooltipTimer.start();
                            }

                            Timer {
                                id: detailsTooltipTimer
                                interval: 1500
                                onTriggered: copyDetailsButton.showTooltip = false
                            }

                            Rectangle {
                                visible: copyDetailsButton.showTooltip
                                width: detailsTooltipLabel.implicitWidth + Theme.spacingM * 2
                                height: detailsTooltipLabel.implicitHeight + Theme.spacingS * 2
                                color: Theme.tooltipSurface
                                radius: Theme.cornerRadiusXS
                                y: -height - Theme.spacingS
                                x: -width / 2 + copyDetailsButton.width / 2

                                StyledText {
                                    id: detailsTooltipLabel
                                    anchors.centerIn: parent
                                    text: root.copiedText
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.tooltipText
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width - Theme.spacingS * 2
                        height: commandText.height + Theme.spacingS
                        anchors.horizontalCenter: parent.horizontalCenter
                        color: Qt.rgba(0, 0, 0, 0.3)
                        radius: Theme.cornerRadiusS
                        visible: ToastService.currentCommand.length > 0

                        StyledText {
                            id: commandText
                            text: ToastService.currentCommand
                            font.pixelSize: Theme.fontSizeSmall
                            color: {
                                switch (ToastService.currentLevel) {
                                case ToastService.levelError:
                                case ToastService.levelWarn:
                                    return SessionData.isLightMode ? Theme.surfaceText : Theme.background;
                                default:
                                    return Theme.surfaceText;
                                }
                            }
                            isMonospace: true
                            anchors.left: parent.left
                            anchors.right: copyButton.visible ? copyButton.left : parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: Theme.spacingS / 2
                            anchors.rightMargin: Theme.spacingS / 2
                            wrapMode: Text.Wrap
                        }

                        DActionButton {
                            id: copyButton
                            iconName: "content_copy"
                            Accessible.name: I18n.tr("Copy Full Command")
                            iconSize: Theme.iconSizeSmall
                            iconColor: {
                                switch (ToastService.currentLevel) {
                                case ToastService.levelError:
                                case ToastService.levelWarn:
                                    return SessionData.isLightMode ? Theme.surfaceText : Theme.background;
                                default:
                                    return Theme.surfaceText;
                                }
                            }
                            buttonSize: Theme.iconSizeSmall + 8
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.rightMargin: Theme.spacingS / 2
                            visible: ToastService.currentCommand.length > 0

                            property bool showTooltip: false

                            onClicked: {
                                Quickshell.execDetached(["dms", "cl", "copy", ToastService.currentCommand]);
                                showTooltip = true;
                                tooltipTimer.start();
                            }

                            Timer {
                                id: tooltipTimer
                                interval: 1500
                                onTriggered: copyButton.showTooltip = false
                            }

                            Rectangle {
                                visible: copyButton.showTooltip
                                width: tooltipLabel.implicitWidth + Theme.spacingM * 2
                                height: tooltipLabel.implicitHeight + Theme.spacingS * 2
                                color: Theme.tooltipSurface
                                radius: Theme.cornerRadiusXS
                                y: -height - Theme.spacingS
                                x: -width / 2 + copyButton.width / 2

                                StyledText {
                                    id: tooltipLabel
                                    anchors.centerIn: parent
                                    text: root.copiedText
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.tooltipText
                                }
                            }
                        }
                    }
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            visible: !ToastService.hasDetails && !ToastService.isStickyCategory(ToastService.currentCategory)
            onClicked: ToastService.hideToast()
        }

        ElevationShadow {
            anchors.fill: parent
            z: -1
            level: Theme.elevationLevel3
            fallbackOffset: 6
            targetRadius: toast.radius
            targetColor: toast.surfaceColor
            shadowOpacity: Theme.elevationLevel3 && Theme.elevationLevel3.alpha !== undefined ? Theme.elevationLevel3.alpha : 0.3
            shadowEnabled: Theme.elevationEnabled
        }

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.mediumDuration
                easing.type: Theme.emphasizedEasing
            }
        }

        Behavior on height {
            enabled: false
        }

        Behavior on width {
            enabled: false
        }
    }

    mask: Region {
        item: toast
    }

    WindowBlur {
        targetWindow: root
        blurEnabled: root.presented
        surfaceColor: toast.surfaceColor
        blurX: toast.x
        blurY: toast.y
        blurWidth: root.presented ? toast.width : 0
        blurHeight: root.presented ? toast.height : 0
        blurRadius: toast.radius
    }
}
