pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.DCommon.Widgets
import qs.Widgets

DOSD {
    id: root

    property string iconName: ""
    property string label: ""
    property bool autoShowOnLabelChange: false
    property bool labelReady: true
    property string _lastObservedLabel: ""
    property bool _labelInitialized: false
    readonly property real horizontalPadding: Theme.spacingL
    readonly property real itemSpacing: Theme.spacingM
    readonly property real labelWidth: Theme.pxCeil(labelMeasurer.implicitWidth, dpr)

    osdWidth: Math.min(screenWidth - Theme.spacingM * 2, Theme.pxCeil(Math.max(140, horizontalPadding * 2 + Theme.buttonHeightS + itemSpacing + labelWidth + 1), dpr))
    osdHeight: Theme.osdHeight
    enableMouseInteraction: false

    function _observeLabel() {
        if (!autoShowOnLabelChange)
            return;
        if (!labelReady) {
            _labelInitialized = false;
            _lastObservedLabel = "";
            return;
        }
        if (!_labelInitialized) {
            _lastObservedLabel = label;
            _labelInitialized = true;
            return;
        }
        if (_lastObservedLabel === label)
            return;
        _lastObservedLabel = label;
        show();
    }

    onLabelChanged: _observeLabel()
    onLabelReadyChanged: _observeLabel()
    Component.onCompleted: _observeLabel()

    StyledText {
        id: labelMeasurer
        visible: false
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Theme.fontWeightMedium
        wrapMode: Text.NoWrap
        elide: Text.ElideNone
        text: root.label
    }

    content: Item {
        anchors.fill: parent

        RowLayout {
            anchors {
                fill: parent
                leftMargin: root.horizontalPadding
                rightMargin: root.horizontalPadding
            }
            spacing: root.itemSpacing

            OsdIcon {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: Theme.buttonHeightS
                Layout.preferredHeight: Theme.buttonHeightS
                iconName: root.iconName
            }

            StyledText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                text: root.label
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Theme.fontWeightMedium
                color: Theme.surfaceText
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
            }
        }
    }
}
