import QtQuick
import qs.Common
import qs.Modules.Plugins
import qs.Services
import qs.DCommon.Widgets

BasePill {
    id: layout

    property bool layoutPopupVisible: false
    property var popoutTarget: null

    signal toggleLayoutPopup

    // mango shares dwl's tag/layout model; route to the right service.
    readonly property bool isMango: CompositorService.isMango

    visible: layout.isMango && MangoService.available

    property var outputState: parentScreen ? MangoService.getOutputState(parentScreen.name) : null
    property string currentLayoutSymbol: outputState?.layoutSymbol || ""
    property int currentLayoutIndex: outputState?.layout || 0

    readonly property var layoutIcons: ({
            "CT": "view_compact",
            "G": "grid_view",
            "K": "layers",
            "M": "fullscreen",
            "RT": "view_sidebar",
            "S": "view_carousel",
            "T": "view_quilt",
            "VG": "grid_on",
            "VK": "view_day",
            "VS": "scrollable_header",
            "VT": "clarify"
        })

    function getLayoutIcon(symbol) {
        return layoutIcons[symbol] || "view_quilt";
    }

    Connections {
        target: MangoService
        function onStateChanged() {
            outputState = parentScreen ? MangoService.getOutputState(parentScreen.name) : null;
        }
    }

    content: Component {
        Item {
            implicitWidth: layout.isVerticalOrientation ? (layout.widgetThickness - layout.horizontalPadding * 2) : layoutContent.implicitWidth
            implicitHeight: layout.isVerticalOrientation ? layoutColumn.implicitHeight : (layout.widgetThickness - layout.horizontalPadding * 2)

            Column {
                id: layoutColumn
                visible: layout.isVerticalOrientation
                anchors.centerIn: parent
                spacing: 1

                DIcon {
                    name: layout.getLayoutIcon(layout.currentLayoutSymbol)
                    size: Theme.barIconSize(layout.barThickness, undefined, layout.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
                    color: layout.contentColor
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                StyledText {
                    text: layout.currentLayoutSymbol
                    font.pixelSize: Theme.barTextSize(layout.barThickness, layout.barConfig?.fontScale, layout.barConfig?.maximizeWidgetText)
                    color: layout.contentColor
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }

            Row {
                id: layoutContent
                visible: !layout.isVerticalOrientation
                anchors.centerIn: parent
                spacing: (barConfig?.noBackground ?? false) ? 1 : 2

                DIcon {
                    name: layout.getLayoutIcon(layout.currentLayoutSymbol)
                    size: Theme.barIconSize(layout.barThickness, -4, layout.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
                    color: layout.contentColor
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: layout.currentLayoutSymbol
                    font.pixelSize: Theme.barTextSize(layout.barThickness, layout.barConfig?.fontScale, layout.barConfig?.maximizeWidgetText)
                    color: layout.contentColor
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    onClicked: {
        toggleLayoutPopup();
    }

    onRightClicked: {
        if (!parentScreen || !MangoService.available || MangoService.layouts.length === 0) {
            return;
        }

        const currentIndex = layout.currentLayoutIndex;
        const nextIndex = (currentIndex + 1) % MangoService.layouts.length;

        MangoService.setLayout(parentScreen.name, nextIndex);
    }
}
