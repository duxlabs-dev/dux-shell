pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services

Column {
    id: root

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    property string tab: ""
    property var tags: []
    property string settingKey: ""

    property string title: ""
    // Not drawn; extract_settings_index.py reads it for the search result icon
    property string iconName: ""
    property bool collapsible: false
    property bool expanded: true
    property real headerLeftPadding: 0

    default property alias content: contentGroup.content
    property alias headerActions: sectionLabel.actions

    readonly property bool isHighlighted: settingKey !== "" && SettingsSearchService.highlightSection === settingKey
    readonly property bool collapsed: collapsible && !expanded
    readonly property bool hasHeader: root.title !== ""
    property bool userToggledCollapse: false

    width: parent?.width ?? 0
    spacing: 0

    SettingsSearchRegistration {
        target: root
        settingKey: root.settingKey
    }

    SettingsSectionLabel {
        id: sectionLabel
        width: parent.width
        text: root.title
        visible: root.hasHeader
        collapsible: root.collapsible
        expanded: root.expanded
        onToggleRequested: {
            root.userToggledCollapse = true;
            root.expanded = !root.expanded;
        }
    }

    Item {
        id: collapseWrapper
        visible: !root.collapsed || height > 0
        enabled: !root.collapsed
        width: parent.width
        height: root.collapsed ? 0 : contentGroup.implicitHeight
        clip: root.collapsible

        Behavior on height {
            enabled: root.userToggledCollapse && Theme.currentAnimationSpeed !== SettingsData.AnimationSpeed.None
            NumberAnimation {
                duration: SettingsMetrics.transitionDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveCurves.expressiveDefaultSpatial
                onRunningChanged: {
                    if (!running)
                        root.userToggledCollapse = false;
                }
            }
        }

        SettingsGroup {
            id: contentGroup
            width: parent.width
            highlighted: root.isHighlighted
        }
    }
}
