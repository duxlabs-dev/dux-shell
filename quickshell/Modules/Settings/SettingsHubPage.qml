pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.Modules.Settings.Widgets
import qs.Widgets

FocusScope {
    id: root

    property string hubId: ""
    property var parentModal: null
    property var pageHost: null
    readonly property string headerFile: SettingsTabs.page(hubId)?.hubHeader ?? ""

    readonly property var rows: SettingsTabs.hubMainRows(hubId)
    readonly property var moreRows: SettingsTabs.hubMoreRows(hubId)
    readonly property var footerRows: SettingsTabs.hubFooterRows(hubId)
    readonly property Component headerAdvanced: headerLoader.item?.advancedContent ?? null
    readonly property real contentHeight: flickable.contentHeight
    readonly property bool settling: headerLoader.status === Loader.Loading

    onHubIdChanged: flickable.contentY = 0

    SettingsPage {
        id: flickable

        Loader {
            id: headerLoader

            width: parent.width
            focus: status === Loader.Ready
            source: root.headerFile ? Qt.resolvedUrl(root.headerFile + ".qml") : ""
            onLoaded: item.parentModal = Qt.binding(() => root.parentModal)
        }

        SettingsGroup {
            width: parent.width
            visible: root.rows.length > 0

            Repeater {
                model: root.rows

                SettingsNavRow {
                    required property var modelData

                    iconName: modelData.icon
                    title: modelData.text
                    hint: modelData.hint ?? ""
                    trailingBadge: modelData.kind === "plugin" && PluginService.loadedPlugins[modelData.pluginId] === undefined ? I18n.tr("Disabled") : ""
                    onClicked: keyboard => root.parentModal?.navigateTo(modelData.id, keyboard)
                }
            }
        }

        SettingsGroup {
            width: parent.width
            visible: root.footerRows.length > 0

            Repeater {
                model: root.footerRows

                SettingsNavRow {
                    required property var modelData

                    iconName: modelData.icon
                    title: modelData.hubFooter
                    hint: modelData.hint ?? ""
                    onClicked: keyboard => root.parentModal?.navigateTo(modelData.id, keyboard)
                }
            }
        }

        SettingsAdvancedSection {
            id: advanced

            visible: root.moreRows.length > 0 || root.headerAdvanced !== null

            Loader {
                width: parent.width
                visible: status === Loader.Ready
                sourceComponent: root.headerAdvanced
            }

            Repeater {
                model: root.moreRows

                Column {
                    id: inlinePage

                    required property var modelData

                    width: parent.width

                    StyledText {
                        x: Theme.spacingS
                        width: parent.width - x * 2
                        topPadding: SettingsMetrics.sectionLabelTopGap
                        bottomPadding: SettingsMetrics.sectionLabelBottomGap
                        text: inlinePage.modelData.text
                        font.pixelSize: Theme.fontSizeLarge
                        font.weight: Theme.fontWeightMedium
                        color: Theme.surfaceText
                        wrapMode: Text.WordWrap
                    }

                    Item {
                        id: pageSlot

                        readonly property bool embedsSettingsPage: true
                        property real pageHeight: 0

                        width: parent.width
                        height: pageHeight

                        Loader {
                            readonly property bool wanted: advanced.populated && root.pageHost !== null

                            anchors.fill: parent
                            onWantedChanged: {
                                if (wanted) {
                                    setSource(root.pageHost.pageSource(inlinePage.modelData.id), root.pageHost.pageProperties(inlinePage.modelData.id));
                                    return;
                                }
                                source = "";
                                pageSlot.pageHeight = 0;
                            }
                        }
                    }
                }
            }
        }
    }
}
