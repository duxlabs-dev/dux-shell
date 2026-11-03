pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Widgets
import "../../../DCommon/Common/FocusNavigation.js" as FocusNavigation
import "../../../DCommon/Common/WheelInput.js" as WheelInput

Item {
    id: root

    property bool vertical: false
    property bool canAdd: true
    property bool hasWidgets: true
    property bool canClear: true
    property bool hasOptions: false
    property bool hasCustomActions: false
    property string pendingAction: ""
    readonly property var actionButtons: [addButton, optionsButton, customButton, resetButton, clearButton, finishButton]
    readonly property var focusTargets: actionButtons.filter(item => item.visible && item.enabled)
    readonly property real focusPadding: Theme.focusRingOffset + Theme.focusRingWidth

    signal addRequested(var anchor)
    signal actionsRequested(var anchor)
    signal optionsRequested
    signal resetRequested
    signal clearRequested
    signal finished

    implicitWidth: actions.implicitWidth
    implicitHeight: actions.implicitHeight
    readonly property Item focusedItem: Window.activeFocusItem
    onFocusedItemChanged: revealFocusedItem()
    onWidthChanged: revealFocusedItem()
    onHeightChanged: revealFocusedItem()

    function revealFocusedItem() {
        const target = focusedItem;
        if (!target || !focusTargets.includes(target))
            return;
        const point = target.mapToItem(viewport.contentItem, 0, 0);
        if (vertical) {
            viewport.contentY = Math.max(0, Math.min(point.y - focusPadding, Math.max(viewport.contentY, point.y + target.height + focusPadding - viewport.height)));
            return;
        }
        viewport.contentX = Math.max(0, Math.min(point.x - focusPadding, Math.max(viewport.contentX, point.x + target.width + focusPadding - viewport.width)));
    }

    function cancelConfirmation() {
        pendingAction = "";
    }

    function clearFocus() {
        for (const target of actionButtons)
            target.focus = false;
    }

    onVisibleChanged: cancelConfirmation()

    component EditButton: DButton {
        property string label: ""
        text: root.vertical ? "" : label
        tooltipText: root.vertical ? label : null
        buttonHeight: Theme.buttonHeightS
    }

    component ConfirmButton: EditButton {
        id: confirmation
        required property string actionId
        property color armedColor: Theme.primary
        property color armedTextColor: Theme.onPrimary
        readonly property bool armed: root.pendingAction === actionId
        readonly property string confirmLabel: I18n.tr("Confirm")
        signal confirmed
        text: root.vertical ? "" : armed ? confirmLabel : label
        reserveText: root.vertical ? "" : armed ? label : confirmLabel
        tooltipText: armed ? confirmLabel : root.vertical ? label : null
        backgroundColor: armed ? armedColor : Theme.buttonBg
        textColor: armed ? armedTextColor : Theme.buttonText
        onClicked: {
            if (!armed) {
                root.pendingAction = actionId;
                return;
            }
            root.pendingAction = "";
            confirmed();
        }
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape && pendingAction !== "") {
            cancelConfirmation();
            event.accepted = true;
            return;
        }
        if (event.key !== Qt.Key_Tab && event.key !== Qt.Key_Backtab)
            return;
        const backwards = event.key === Qt.Key_Backtab || !!(event.modifiers & Qt.ShiftModifier);
        if (!FocusNavigation.moveFocus(focusTargets, backwards))
            focusTargets[backwards ? focusTargets.length - 1 : 0]?.forceActiveFocus(backwards ? Qt.BacktabFocusReason : Qt.TabFocusReason);
        event.accepted = true;
    }

    DFlickable {
        id: viewport
        anchors.fill: parent
        anchors.margins: -root.focusPadding
        showScrollBar: false
        contentWidth: root.vertical ? width : Math.max(width, actions.implicitWidth + root.focusPadding * 2)
        contentHeight: root.vertical ? actions.implicitHeight + root.focusPadding * 2 : height
        flickableDirection: root.vertical ? Flickable.VerticalFlick : Flickable.HorizontalFlick
        wheelEnabled: root.vertical
        clip: true

        WheelHandler {
            enabled: !root.vertical && viewport.contentWidth > viewport.width
            onWheel: event => {
                const delta = WheelInput.anyAxisDelta(event);
                viewport.contentX = Math.max(0, Math.min(viewport.contentWidth - viewport.width, viewport.contentX - delta));
                event.accepted = true;
            }
        }

        Grid {
            id: actions
            x: Math.max(root.focusPadding, (viewport.width - implicitWidth) / 2)
            y: root.vertical ? root.focusPadding : Math.max(root.focusPadding, (viewport.height - implicitHeight) / 2)
            columns: root.vertical ? 1 : root.actionButtons.length
            horizontalItemAlignment: Grid.AlignHCenter
            verticalItemAlignment: Grid.AlignVCenter
            LayoutMirroring.enabled: false
            spacing: Theme.spacingS
            layoutDirection: I18n.isRtl && !root.vertical ? Qt.RightToLeft : Qt.LeftToRight

            EditButton {
                id: addButton
                label: I18n.tr("Add widget")
                iconName: "add"
                backgroundColor: Theme.secondaryContainer
                textColor: Theme.onSecondaryContainer
                visible: root.hasWidgets
                enabled: root.canAdd
                onClicked: root.addRequested(addButton)
            }

            EditButton {
                id: optionsButton
                label: I18n.tr("Options")
                iconName: "tune"
                visible: root.hasOptions
                onClicked: root.optionsRequested()
            }

            EditButton {
                id: customButton
                label: I18n.tr("Actions", "Dashboard page actions supplied by a plugin or built-in page")
                iconName: "more_horiz"
                visible: root.hasCustomActions
                onClicked: root.actionsRequested(customButton)
            }

            ConfirmButton {
                id: resetButton
                actionId: "reset"
                label: I18n.tr("Reset to default")
                iconName: "settings_backup_restore"
                onConfirmed: root.resetRequested()
            }

            ConfirmButton {
                id: clearButton
                actionId: "clear"
                label: I18n.tr("Clear All")
                iconName: "clear_all"
                armedColor: Theme.error
                armedTextColor: Theme.onError
                visible: root.hasWidgets && root.canClear
                onConfirmed: root.clearRequested()
            }

            EditButton {
                id: finishButton
                label: I18n.tr("Finish")
                iconName: "check"
                backgroundColor: Theme.primary
                textColor: Theme.onPrimary
                onClicked: root.finished()
            }
        }
    }
}
