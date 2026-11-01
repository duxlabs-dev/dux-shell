pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Widgets
// Sections load at runtime and their imports are never scanned: only a static import registers Components for them.
import qs.Modules.Settings.Niri.Components
import qs.Modules.Settings.Niri.Drawer
import qs.Modules.Settings.Niri.Sections.Animations
import qs.Modules.Settings.Niri.Sections.Gestures
import qs.Modules.Settings.Niri.Sections.Input
import qs.Modules.Settings.Niri.Sections.Keybinds
import qs.Modules.Settings.Niri.Sections.Windows
import qs.Modules.Settings.Niri.Sections.Workspaces
import qs.Modules.Settings.Niri.Shell
import qs.Modules.Settings.Widgets
import qs.Services
import "../../../Common/niri/shell.js" as Shell

Item {
    id: root

    readonly property var log: Log.scoped("NiriShell")

    property bool pageActive: true
    readonly property bool kdlOpen: sideStack.drawer?.open ?? false
    property bool navOpen: false
    property bool changedOnly: false

    readonly property string currentSection: SettingsUiState.niriSection
    readonly property bool expert: SettingsData.niriPageExpert
    readonly property var modifiedCounts: Shell.modifiedCounts(Object.keys(SettingsData.niriPage), key => NiriPageService.isModified(key))
    readonly property int modifiedTotal: Object.values(modifiedCounts).reduce((sum, n) => sum + n, 0)

    // Breakpoints of the validated mockup (a-final.html), kept in shell.js; NiriTab reads maxWidth
    readonly property real maxWidth: Shell.maxWidth
    readonly property bool wide: width >= Shell.wideMinWidth
    readonly property bool narrow: width <= Shell.narrowMaxWidth
    readonly property bool compact: width <= Shell.compactMaxWidth
    readonly property real menuWidth: wide ? Shell.menuWideWidth : Shell.menuMediumWidth

    readonly property var sections: sectionCatalog.all
    readonly property var visibleSections: sections.filter(section => expert || !section.expertOnly)
    readonly property var currentInfo: sections.find(section => section.id === currentSection) ?? sections[0]
    readonly property var sidePane: Shell.paneOf(sectionLoader.item)
    // "right", "below", "inline" or "" when the side column shows no pane (shell.js)
    readonly property string panePlace: Shell.place(currentSection, sidePane !== null, wide)
    readonly property bool paneBelow: panePlace === "below"
    // Section keepers find the page's Keep banner through their parents and hand it their state
    readonly property var keepBannerHost: keepBanner
    // The health pill finds the include toast the same way and hands it its announcements
    readonly property var includeToastHost: includeBanner

    // Quickshell resolves sibling types only in imported directories: once a part has helper files, import it like Desk
    readonly property Component sectionComponent: Qt.createComponent(Qt.resolvedUrl("Sections/" + currentSection.charAt(0).toUpperCase() + currentSection.slice(1) + "Section.qml"))

    signal searchRequested(string text)
    signal comboCaptured(string combo)

    function readyOr(component, fallback) {
        if (component?.status === Component.Ready)
            return component;
        // An absent file is a part not built yet; any other error is a broken file worth a log line
        if (component?.status === Component.Error && !component.errorString().includes("File not found"))
            root.log.warn("section", currentSection + ":", component.errorString().replace(/file:\/\/\S*\//g, ""));
        return fallback;
    }

    function selectSection(id) {
        SettingsUiState.niriSection = id;
        navOpen = false;
        mainFlick.contentY = 0;
    }

    function toggleKdl() {
        sideStack.drawerWanted = true;
        const drawer = sideStack.drawer;
        if (!drawer)
            return;
        drawer.open = !drawer.open;
    }

    onExpertChanged: {
        if (expert)
            return;
        if (currentInfo.expertOnly)
            selectSection("windows");
    }

    Shortcut {
        sequence: "Ctrl+K"
        enabled: root.pageActive
        onActivated: header.focusSearch()
    }

    Shortcut {
        sequence: "Ctrl+E"
        enabled: root.pageActive && root.expert
        onActivated: root.toggleKdl()
    }

    NiriHeader {
        id: header
        width: parent.width
        compact: root.compact
        searchMinWidth: Shell.searchMinWidth
        expert: root.expert
        kdlOpen: root.kdlOpen
        changedOnly: root.changedOnly
        modifiedTotal: root.modifiedTotal
        onSearchRequested: text => root.searchRequested(text)
        onComboCaptured: combo => root.comboCaptured(combo)
        onKdlToggled: root.toggleKdl()
        onChangedOnlyToggled: root.changedOnly = !root.changedOnly
    }

    Item {
        id: sideMenu

        visible: !root.narrow
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        width: root.narrow ? 0 : root.menuWidth

        NiriNavList {
            anchors.fill: parent
            anchors.topMargin: Theme.spacingM
            anchors.rightMargin: Theme.spacingS
            sections: root.visibleSections
            current: root.currentSection
            counts: root.modifiedCounts
            onPicked: id => root.selectSection(id)
        }

        Rectangle {
            anchors.right: parent.right
            width: Theme.outlineWidth
            height: parent.height
            color: Theme.outlineVariant
        }
    }

    DFlickable {
        id: mainFlick

        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        anchors.left: sideMenu.right
        anchors.right: rightColumn.left
        clip: true
        contentWidth: width
        contentHeight: mainColumn.height

        Column {
            id: mainColumn
            width: mainFlick.width

            NiriNarrowNav {
                visible: root.narrow
                width: parent.width
                sections: root.visibleSections
                current: root.currentSection
                currentText: root.currentInfo.text
                counts: root.modifiedCounts
                open: root.navOpen
                onToggled: root.navOpen = !root.navOpen
                onPicked: id => root.selectSection(id)
            }

            NiriSideSlot {
                id: inlineDeskHolder
                visible: root.panePlace === "inline"
                width: parent.width
                height: visible ? sideStack.height + Theme.outlineWidth : 0
            }

            Column {
                x: root.narrow || root.currentSection === "keybinds" ? Theme.spacingL : Theme.spacingXL
                width: parent.width - x * 2
                topPadding: Theme.spacingL
                bottomPadding: Theme.spacingXL
                spacing: Theme.spacingL

                Rectangle {
                    visible: root.changedOnly && !root.modifiedCounts[root.currentSection]
                    width: parent.width
                    height: nothingText.implicitHeight + Theme.spacingXL * 2
                    radius: Theme.cornerRadiusM
                    color: "transparent"
                    border.width: Theme.outlineWidth
                    border.color: Theme.outlineVariant

                    StyledText {
                        id: nothingText
                        anchors.centerIn: parent
                        width: parent.width - Theme.spacingL * 2
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: I18n.tr("Nothing changed in %1.", "niri page, Changed only filter finds nothing; %1 is the section name").arg(root.currentInfo.text)
                        color: Theme.surfaceVariantText
                    }
                }

                NiriSideHead {
                    icon: root.currentInfo.icon
                    title: root.currentInfo.title ?? root.currentInfo.text
                    textSize: Theme.fontSizeLarge
                }

                Loader {
                    width: parent.width
                    id: sectionLoader
                    sourceComponent: root.readyOr(root.sectionComponent, sectionPlaceholder)

                    Binding {
                        target: sectionLoader.item
                        property: "changedOnly"
                        value: root.changedOnly
                        when: sectionLoader.item !== null && "changedOnly" in sectionLoader.item
                    }
                }
            }

            NiriSideSlot {
                id: belowDeskHolder
                line: "top"
                visible: root.paneBelow
                width: parent.width
                height: visible ? sideStack.height + Theme.outlineWidth : 0
            }
        }
    }

    NiriSideSlot {
        id: rightColumn
        line: "left"
        visible: root.wide && (root.kdlOpen || root.panePlace === "right")
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        width: visible ? (root.kdlOpen ? Shell.drawerColumnWidth : Shell.keysPaneWidth) : 0
        clip: true
    }

    NiriSideStack {
        id: sideStack

        parent: root.wide ? rightColumn : root.paneBelow ? belowDeskHolder : inlineDeskHolder
        x: root.wide ? Theme.outlineWidth : 0
        y: parent === belowDeskHolder ? Theme.outlineWidth : 0
        width: parent.width - x
        sidePane: root.panePlace ? root.sidePane : null
        wide: root.wide
        expert: root.expert
        sectionId: root.currentSection
        title: root.currentInfo.text
    }

    Component {
        id: sectionPlaceholder

        NiriSectionPlaceholder {
            iconName: root.currentInfo.icon
            title: root.currentInfo.text
        }
    }

    NiriSections {
        id: sectionCatalog
    }

    // The mockup floats one « Keep this change? » banner at the top of the page, over every section
    NiriKeep {
        id: keepBanner

        anchors.top: parent.top
        anchors.topMargin: Theme.spacingL
        anchors.horizontalCenter: parent.horizontalCenter
    }

    // « input.kdl added »: the doctor's own include fix, announced only while the Undo is live
    NiriIncludeBanner {
        id: includeBanner

        anchors.top: keepBanner.bottom
        anchors.topMargin: keepBanner.visible ? Theme.spacingS : 0
        anchors.horizontalCenter: parent.horizontalCenter
    }
}

