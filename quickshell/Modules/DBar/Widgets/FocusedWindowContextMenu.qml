import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.Common
import qs.Modules.DBar
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets

DPopout {
    id: root

    property var currentWindow: null
    property int processId: 0

    readonly property string appId: currentWindow?.appId || ""
    readonly property string windowTitle: currentWindow?.title || ""
    readonly property string appName: appId ? Paths.getAppName(appId, DesktopEntries.heuristicLookup(Paths.moddedAppId(appId))) : I18n.tr("Unknown")
    readonly property int pid: processId
    readonly property string scratchpadName: CompositorService.windowScratchpadName(currentWindow)

    layerNamespace: "dms:focused-window-popout"
    popupWidth: 340
    popupHeight: contentLoader.item ? contentLoader.item.implicitHeight : 260
    triggerWidth: 40
    positioning: ""
    shouldBeVisible: false

    property var matchingRule: null
    readonly property bool hasMatchingRule: matchingRule !== null

    function testPattern(pattern, value) {
        if (!pattern)
            return true;
        try {
            return new RegExp(pattern).test(value || "");
        } catch (e) {
            return pattern === (value || "");
        }
    }

    function matchesCriteria(match, window) {
        if (!match || (!match.appId && !match.title))
            return false;
        return testPattern(match.appId, window.appId) && testPattern(match.title, window.title);
    }

    function findMatchingDmsRule(rules, window) {
        if (!rules || !window)
            return null;
        return rules.find(rule => {
            if (!(rule.source || "").includes("dms/windowrules") || [CompositorService.dmsFloatingRuleId, CompositorService.dmsOpaqueRuleId].includes(rule.id))
                return false;
            const matches = (rule.matches && rule.matches.length > 0) ? rule.matches : (rule.matchCriteria ? [rule.matchCriteria] : []);
            return matches.some(m => matchesCriteria(m, window));
        }) || null;
    }

    function checkMatchingRule() {
        if (!shouldBeVisible || !currentWindow || !CompositorService.supportsWindowRules) {
            matchingRule = null;
            return;
        }

        matchingRule = null;
        const targetWin = currentWindow;
        const compositor = CompositorService.compositor;
        Proc.runCommand("focused-window-rules", [Proc.dmsBin, "config", "windowrules", "list", compositor], (output, exitCode) => {
            if (exitCode !== 0 || targetWin !== currentWindow)
                return;
            try {
                const result = JSON.parse(output.trim());
                matchingRule = findMatchingDmsRule(result.rules, currentWindow);
            } catch (e) {
                matchingRule = null;
            }
        });
    }

    onShouldBeVisibleChanged: {
        if (shouldBeVisible)
            checkMatchingRule();
    }

    onCurrentWindowChanged: {
        if (shouldBeVisible)
            checkMatchingRule();
    }

    function copyValue(value) {
        if (!value)
            return;
        Quickshell.execDetached(["dms", "cl", "copy", value.toString()]);
        ToastService.showInfo(I18n.tr("Copied to clipboard"));
        close();
    }

    function killWindow() {
        if (pid > 0)
            Quickshell.execDetached(["kill", pid.toString()]);
        close();
    }

    function addWindowRule() {
        openWindowRule();
    }

    function openWindowRule() {
        if (!currentWindow || !PopoutService.windowRuleModalLoader)
            return;
        const targetRule = root.matchingRule;
        const targetWin = currentWindow;
        close();

        const loader = PopoutService.windowRuleModalLoader;
        loader.active = true;

        const openModal = () => {
            if (!loader.item)
                return;
            if (targetRule)
                loader.item.showEdit(targetRule);
            else
                loader.item.show(targetWin);
        };

        if (loader.item)
            openModal();
        else
            Qt.callLater(openModal);
    }

    component ActionLabel: Row {
        id: actionLabel

        property string iconName: ""
        property string text: ""
        property color color

        anchors.fill: parent
        anchors.leftMargin: Theme.spacingL
        anchors.rightMargin: Theme.spacingL
        spacing: Theme.spacingS

        DIcon {
            name: actionLabel.iconName
            size: Theme.iconSizeSmall
            color: actionLabel.color
            anchors.verticalCenter: parent.verticalCenter
        }

        StyledText {
            width: parent.width - Theme.iconSizeSmall - Theme.spacingS
            text: actionLabel.text
            color: actionLabel.color
            font.pixelSize: Theme.fontSizeSmall
            elide: Text.ElideRight
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    component ActionItem: DListItem {
        id: actionItem

        property string iconName: ""

        Accessible.name: text

        ActionLabel {
            iconName: actionItem.iconName
            text: actionItem.text
            color: actionItem.contentColor
        }
    }

    onBackgroundClicked: close()

    content: Component {
        Rectangle {
            id: contentRoot

            implicitWidth: 340
            implicitHeight: contentColumn.implicitHeight + PopoutMetrics.contentPadding * 2
            anchors.fill: parent
            color: "transparent"
            focus: true

            Keys.onEscapePressed: event => {
                root.close();
                event.accepted = true;
            }

            Column {
                id: contentColumn
                anchors.fill: parent
                anchors.margins: PopoutMetrics.contentPadding
                spacing: Theme.spacingS

                Row {
                    width: parent.width
                    spacing: Theme.spacingS
                    height: implicitHeight + Theme.spacingS

                    IconImage {
                        width: Theme.iconSizeMedium
                        height: Theme.iconSizeMedium
                        source: Paths.getAppIcon(root.appId, DesktopEntries.heuristicLookup(root.appId))
                        asynchronous: true
                        mipmap: true
                        smooth: true
                    }

                    StyledText {
                        width: parent.width - Theme.iconSizeMedium - Theme.spacingS
                        text: root.appName
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Theme.fontWeightMedium
                        elide: Text.ElideRight
                        maximumLineCount: 2
                        wrapMode: Text.Wrap
                        clip: true
                    }
                }

                Column {
                    width: parent.width
                    spacing: Theme.spacingXXS

                    Repeater {
                        model: [
                            {
                                label: I18n.tr("App ID"),
                                value: root.appId,
                                copyable: !!root.appId,
                                copyTooltip: I18n.tr("Copy App ID")
                            },
                            {
                                label: I18n.tr("Title"),
                                value: root.windowTitle || I18n.tr("Untitled"),
                                copyable: !!root.windowTitle,
                                copyTooltip: I18n.tr("Copy Title")
                            },
                            {
                                label: I18n.tr("PID", "Label for the process ID row in the focused window popout"),
                                value: root.pid > 0 ? root.pid.toString() : I18n.tr("Unavailable"),
                                copyable: root.pid > 0,
                                copyTooltip: I18n.tr("Copy PID")
                            }
                        ]

                        delegate: DListRow {
                            id: copyRow
                            required property var modelData
                            required property int index
                            readonly property real labelWidth: Theme.iconButtonSize + Theme.iconSizeLarge

                            width: contentColumn.width
                            implicitHeight: Theme.listItemHeight
                            firstInGroup: index === 0
                            lastInGroup: index === 2

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.spacingL
                                anchors.rightMargin: Theme.spacingL
                                spacing: Theme.spacingS

                                StyledText {
                                    width: copyRow.labelWidth
                                    text: copyRow.modelData.label
                                    color: copyRow.supportingContentColor
                                    font.pixelSize: Theme.fontSizeSmall
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                StyledText {
                                    width: parent.width - copyRow.labelWidth - Theme.spacingS
                                    text: copyRow.modelData.value
                                    color: copyRow.contentColor
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.family: SettingsData.monoFontFamily
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 2
                                    elide: Text.ElideMiddle
                                    clip: true
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            StateLayer {
                                topLeftRadius: copyRow.firstInGroup ? Theme.groupedListOuterRadius : Theme.groupedListInnerRadius
                                topRightRadius: topLeftRadius
                                bottomLeftRadius: copyRow.lastInGroup ? Theme.groupedListOuterRadius : Theme.groupedListInnerRadius
                                bottomRightRadius: bottomLeftRadius
                                enabled: copyRow.modelData.copyable
                                disabled: !copyRow.modelData.copyable
                                tooltipText: copyRow.modelData.copyable ? copyRow.modelData.copyTooltip : null
                                onClicked: root.copyValue(copyRow.modelData.value)
                            }
                        }
                    }
                }

                Column {
                    visible: actionRepeater.count > 0
                    width: parent.width
                    spacing: Theme.spacingXXS

                    Repeater {
                        id: actionRepeater

                        model: {
                            const items = [];
                            if (root.scratchpadName !== "") {
                                items.push({
                                    icon: "outbox",
                                    text: I18n.tr("Move out of scratchpad", "window context menu action, brings the window back from the special workspace"),
                                    run: () => {
                                        CompositorService.moveWindowOutOfSpecial(root.currentWindow);
                                        root.close();
                                    }
                                });
                            } else {
                                for (const name of CompositorService.specialWorkspaceNames) {
                                    items.push({
                                        icon: "inbox",
                                        text: name === "special" ? I18n.tr("Move to scratchpad", "window context menu action, sends the window to the unnamed special workspace") : I18n.tr("Move to scratchpad: %1", "%1 is the named special workspace").arg(name),
                                        run: () => {
                                            CompositorService.moveWindowToSpecial(root.currentWindow, name);
                                            root.close();
                                        }
                                    });
                                }
                            }
                            if (CompositorService.supportsWindowRules) {
                                items.push({
                                    isRule: true,
                                    run: () => root.openWindowRule()
                                });
                            }
                            return items;
                        }

                        delegate: ActionItem {
                            required property var modelData
                            required property int index

                            width: contentColumn.width
                            firstInGroup: index === 0
                            lastInGroup: index === actionRepeater.count - 1
                            // The rule lookup resolves after opening; binding here keeps the model, and the hovered row, intact.
                            iconName: modelData.isRule ? (root.hasMatchingRule ? "edit" : "rule") : modelData.icon
                            text: modelData.isRule ? (root.hasMatchingRule ? I18n.tr("Edit Window Rule") : I18n.tr("Add window rule")) : modelData.text
                            onClicked: modelData.run()
                        }
                    }
                }

                StyledButton {
                    id: killItem

                    readonly property color itemColor: enabled ? Theme.error : Theme.onSurface_38

                    width: parent.width
                    implicitHeight: Theme.listItemHeight
                    enabled: root.pid > 0
                    text: I18n.tr("Kill Process")
                    Accessible.name: text
                    color: Theme.foregroundColor(Theme.cardSurface, Theme.isFloatingWindow(killItem))
                    border.width: Theme.layerOutlineWidth
                    border.color: Theme.outlineMedium
                    radius: Theme.groupedListOuterRadius
                    onClicked: root.killWindow()

                    StateLayer {
                        control: killItem
                        disabled: !killItem.enabled
                        stateColor: Theme.error
                    }

                    ActionLabel {
                        iconName: "close"
                        text: killItem.text
                        color: killItem.itemColor
                    }
                }
            }
        }
    }
}
