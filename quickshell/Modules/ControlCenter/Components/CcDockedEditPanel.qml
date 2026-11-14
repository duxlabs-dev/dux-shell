pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Modules.ControlCenter
import qs.Modules.ControlCenter.Widgets
import qs.DCommon.Widgets
import qs.Widgets
import "../utils/catalog.js" as Catalog

Item {
    id: root

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    property var widgets: []
    property var grid: null
    property bool floating: false
    property bool fadeOut: false
    property bool canUndo: false
    property bool removeTarget: false
    property var transientSurfaceTracker: null
    property color surfaceColor: Theme.withAlpha(CcMetrics.dialogColor, 1)
    property real radius: Theme.cornerRadiusXL

    readonly property CcWidgetCategories categoryDefs: CcWidgetCategories {}
    readonly property var addable: widgets.filter(widget => widget.enabled !== false)
    readonly property var chips: [
        {
            "label": I18n.tr("All"),
            "value": "all"
        }
    ].concat(Catalog.shownCategories(categoryDefs.defs, addable).map(category => ({
                "label": category.title,
                "value": category.id
            })))
    property string category: "all"
    readonly property int chipIndex: Math.max(0, chips.findIndex(chip => chip.value === category))
    readonly property string query: searchField.text.trim()
    readonly property var matches: Catalog.filterWidgets(addable, query, chips[chipIndex].value)
    property string dragWidgetId: ""
    property point dragPoint
    readonly property var dragEntry: dragWidgetId === "" ? null : (addable.find(widget => widget.id === dragWidgetId) ?? null)
    // A floating popover covers the grid, so it hides while a widget is dragged out of it.
    readonly property bool faded: floating && (fadeOut || dragWidgetId !== "")

    signal addRequested(string widgetId)
    signal undoRequested
    signal resetRequested
    signal clearRequested
    signal finishRequested
    signal cancelRequested
    signal closeRequested

    function containsScenePoint(scenePoint) {
        const point = mapFromItem(null, scenePoint.x, scenePoint.y);
        return point.x >= 0 && point.y >= 0 && point.x <= width && point.y <= height;
    }

    function overPanel(scenePoint) {
        return !faded && containsScenePoint(scenePoint);
    }

    function updateDrag(point) {
        dragPoint = point;
        if (overPanel(point)) {
            grid?.clearExternal();
            return;
        }
        grid?.hoverNew(dragWidgetId, point);
    }

    function endDrag(widgetId, canceled) {
        const dropped = !canceled && !overPanel(dragPoint) && (grid?.dropNew(widgetId) ?? false);
        if (!dropped)
            grid?.clearExternal();
        dragWidgetId = "";
    }

    function focusSearch() {
        searchField.forceActiveFocus();
    }

    implicitWidth: CcMetrics.dockedPanelWidth
    Accessible.name: floating ? I18n.tr("Add widget") : I18n.tr("Edit mode")

    Component.onCompleted: {
        if (floating)
            searchField.forceActiveFocus();
    }
    Component.onDestruction: grid?.clearExternal()

    onVisibleChanged: {
        if (visible)
            return;
        searchField.text = "";
        category = "all";
        if (dragWidgetId === "")
            return;
        grid?.clearExternal();
        dragWidgetId = "";
    }

    Item {
        anchors.fill: parent
        opacity: root.faded ? 0 : 1
        // Kept enabled while faded: disabling it would cancel the bubble's own drag.

        Behavior on opacity {
            enabled: CcMetrics.animationsEnabled
            NumberAnimation {
                duration: Theme.shortDuration
                easing.type: Theme.standardEasing
            }
        }

        ElevationShadow {
            anchors.fill: parent
            z: -1
            level: Theme.elevationLevel2
            targetRadius: root.radius
            targetColor: "transparent"
            shadowEnabled: root.floating && Theme.elevationEnabled
            visible: shadowEnabled
        }

        Rectangle {
            anchors.fill: parent
            radius: root.radius
            color: root.surfaceColor
            border.width: root.removeTarget ? Theme.outlineWidthFocused : 0
            border.color: Theme.error
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: CcMetrics.sheetPadding
            spacing: Theme.spacingL

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingS

                Column {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop

                    StyledText {
                        width: parent.width
                        text: root.floating ? I18n.tr("Add widget") : I18n.tr("Edit mode")
                        font.pixelSize: Theme.fontSizeLarge
                        font.weight: Theme.fontWeightMedium
                        color: Theme.surfaceText
                        elide: Text.ElideRight
                    }

                    StyledText {
                        width: parent.width
                        text: root.floating ? I18n.tr("Click to add, or drag into place") : I18n.tr("Drag widgets in, or click one to add it")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        elide: Text.ElideRight
                    }

                    // Floating, the edit strip says it.
                    StyledText {
                        width: parent.width
                        visible: !root.floating
                        text: I18n.tr("Right-click a widget for options")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        elide: Text.ElideRight
                    }
                }

                DActionButton {
                    Layout.alignment: Qt.AlignTop
                    visible: root.floating
                    buttonSize: Theme.iconButtonSize
                    iconName: "close"
                    iconSize: CcMetrics.iconBoxIconSize
                    iconColor: Theme.onSurface
                    tooltipText: I18n.tr("Close")
                    onClicked: root.closeRequested()
                }
            }

            DSearchField {
                id: searchField

                Layout.fillWidth: true
                placeholderText: I18n.tr("Search widgets...")
                onAccepted: {
                    if (root.matches.length > 0)
                        root.addRequested(root.matches[0].id);
                }
            }

            DFilterChips {
                Layout.fillWidth: true
                model: root.chips
                currentIndex: root.chipIndex
                onSelectionChanged: index => root.category = root.chips[index].value
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                DFlickable {
                    id: flickable

                    anchors.fill: parent
                    visible: root.matches.length > 0
                    contentWidth: width
                    contentHeight: bubbles.height
                    clip: contentHeight > height
                    interactive: contentHeight > height

                    CcWidgetBubbleGrid {
                        id: bubbles

                        width: flickable.width
                        entries: root.matches
                        bubbleSize: CcMetrics.dockedBubbleSize
                        columns: Math.max(1, Math.min(CcMetrics.dockedPanelColumns, Math.floor((width + columnSpacing) / (bubbleSize + columnSpacing))))
                        columnSpacing: CcMetrics.gridGap
                        rowSpacing: Theme.spacingM
                        draggable: true
                        fallbackFocus: searchField
                        onChosen: widgetId => root.addRequested(widgetId)
                        onItemFocused: item => flickable.revealRange(item.y, item.y + item.height)
                        onDragStarted: (widgetId, scenePoint) => {
                            root.dragWidgetId = widgetId;
                            root.updateDrag(scenePoint);
                        }
                        onDragMoved: (widgetId, scenePoint) => root.updateDrag(scenePoint)
                        onDragEnded: (widgetId, canceled) => root.endDrag(widgetId, canceled)
                    }
                }

                CcEmptyState {
                    anchors.top: parent.top
                    visible: root.matches.length === 0
                    iconName: "search_off"
                    title: root.query.length > 0 ? I18n.tr("No widgets match your search") : I18n.tr("No widgets available")
                }
            }

            Item {
                Layout.fillWidth: true
                implicitHeight: Theme.iconButtonSize
                visible: !root.floating

                CcEditMenuButton {
                    anchors.left: parent.left
                    undoInMenu: false
                    transientSurfaceTracker: root.transientSurfaceTracker
                    onResetRequested: root.resetRequested()
                    onClearRequested: root.clearRequested()
                }

                Row {
                    anchors.right: parent.right
                    spacing: Theme.spacingS

                    DActionButton {
                        buttonSize: Theme.iconButtonSize
                        iconName: "undo"
                        iconSize: CcMetrics.iconBoxIconSize
                        iconColor: Theme.onSurface
                        backgroundColor: CcMetrics.tileInactiveColor
                        enabled: root.canUndo
                        tooltipText: I18n.tr("Undo")
                        onClicked: root.undoRequested()
                    }

                    DActionButton {
                        buttonSize: Theme.iconButtonSize
                        iconName: "close"
                        iconSize: CcMetrics.iconBoxIconSize
                        iconColor: Theme.onSurface
                        backgroundColor: CcMetrics.tileInactiveColor
                        tooltipText: I18n.tr("Discard")
                        onClicked: root.cancelRequested()
                    }

                    DButton {
                        buttonHeight: Theme.iconButtonSize
                        iconName: "check"
                        text: I18n.tr("Finish")
                        onClicked: root.finishRequested()
                    }
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: root.radius
            color: Theme.withAlpha(Theme.errorContainer, CcMetrics.removeOverlayOpacity)
            opacity: root.removeTarget ? 1 : 0
            visible: opacity > 0

            Behavior on opacity {
                enabled: CcMetrics.animationsEnabled
                NumberAnimation {
                    duration: Theme.shortDuration
                    easing.type: Theme.standardEasing
                }
            }

            DIcon {
                anchors.centerIn: parent
                name: "delete"
                size: Theme.iconSizeLarge
                filled: true
                color: Theme.error
                Accessible.role: Accessible.Graphic
                Accessible.name: I18n.tr("Remove")
            }
        }
    }

    Loader {
        readonly property point local: root.mapFromItem(null, root.dragPoint.x, root.dragPoint.y)

        active: root.dragEntry !== null
        z: CcMetrics.overlayZ
        x: local.x - width / 2
        y: local.y - height / 2
        sourceComponent: Rectangle {
            id: pill

            readonly property size ghostSize: root.grid?.externalGhostSize(root.dragWidgetId) ?? Qt.size(CcMetrics.columnWidth, CcMetrics.tileHeight)

            width: ghostSize.width
            height: ghostSize.height
            radius: CcMetrics.pillRadius(width, height)
            color: Theme.primaryContainer

            Row {
                anchors.centerIn: parent
                spacing: Theme.spacingS

                DIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: root.dragEntry?.icon ?? ""
                    size: Theme.iconSize
                    color: Theme.onPrimaryContainer
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, pill.width - Theme.spacingM * 2 - Theme.iconSize - Theme.spacingS)
                    text: root.dragEntry?.text ?? ""
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.onPrimaryContainer
                    elide: Text.ElideRight
                }
            }
        }
    }
}
