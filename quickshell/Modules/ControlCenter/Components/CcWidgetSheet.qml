pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modules.ControlCenter
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import "../utils/widgets.js" as WidgetUtils

DBottomSheet {
    id: root

    property var widgets: []
    readonly property var addable: widgets.filter(widget => widget.enabled !== false)
    readonly property string query: searchField.text.trim()
    readonly property var matches: WidgetUtils.filterWidgets(addable, query)
    readonly property var categories: [
        {
            "id": "user",
            "title": I18n.tr("User"),
            "icon": "account_circle"
        },
        {
            "id": "network",
            "title": I18n.tr("Network"),
            "icon": "hub"
        },
        {
            "id": "audio",
            "title": I18n.tr("Audio"),
            "icon": "tune"
        },
        {
            "id": "display",
            "title": I18n.tr("Display"),
            "icon": "display_settings"
        },
        {
            "id": "system",
            "title": I18n.tr("System"),
            "icon": "dns"
        },
        {
            "id": "plugins",
            "title": I18n.tr("Plugins"),
            "icon": "extension"
        }
    ]
    readonly property var shownCategories: categories.filter(category => addable.some(widget => (widget.category ?? "plugins") === category.id))

    signal chosen(string widgetId)

    function toggleCategory(id) {
        const collapsed = CacheData.controlCenterCollapsedCategories;
        CacheData.set("controlCenterCollapsedCategories", collapsed.includes(id) ? collapsed.filter(entry => entry !== id) : collapsed.concat([id]));
    }

    Accessible.name: I18n.tr("Widgets")
    initialFocusItem: searchField
    sheetHeight: height * CcMetrics.widgetSheetHeightRatio
    contentSpacing: Theme.spacingM

    onOpenedChanged: {
        if (opened)
            searchField.text = "";
    }

    component PreviewGrid: Grid {
        id: grid

        property var entries: []

        signal chosen(string widgetId)

        columns: Math.max(1, Math.floor((width + columnSpacing) / (CcMetrics.previewSize + columnSpacing)))
        columnSpacing: Theme.spacingM
        rowSpacing: Theme.spacingL

        Repeater {
            model: grid.entries

            StyledButton {
                id: item

                required property var modelData

                width: (grid.width - grid.columnSpacing * (grid.columns - 1)) / grid.columns
                height: preview.height + Theme.spacingS + label.implicitHeight
                Accessible.name: modelData.text
                Accessible.description: modelData.description ?? ""
                onClicked: grid.chosen(modelData.id)

                Rectangle {
                    id: preview

                    anchors.horizontalCenter: parent.horizontalCenter
                    width: CcMetrics.previewSize
                    height: width
                    radius: item.modelData.id === "user" ? Theme.fullRadius(width, height) : Theme.cornerRadiusLIncreased
                    // Solid: translucent, it vanishes against the card in light mode.
                    color: Theme.chipSurfaceNested

                    DIcon {
                        anchors.centerIn: parent
                        name: item.modelData.icon
                        size: Theme.iconSizeLarge
                        color: Theme.primary
                        visible: item.modelData.id !== "user" || PortalService.profileImageUrl === ""
                    }

                    Loader {
                        anchors.fill: parent
                        active: item.modelData.id === "user" && PortalService.profileImageUrl !== ""
                        sourceComponent: DCircularImage {
                            imageSource: PortalService.profileImageUrl
                            fallbackIcon: "material:person"
                        }
                    }

                    FocusRing {
                        visible: item.visualFocus
                    }

                    StateLayer {
                        control: item
                        stateColor: Theme.primary
                    }
                }

                StyledText {
                    id: label
                    anchors.top: preview.bottom
                    anchors.topMargin: Theme.spacingS
                    width: parent.width
                    text: item.modelData.text
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceText
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                }
            }
        }
    }

    component CategoryCard: Rectangle {
        id: card

        required property var category
        property var entries: []
        property bool expanded: true
        readonly property real collapsedHeight: Theme.avatarSize + Theme.spacingL * 2

        signal chosen(string widgetId)
        signal toggleRequested

        height: expanded ? itemsClip.y + items.implicitHeight + Theme.spacingL : collapsedHeight
        radius: Theme.cornerRadiusXL
        color: CcMetrics.rowColor

        Behavior on height {
            enabled: CcMetrics.animationsEnabled
            NumberAnimation {
                duration: Theme.expressiveDurations.expressiveDefaultSpatial
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveCurves.expressiveDefaultSpatial
            }
        }

        StyledButton {
            id: header

            width: parent.width
            height: card.collapsedHeight
            radius: card.radius
            bottomLeftRadius: card.expanded ? 0 : card.radius
            bottomRightRadius: card.expanded ? 0 : card.radius
            Accessible.name: card.category.title
            onClicked: card.toggleRequested()

            Rectangle {
                id: badge
                anchors.left: parent.left
                anchors.leftMargin: Theme.spacingL
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.avatarSize
                height: width
                radius: Theme.fullRadius(width, height)
                color: Theme.chipSurfaceNested

                DIcon {
                    anchors.centerIn: parent
                    name: card.category.icon
                    size: Theme.iconSize
                    color: Theme.primary
                }
            }

            StyledText {
                anchors.left: badge.right
                anchors.leftMargin: Theme.spacingL
                anchors.right: chevron.left
                anchors.rightMargin: Theme.spacingM
                anchors.verticalCenter: parent.verticalCenter
                text: card.category.title
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Theme.fontWeightMedium
                color: Theme.surfaceText
                elide: Text.ElideRight
            }

            DIcon {
                id: chevron
                anchors.right: parent.right
                anchors.rightMargin: Theme.spacingL
                anchors.verticalCenter: parent.verticalCenter
                name: "expand_more"
                size: Theme.iconSize
                color: Theme.onSurfaceVariant
                rotation: card.expanded ? 180 : 0

                Behavior on rotation {
                    enabled: CcMetrics.animationsEnabled
                    NumberAnimation {
                        duration: Theme.expressiveDurations.expressiveFastSpatial
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.expressiveCurves.expressiveFastSpatial
                    }
                }
            }

            FocusRing {
                visible: header.visualFocus
            }

            StateLayer {
                control: header
            }
        }

        Item {
            id: itemsClip
            x: Theme.spacingL
            y: header.height + Theme.spacingM
            width: parent.width - Theme.spacingL * 2
            height: Math.max(0, card.height - y)
            visible: card.height > card.collapsedHeight
            clip: true

            PreviewGrid {
                id: items
                width: parent.width
                entries: card.entries
                enabled: card.expanded
                onChosen: widgetId => card.chosen(widgetId)
            }
        }
    }

    DSearchField {
        id: searchField
        width: parent.width
        placeholderText: I18n.tr("Search widgets...")
        onAccepted: {
            if (root.matches.length > 0)
                root.chosen(root.matches[0].id);
        }
    }

    Repeater {
        model: root.query === "" ? root.shownCategories : []

        CategoryCard {
            required property var modelData

            width: parent?.width ?? 0
            category: modelData
            entries: root.addable.filter(widget => (widget.category ?? "plugins") === modelData.id)
            expanded: !CacheData.controlCenterCollapsedCategories.includes(modelData.id)
            onChosen: widgetId => root.chosen(widgetId)
            onToggleRequested: root.toggleCategory(modelData.id)
        }
    }

    PreviewGrid {
        width: parent.width
        visible: root.query !== ""
        entries: root.query !== "" ? root.matches : []
        onChosen: widgetId => root.chosen(widgetId)
    }

    StyledText {
        width: parent.width
        visible: root.matches.length === 0
        topPadding: Theme.spacingL
        bottomPadding: Theme.spacingL
        text: I18n.tr("No widgets available")
        font.pixelSize: Theme.fontSizeMedium
        color: Theme.surfaceVariantText
        horizontalAlignment: Text.AlignHCenter
    }
}
