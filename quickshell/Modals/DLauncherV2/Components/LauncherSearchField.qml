import QtQuick
import qs.Common
import qs.DCommon.Widgets

DSearchField {
    id: root

    property string mode: "all"
    property bool showModes: false
    property string pluginName: ""
    property string pluginIcon: ""
    property bool pluginIconVisible: true
    property bool flat: false
    readonly property var modes: [
        {
            "label": I18n.tr("All"),
            "mode": "all"
        },
        {
            "label": I18n.tr("Apps", "launcher mode tab, short for applications"),
            "mode": "apps"
        },
        {
            "label": I18n.tr("Files"),
            "mode": "files"
        },
        {
            "label": I18n.tr("Plugins"),
            "mode": "plugins"
        }
    ]
    readonly property int modeIndex: Math.max(0, modes.findIndex(entry => entry.mode === root.mode))
    signal modeSelected(string mode)

    function revealMode() {
        const chip = chips.children.find(child => child.index === root.modeIndex);
        if (!chip)
            return;
        const left = chip.x;
        const right = left + chip.width;
        const maxX = Math.max(0, modeViewport.contentWidth - modeViewport.width);
        if (left < modeViewport.contentX) {
            modeViewport.contentX = Math.max(0, left);
            return;
        }
        if (right > modeViewport.contentX + modeViewport.width)
            modeViewport.contentX = Math.min(maxX, right - modeViewport.width);
    }

    onModeIndexChanged: revealTimer.restart()

    Timer {
        id: revealTimer
        interval: 0
        onTriggered: root.revealMode()
    }

    height: LauncherMetrics.pillHeight
    textColor: Theme.onSurface
    font.pixelSize: Theme.fontSizeLarge
    backgroundColor: flat ? "transparent" : Theme.chipSurface
    normalBorderColor: flat ? "transparent" : Theme.outlineVariant
    leadingContent: pluginName ? pluginBadge : null
    rightAccessoryWidth: modeViewport.visible ? modeViewport.width + Theme.spacingS : 0

    Component {
        id: pluginBadge

        Rectangle {
            implicitWidth: pluginLabel.implicitWidth + (root.pluginIconVisible ? Theme.chipIconSize + Theme.spacingS : 0) + Theme.spacingM * 2
            width: Math.min(implicitWidth, Math.max(0, root.width - root.contentPadding - LauncherMetrics.minSearchWidth - root.accessorySize - Theme.spacingS * 3))
            height: Theme.buttonHeightXS
            radius: Theme.fullRadius(width, height)
            color: Theme.primaryContainer
            clip: true

            DIcon {
                id: pluginIconGlyph
                visible: root.pluginIconVisible
                anchors.left: parent.left
                anchors.leftMargin: Theme.spacingM
                anchors.verticalCenter: parent.verticalCenter
                name: root.pluginIcon || "extension"
                size: Theme.chipIconSize
                color: Theme.onPrimaryContainer
            }

            StyledText {
                id: pluginLabel
                anchors.left: root.pluginIconVisible ? pluginIconGlyph.right : parent.left
                anchors.leftMargin: root.pluginIconVisible ? Theme.spacingS : Theme.spacingM
                anchors.right: parent.right
                anchors.rightMargin: Theme.spacingM
                anchors.verticalCenter: parent.verticalCenter
                text: root.pluginName
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Theme.fontWeightMedium
                color: Theme.onPrimaryContainer
                wrapMode: Text.NoWrap
                elide: I18n.isRtl ? Text.ElideLeft : Text.ElideRight
                maximumLineCount: 1
            }
        }
    }

    DFlickable {
        id: modeViewport
        anchors.right: parent.right
        anchors.rightMargin: Theme.spacingM
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(chips.implicitWidth, Math.max(0, root.width - LauncherMetrics.minSearchWidth - root.leftPadding - root.accessorySize - Theme.spacingS * 3))
        height: LauncherMetrics.modeChipHeight
        visible: root.showModes && !root.pluginName && width > 0
        onWidthChanged: revealTimer.restart()
        contentWidth: chips.implicitWidth
        contentHeight: height
        flickableDirection: Flickable.HorizontalFlick
        clip: true

        DFilterChips {
            id: chips
            width: implicitWidth
            flow: Flow.TopToBottom
            height: chipHeight
            chipHeight: LauncherMetrics.modeChipHeight
            chipRadius: Theme.fullRadius(chipHeight, chipHeight)
            spacing: Theme.spacingXS
            model: root.modes
            Binding on currentIndex {
                value: root.modeIndex
                restoreMode: Binding.RestoreNone
            }
            showCheck: false
            chipPadding: Theme.spacingM
            activeFocusOnTab: false
            onPositioningComplete: revealTimer.restart()
            onSelectionChanged: index => {
                root.modeSelected(root.modes[index].mode);
                root.forceActiveFocus();
            }
        }
    }
}
