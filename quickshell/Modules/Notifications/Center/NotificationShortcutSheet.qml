pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Notifications
import "../NotificationShortcuts.js" as Shortcuts

FocusScope {
    id: root

    property real bottomInset: 0
    property bool alignEnd: false
    property bool editing: false
    property var choices: []
    readonly property var tileActions: editing ? choices.concat(["remove"]) : choices
    property NotificationShortcutSlot slot: null
    property bool keyboardOpened: false
    property bool opened: false
    property real progress: opened ? 1 : 0
    readonly property bool animationsEnabled: !SettingsData.reduceMotion && Theme.currentAnimationSpeed !== SettingsData.AnimationSpeed.None

    signal chosen(string action)

    function open(slot, choices, editing, alignEnd, keyboard) {
        root.choices = choices;
        root.editing = editing;
        root.alignEnd = alignEnd;
        root.slot = slot;
        root.keyboardOpened = keyboard;
        root.opened = true;
        focusTimer.restart();
    }

    function cycleFocus(backwards) {
        const targets = [];
        for (let i = 0; i < tiles.count; i++)
            targets.push(tiles.itemAt(i).button);
        if (targets.length === 0)
            return;
        const index = targets.indexOf(Window.activeFocusItem);
        const next = index < 0 ? (backwards ? targets.length - 1 : 0) : (index + (backwards ? -1 : 1) + targets.length) % targets.length;
        focusTile(targets[next], Qt.TabFocusReason);
    }

    function focusTile(button, reason) {
        if (!button)
            return;
        button.forceActiveFocus(reason);
        const point = button.mapToItem(scroll.contentItem, 0, 0);
        scroll.revealRange(point.y - Theme.spacingL, point.y + button.parent.height + Theme.spacingL);
    }

    function handleKeyEvent(event) {
        if (!opened)
            return false;
        switch (event.key) {
        case Qt.Key_Escape:
            close();
            break;
        case Qt.Key_Tab:
        case Qt.Key_Backtab:
            cycleFocus(event.key === Qt.Key_Backtab || !!(event.modifiers & Qt.ShiftModifier));
            break;
        }
        return true;
    }

    function close() {
        if (!opened)
            return;
        const restoreFocus = activeFocus;
        opened = false;
        if (restoreFocus)
            slot?.forceActiveFocus(keyboardOpened ? Qt.TabFocusReason : Qt.OtherFocusReason);
    }

    function label(action) {
        switch (action) {
        case "dnd":
            return I18n.tr("Do not disturb");
        case "history":
            return I18n.tr("History", "notification center tab");
        case "hints":
            return I18n.tr("Keyboard shortcuts");
        case "settings":
            return I18n.tr("Settings");
        case "remove":
            return I18n.tr("Remove");
        }
        return "";
    }

    visible: progress > 0
    onVisibleChanged: {
        if (visible)
            return;
        choices = [];
        editing = false;
    }
    enabled: opened
    onActiveFocusChanged: {
        if (!activeFocus)
            close();
    }
    Keys.onShortcutOverride: event => event.accepted = opened
    Keys.onPressed: event => event.accepted = handleKeyEvent(event)
    Keys.onReleased: event => event.accepted = opened

    Behavior on progress {
        enabled: root.animationsEnabled
        NumberAnimation {
            duration: Theme.expressiveDurations.expressiveEffects
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.expressiveCurves.emphasizedDecel
        }
    }

    Timer {
        id: focusTimer
        interval: 0
        onTriggered: root.focusTile(tiles.itemAt(0)?.button, root.keyboardOpened ? Qt.TabFocusReason : Qt.OtherFocusReason)
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: root.close()
        onWheel: wheel => wheel.accepted = true
    }

    Rectangle {
        id: surface

        anchors.left: root.alignEnd ? undefined : parent.left
        anchors.right: root.alignEnd ? parent.right : undefined
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.bottomInset
        width: Math.min(parent.width, Math.max(title.implicitWidth, root.tileActions.length * (NotificationMetrics.shortcutTileWidth + Theme.spacingS) - Theme.spacingS) + Theme.spacingL * 2)
        height: Math.min(content.implicitHeight + Theme.spacingL * 2, Math.max(0, root.height - root.bottomInset - Theme.spacingS))
        radius: Theme.cornerRadiusXL
        color: Theme.foregroundColor(Theme.chipSurface, Theme.isFloatingWindow(root))
        border.width: Theme.layerOutlineWidth
        border.color: Theme.outlineMedium
        opacity: root.progress
        scale: Theme.popupEnterScale + (1 - Theme.popupEnterScale) * root.progress
        transformOrigin: root.alignEnd !== I18n.isRtl ? Item.BottomRight : Item.BottomLeft
        Accessible.role: Accessible.Dialog
        Accessible.name: title.text

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
        }

        DFlickable {
            id: scroll
            anchors.fill: parent
            contentWidth: width
            contentHeight: content.implicitHeight + Theme.spacingL * 2
            interactive: contentHeight > height
            clip: true

            Column {
                id: content
                x: Theme.spacingL
                y: Theme.spacingL
                width: scroll.width - Theme.spacingL * 2
                spacing: Theme.spacingM

                StyledText {
                    id: title
                    width: parent.width
                    text: root.editing ? I18n.tr("Edit shortcut") : I18n.tr("Add shortcut")
                    font.pixelSize: Theme.fontSizeLarge
                    font.weight: Theme.fontWeightMedium
                    color: Theme.onSurface
                    elide: Text.ElideRight
                }

                Flow {
                    width: parent.width
                    spacing: Theme.spacingS

                    Repeater {
                        id: tiles
                        model: root.tileActions

                        Column {
                            id: tile

                            required property string modelData
                            readonly property alias button: button

                            width: NotificationMetrics.shortcutTileWidth
                            spacing: Theme.spacingXS

                            DIconButton {
                                id: button
                                anchors.horizontalCenter: parent.horizontalCenter
                                size: "m"
                                width: Theme.buttonHeightM
                                variant: "tonal"
                                containerColor: Theme.foregroundColor(Theme.chipSurfaceNested, Theme.isFloatingWindow(root))
                                contentColor: Theme.onSurfaceVariant
                                iconName: Shortcuts.icon(tile.modelData)
                                Accessible.name: root.label(tile.modelData)
                                onClicked: root.chosen(tile.modelData)
                                Keys.onTabPressed: root.cycleFocus(false)
                                Keys.onBacktabPressed: root.cycleFocus(true)
                            }

                            StyledText {
                                width: parent.width
                                text: root.label(tile.modelData)
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.onSurfaceVariant
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }
    }
}
