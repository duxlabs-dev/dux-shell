import QtQuick
import qs.Common
import qs.Modules.Settings
import qs.Services
import qs.DCommon.Widgets

Item {
    id: root

    property var greeterRoot: parent ? parent.greeterRoot : null

    readonly property var curatedPluginIds: ["quickCapture", "dankKDEConnect", "wallpaperCarousel", "calculator", "emojiLauncher", "dockerManager", "dankSoftwareDepot", "homeAssistantMonitor"]

    readonly property real headerIconContainerSize: Math.round(Theme.iconSize * 2)

    property var curatedPlugins: []
    property bool isLoading: false
    property string loadError: ""

    function refresh() {
        isLoading = true;
        loadError = "";
        DMSService.listPlugins(response => {
            isLoading = false;
            if (response.error) {
                loadError = response.error;
                return;
            }
            curatedPlugins = curate(response.result || []);
        });
        if (DMSService.apiVersion >= 8)
            DMSService.listInstalled();
    }

    function curate(registry) {
        const byId = {};
        for (let i = 0; i < registry.length; i++)
            byId[registry[i].id] = registry[i];
        const result = [];
        for (let i = 0; i < curatedPluginIds.length; i++) {
            const plugin = byId[curatedPluginIds[i]];
            if (plugin)
                result.push(plugin);
        }
        return result;
    }

    function markInstalled(installedList) {
        const installedKeys = {};
        for (let i = 0; i < installedList.length; i++) {
            const plugin = installedList[i];
            if (plugin.id)
                installedKeys[plugin.id] = true;
            if (plugin.name)
                installedKeys[plugin.name] = true;
        }
        curatedPlugins = curatedPlugins.map(p => Object.assign({}, p, {
                "installed": installedKeys[p.id] || installedKeys[p.name] || false
            }));
    }

    Component.onCompleted: refresh()

    Connections {
        target: DMSService

        function onInstalledPluginsReceived(plugins) {
            root.markInstalled(plugins);
        }

        function onIsConnectedChanged() {
            if (DMSService.isConnected && root.curatedPlugins.length === 0 && !root.isLoading)
                root.refresh();
        }
    }

    DFlickable {
        anchors.fill: parent
        clip: true
        contentHeight: mainColumn.height + Theme.spacingL * 2
        contentWidth: width

        Column {
            id: mainColumn
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(640, parent.width - Theme.spacingXL * 2)
            topPadding: Theme.spacingL
            spacing: Theme.spacingL

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.spacingM

                Rectangle {
                    width: root.headerIconContainerSize
                    height: root.headerIconContainerSize
                    radius: Math.round(root.headerIconContainerSize * 0.29)
                    color: Theme.primaryContainer
                    anchors.verticalCenter: parent.verticalCenter

                    DIcon {
                        anchors.centerIn: parent
                        name: "extension"
                        size: Theme.iconSize + 4
                        color: Theme.accentOnPrimaryContainer
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingXXS

                    StyledText {
                        text: I18n.tr("Popular Plugins", "greeter plugins page title")
                        font.pixelSize: Theme.fontSizeXLarge
                        color: Theme.surfaceText
                    }

                    StyledText {
                        text: I18n.tr("Community favorites to get you started", "greeter plugins page subtitle")
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.surfaceVariantText
                    }
                }
            }

            Item {
                width: parent.width
                height: Math.round(Theme.fontSizeMedium * 8)
                visible: root.isLoading

                DSpinner {
                    anchors.centerIn: parent
                    running: root.isLoading
                }
            }

            Column {
                width: parent.width
                spacing: Theme.spacingS
                visible: !root.isLoading && root.loadError !== ""

                DIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: "cloud_off"
                    size: Theme.iconSize + 16
                    color: Theme.outline
                }

                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: I18n.tr("Couldn't load plugins", "plugin registry fetch error")
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceVariantText
                }

                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.loadError
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.outline
                }

                DButton {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: I18n.tr("Retry", "retry failed action button")
                    iconName: "refresh"
                    backgroundColor: Theme.chipSurface
                    textColor: Theme.surfaceText
                    onClicked: root.refresh()
                }
            }

            Grid {
                width: parent.width
                columns: 2
                rowSpacing: Theme.spacingS
                columnSpacing: Theme.spacingS
                visible: !root.isLoading && root.curatedPlugins.length > 0

                Repeater {
                    model: root.curatedPlugins

                    PluginCard {
                        required property var modelData

                        width: (parent.width - Theme.spacingS) / 2
                        previewHeight: Math.round(width * 0.45)
                        plugin: modelData
                        installed: modelData.installed || false
                        onClicked: {
                            if (modelData.repo)
                                Qt.openUrlExternally(modelData.repo);
                        }
                        onInstallRequested: PluginService.installFromRegistry(modelData.id, modelData.name, modelData.type === "desktop")
                    }
                }
            }

            GreeterSettingsCard {
                width: parent.width
                iconName: "explore"
                title: I18n.tr("Browse plugins", "plugin browser window title")
                description: I18n.tr("Browse or search plugins")
                visible: !root.isLoading && root.loadError === ""
                onClicked: PopoutService.openSettingsWithTab("plugins")
            }
        }
    }
}
