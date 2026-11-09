pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets

Item {
    id: root

    required property var controller
    required property var activity
    property bool expanded: false
    property bool stable: false
    property bool trackSize: true
    readonly property bool vertical: controller.isVertical && !expanded
    property color foreground: Theme.surfaceText
    readonly property string iconAnimation: root.controller.liveIconAnimationMode === "activity" ? (root.activity?.iconAnimation ?? "") : root.controller.liveIconAnimationMode
    readonly property real animationIntensity: Math.max(0.1, Math.min(1, root.controller.liveIconAnimationIntensity / 100))
    property string animatedActivityKey: ""
    readonly property bool iconOnly: !expanded && (vertical || (stable ? activity?.stableCompact : activity?.compact) === "icon")
    readonly property real measuredLength: customFace ? (customLoader.item?.implicitWidth || controller.mediaCompactMaxLength) : iconOnly ? controller.compactFaceThickness : controller.compactIconSize + Theme.spacingM * 2 + Theme.spacingS + Math.max(titleMetrics.width, controller.compactDense ? 0 : subtitleMetrics.width)
    readonly property real expandedWidth: customFace ? (customLoader.item?.implicitWidth || controller.mediaCompactMaxLength) : controller.mediaCompactMaxLength
    readonly property real expandedHeight: customFace ? (customLoader.item?.implicitHeight || controller.compactFaceThickness + Theme.spacingL * 2) : content.implicitHeight + Theme.spacingL * 2
    onExpandedWidthChanged: {
        if (trackSize && expanded)
            controller.liveExpandedWidth = expandedWidth;
    }
    onExpandedHeightChanged: {
        if (trackSize && expanded)
            controller.liveExpandedHeight = expandedHeight;
    }
    onMeasuredLengthChanged: {
        if (trackSize && !expanded)
            controller.liveContentLength = measuredLength;
    }
    Component.onCompleted: {
        syncActivityAnimation();
        if (trackSize && expanded) {
            controller.liveExpandedWidth = expandedWidth;
            controller.liveExpandedHeight = expandedHeight;
        }
        if (trackSize && !expanded)
            controller.liveContentLength = measuredLength;
    }
    StyledTextMetrics {
        id: titleMetrics
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Theme.fontWeightMedium
        text: root.activity?.title ?? ""
    }
    StyledTextMetrics {
        id: subtitleMetrics
        font.pixelSize: Theme.fontSizeSmall
        text: root.activity?.subtitle ?? ""
    }
    readonly property var renderer: IslandActivityService.renderers[activity?.source]
    readonly property Component customFace: (expanded ? renderer?.expanded : iconOnly ? null : renderer?.compact) ?? null
    readonly property Component customIcon: renderer?.icon ?? null
    readonly property bool live: visible && opacity > 0 && !!Window.window && Window.window.visible
    readonly property bool rendererMotionEnabled: live && !SettingsData.reduceMotion && Theme.currentAnimationSpeed !== SettingsData.AnimationSpeed.None && controller.liveIconAnimationMode !== "none"
    readonly property bool motionEnabled: rendererMotionEnabled && !customFace && !customIcon

    function focusFace() {
        if (!expanded || !visible)
            return false;
        let target = customLoader.item;
        for (let i = 0; !target && i < actionRepeater.count; i++) {
            const button = actionRepeater.itemAt(i);
            if (button?.enabled)
                target = button;
        }
        target = target ?? dismissButton;
        if (typeof target.focusFace === "function")
            return target.focusFace() === true;
        target.forceActiveFocus(Qt.TabFocusReason);
        return true;
    }

    function syncActivityAnimation() {
        const key = `${root.activity?.source ?? ""}:${root.activity?.id ?? ""}:${root.iconAnimation}`;
        if (!key || key === animatedActivityKey)
            return;
        animatedActivityKey = key;
        if (iconAnimation === "wiggle" && motionEnabled && !customIcon && !activity?.image)
            wiggleAnimation.restart();
    }

    onMotionEnabledChanged: {
        if (motionEnabled)
            return;
        wiggleAnimation.stop();
        iconGlyph.rotation = 0;
        iconGlyph.scale = 1;
    }
    onActivityChanged: syncActivityAnimation()
    onIconAnimationChanged: syncActivityAnimation()
    Loader {
        id: customLoader
        anchors.fill: parent
        active: !!root.customFace
        sourceComponent: root.customFace
        // Custom Components bind to these through the Loader that hosts them.
        readonly property var activity: root.activity
        readonly property var controller: root.controller
        readonly property bool expanded: root.expanded
        readonly property bool stable: root.stable
        readonly property color foreground: root.foreground
        readonly property bool live: root.live
        readonly property bool motionEnabled: root.rendererMotionEnabled
        readonly property int motionDuration: root.controller.liveIconAnimationDuration
        readonly property real motionIntensity: root.animationIntensity
        readonly property real contentInset: root.expanded ? Theme.spacingL : Theme.spacingM
        readonly property real contentSpacing: Theme.spacingM
        readonly property real actionHeight: Theme.buttonHeightS
        function close() { root.controller.requestCollapse(); }
    }

    IslandActivityLayout {
        id: content
        visible: !root.customFace
        anchors.centerIn: parent
        contentInset: root.expanded ? Theme.spacingL : Theme.spacingM
        width: root.iconOnly ? root.controller.compactIconSize : availableWidth

        Row {
            width: parent.width
            spacing: root.expanded ? Theme.spacingM : Theme.spacingS

            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: root.expanded ? Theme.iconSizeLarge : root.controller.compactIconSize
                height: width

                DCircularImage {
                    anchors.fill: parent
                    visible: !!imageSource
                    imageSource: root.activity?.image ?? ""
                    fallbackIcon: "material:" + (root.activity?.icon ?? "notifications")
                    fallbackText: ""
                }

                DIcon {
                    id: iconGlyph
                    anchors.centerIn: parent
                    visible: !root.activity?.image && !root.customIcon
                    name: root.activity?.icon ?? "notifications"
                    size: root.expanded ? Theme.iconSizeMedium : parent.width
                    color: root.foreground
                    filled: true
                }

                Loader {
                    anchors.fill: parent
                    active: !!root.customIcon && !root.customFace && !root.activity?.image
                    sourceComponent: root.customIcon
                    readonly property var activity: root.activity
                    readonly property var controller: root.controller
                    readonly property bool expanded: root.expanded
                    readonly property bool stable: root.stable
                    readonly property color foreground: root.foreground
                    readonly property real iconSize: root.expanded ? Theme.iconSize : root.controller.compactIconSize
                    readonly property bool live: root.live && !root.customFace && !root.activity?.image
                    readonly property bool motionEnabled: live && root.rendererMotionEnabled
                    readonly property int motionDuration: root.controller.liveIconAnimationDuration
                    readonly property real motionIntensity: root.animationIntensity
                }

                SequentialAnimation {
                    id: wiggleAnimation
                    running: false
                    loops: 1
                    NumberAnimation {
                        target: iconGlyph
                        property: "rotation"
                        from: 0
                        to: -3.5 * root.animationIntensity
                        duration: Math.max(90, root.controller.liveIconAnimationDuration * 0.22)
                        easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                        target: iconGlyph
                        property: "rotation"
                        to: 3.5 * root.animationIntensity
                        duration: Math.max(130, root.controller.liveIconAnimationDuration * 0.32)
                        easing.type: Easing.InOutSine
                    }
                    NumberAnimation {
                        target: iconGlyph
                        property: "rotation"
                        to: 0
                        duration: Math.max(110, root.controller.liveIconAnimationDuration * 0.26)
                        easing.type: Easing.OutCubic
                    }
                }

                NumberAnimation {
                    target: iconGlyph
                    property: "rotation"
                    from: 0
                    to: 360
                    duration: Math.max(1000, root.controller.liveIconAnimationDuration)
                    easing.type: Easing.Linear
                    loops: Animation.Infinite
                    running: root.motionEnabled && iconGlyph.visible && root.iconAnimation === "spin"
                    onRunningChanged: {
                        if (!running)
                            iconGlyph.rotation = 0;
                    }
                }

                SequentialAnimation {
                    loops: Animation.Infinite
                    running: root.motionEnabled && iconGlyph.visible && root.iconAnimation === "pulse"
                    onRunningChanged: {
                        if (!running)
                            iconGlyph.scale = 1;
                    }
                    NumberAnimation {
                        target: iconGlyph
                        property: "scale"
                        to: 1 + 0.05 * root.animationIntensity
                        duration: Math.max(650, root.controller.liveIconAnimationDuration)
                        easing.type: Easing.InOutSine
                    }
                    NumberAnimation {
                        target: iconGlyph
                        property: "scale"
                        to: 1
                        duration: Math.max(650, root.controller.liveIconAnimationDuration)
                        easing.type: Easing.InOutSine
                    }
                    PauseAnimation {
                        duration: 1100
                    }
                }
            }

            Column {
                width: Math.max(0, parent.width - (root.expanded ? Theme.iconSizeLarge : root.controller.compactIconSize) - parent.spacing - (root.expanded ? dismissButton.width + parent.spacing : 0))
                anchors.verticalCenter: parent.verticalCenter
                visible: !root.iconOnly
                spacing: root.expanded ? Theme.spacingXXS : 0

                StyledText {
                    width: parent.width
                    text: root.activity?.title ?? ""
                    textFormat: Text.PlainText
                    color: root.foreground
                    font.pixelSize: root.expanded ? Theme.fontSizeMedium : Theme.fontSizeSmall
                    font.weight: Theme.fontWeightMedium
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                }

                StyledText {
                    width: parent.width
                    visible: !!text && (root.expanded || !root.controller.compactDense)
                    text: root.activity?.subtitle ?? ""
                    textFormat: Text.PlainText
                    color: root.foreground
                    opacity: 0.75
                    font.pixelSize: Theme.fontSizeSmall
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                }
            }

            DActionButton {
                id: dismissButton
                visible: root.expanded
                anchors.verticalCenter: parent.verticalCenter
                iconName: "close"
                iconColor: root.foreground
                Accessible.name: I18n.tr("Close")
                onClicked: root.controller.requestCollapse()
            }
        }

        Column {
            width: parent.width
            visible: root.expanded && (!!root.activity?.value || !!root.activity?.status)
            spacing: Theme.spacingXS

            StyledText {
                width: parent.width
                visible: !!text
                text: root.activity?.value ?? ""
                textFormat: Text.PlainText
                color: root.foreground
                font.pixelSize: Theme.fontSizeXLarge
                font.weight: Theme.fontWeightMedium
                elide: Text.ElideRight
            }

            StyledText {
                width: parent.width
                visible: !!text
                text: root.activity?.status ?? ""
                textFormat: Text.PlainText
                color: root.foreground
                opacity: 0.75
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
        }

        StyledText {
            width: parent.width
            visible: root.expanded && !!text
            text: root.activity?.body ?? ""
            textFormat: Text.PlainText
            color: root.foreground
            font.pixelSize: Theme.fontSizeSmall
            opacity: 0.8
            wrapMode: Text.Wrap
            maximumLineCount: 4
            elide: Text.ElideRight
        }

        Rectangle {
            width: parent.width
            height: Theme.spacingXS
            radius: height / 2
            visible: root.expanded && (root.activity?.progress ?? -1) >= 0
            color: Theme.withAlpha(root.foreground, 0.2)

            Rectangle {
                width: parent.width * Math.max(0, root.activity?.progress ?? 0)
                height: parent.height
                radius: parent.radius
                color: root.foreground

                Behavior on width {
                    enabled: !SettingsData.reduceMotion && Theme.currentAnimationSpeed !== SettingsData.AnimationSpeed.None
                    NumberAnimation {
                        duration: Math.min(220, Math.max(120, root.controller.liveIconAnimationDuration * 0.24))
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }

        Flow {
            id: actionRow
            width: parent.width
            visible: root.expanded && (actionRepeater.count > 0 || !!root.activity?.dismissible)
            spacing: Theme.spacingS

            Repeater {
                id: actionRepeater
                model: root.activity?.actions ?? []

                DButton {
                    required property var modelData
                    maximumWidth: actionRow.width
                    buttonHeight: Theme.buttonHeightS
                    wrapText: true
                    enabled: modelData.enabled !== false && !modelData.pending
                    busy: root.live && !!modelData.pending && root.rendererMotionEnabled
                    backgroundColor: modelData.role === "primary" ? Theme.primary : modelData.role === "destructive" ? Theme.errorContainer : Theme.withAlpha(root.foreground, 0.12)
                    textColor: modelData.role === "primary" ? Theme.onPrimary : modelData.role === "destructive" ? Theme.onErrorContainer : root.foreground
                    Accessible.description: modelData.pending ? I18n.tr("Loading") : ""
                    text: modelData.label
                    onClicked: IslandActivityService.invoke(root.activity.source, root.activity.id, modelData.id)
                }
            }

            DButton {
                visible: !!root.activity?.dismissible
                maximumWidth: actionRow.width
                buttonHeight: Theme.buttonHeightS
                wrapText: true
                backgroundColor: Theme.withAlpha(root.foreground, 0.12)
                textColor: root.foreground
                text: I18n.tr("Dismiss")
                onClicked: {
                    IslandActivityService.remove(root.activity.source, root.activity.id);
                    root.controller.requestCollapse();
                }
            }
        }
    }
}
