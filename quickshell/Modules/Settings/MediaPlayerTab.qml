import QtQuick
import Quickshell.Io
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets
import qs.Modules.DDash
import qs.Services

Item {
    id: root

    property var desktopApps: []
    property var parentModal: null
    property bool mprisProxyRunning: false
    readonly property bool bluetoothMprisEnabled: SettingsData.bluetoothMprisEnabled

    function addExcludedPlayer() {
        const name = excludeEditor.value.trim();
        if (!name)
            return;
        SettingsData.addMediaExcludePlayer(name);
        excludeEditor.value = "";
    }

    function checkMprisProxy(): void {
        if (!root.visible || !root.bluetoothMprisEnabled) {
            mprisProxyRunning = false;
            return;
        }
        if (!mprisProxyCheck.running)
            mprisProxyCheck.running = true;
    }

    Component.onCompleted: desktopApps = AppSearchService.getVisibleApplications() || []
    onVisibleChanged: checkMprisProxy()
    onBluetoothMprisEnabledChanged: checkMprisProxy()

    Process {
        id: mprisProxyCheck
        command: ["sh", "-c", "systemctl --user --quiet is-active mpris-proxy.service 2>/dev/null || pgrep -U \"$(id -u)\" -x mpris-proxy >/dev/null"]
        running: false
        onExited: exitCode => root.mprisProxyRunning = root.visible && root.bluetoothMprisEnabled && exitCode === 0
    }

    Component.onDestruction: {
        desktopApps = [];
    }

    SettingsPage {
        id: mainColumn

        SettingsCard {
            width: parent.width
            iconName: "music_note"
            title: I18n.tr("General")
            settingKey: "mediaPlayer"

            SettingsToggleRow {
                settingKey: "mediaScrollTitle"
                tags: ["scroll", "title", "marquee"]
                text: I18n.tr("Scroll song title")
                checked: SettingsData.scrollTitleEnabled
                onToggled: checked => SettingsData.set("scrollTitleEnabled", checked)
            }

            SettingsToggleRow {
                settingKey: "mediaVisualizer"
                tags: ["visualizer", "cava", "spectrum"]
                text: I18n.tr("Audio visualizer")
                checked: SettingsData.audioVisualizerEnabled
                onToggled: checked => SettingsData.set("audioVisualizerEnabled", checked)
            }

            SettingsToggleRow {
                settingKey: "bluetoothMpris"
                tags: ["bluetooth", "headphones", "media", "mpris", "avrcp"]
                text: I18n.tr("Bluetooth media controls", "Title for the setting that routes Bluetooth headset media buttons through DMS")
                description: root.mprisProxyRunning ? I18n.tr("%1 is running and will create duplicate Bluetooth players. Disable it with: %2", "Warning shown when the legacy BlueZ MPRIS proxy conflicts with DMS Bluetooth media controls, %1 is the service name, %2 a shell command").arg("mpris-proxy").arg("systemctl --user disable --now mpris-proxy.service") : I18n.tr("Route Bluetooth headset controls to the active DMS media player", "Description of how Bluetooth headset media buttons select a player")
                descriptionColor: root.mprisProxyRunning ? Theme.error : Theme.surfaceVariantText
                checked: SettingsData.bluetoothMprisEnabled
                onToggled: checked => SettingsData.set("bluetoothMprisEnabled", checked)
            }

            SettingsNavRow {
                title: I18n.tr("Dashboard")
                hint: I18n.tr("Media")
                iconName: "dashboard"
                onClicked: keyboard => {
                    root.parentModal?.navigateTo("dank_dash", keyboard);
                    SettingsSearchService.navigateToSection("dashOptions:media");
                }
            }

            SettingsRow {
                id: volumeStepRow
                resetKeys: ["audioWheelScrollAmount"]
                title: I18n.tr("Volume step")

                DTextField {
                    outlined: true
                    leftIconName: "volume_up"
                    width: Theme.fieldHeight * 2
                    anchors.verticalCenter: parent.verticalCenter
                    Accessible.name: volumeStepRow.title
                    text: SettingsData.audioWheelScrollAmount.toString()
                    maximumLength: 2
                    validator: IntValidator {
                        bottom: 0
                        top: 99
                    }
                    onEditingFinished: {
                        const value = parseInt(text, 10);
                        if (!isNaN(value))
                            SettingsData.set("audioWheelScrollAmount", value);
                    }
                }
            }
        }

        SettingsCard {
            title: I18n.tr("Lyrics", "Media player lyrics button")
            settingKey: "mediaLyrics"
            tags: ["lyrics", "music", "karaoke", "synced", "word", "timing"]

            SettingsToggleRow {
                settingKey: "mediaLyricsEnabled"
                text: I18n.tr("Lyrics", "Media player lyrics button")
                description: I18n.tr("Sends the playing track, artist and album name to enabled lyrics providers")
                checked: DashRegistry.option("media", "lyrics") === true
                modified: checked !== MediaOptions.defaults.lyrics
                onToggled: checked => DashRegistry.setOption("media", "lyrics", checked)
            }
        }

        SettingsCard {
            title: I18n.tr("Lyrics providers", "Lyrics source priority settings")
            settingKey: "mediaLyricsProviders"
            tags: ["lyrics", "provider", "priority", "order", "source", "lrclib", "better lyrics", "unison", "lyricsplus", "kugou", "youtube music"]

            headerActions: DActionButton {
                iconName: "restart_alt"
                tooltipText: I18n.tr("Reset to default")
                enabled: !SettingsData.isDefault(["mediaLyricsProviders"])
                onClicked: SettingsData.resetToDefault(["mediaLyricsProviders"])
            }

            SettingsRow {
                title: I18n.tr("Drag to reorder")
                subtitle: I18n.tr("Higher providers take priority. Turn all off to use local lyrics only.")
            }

            SettingsReorderList {
                id: lyricsProviderList
                model: MediaOptions.lyricsProviderOrder.split(",")
                onReordered: indices => MediaOptions.reorderLyricsProviders(indices)

                delegate: SettingsReorderRow {
                    id: providerRow
                    required property string modelData
                    readonly property var provider: MediaOptions.lyricsProviders.find(provider => provider.id === modelData)
                    reorderList: lyricsProviderList
                    title: provider?.text ?? ""
                    clickable: true
                    onClicked: MediaOptions.setLyricsProviderEnabled(modelData, !provider?.enabled)

                    DToggle {
                        hideText: true
                        Accessible.name: providerRow.title
                        checked: providerRow.provider?.enabled ?? false
                        onToggled: checked => MediaOptions.setLyricsProviderEnabled(providerRow.modelData, checked)
                    }
                }
            }
        }

        SettingsCard {
            width: parent.width
            iconName: "do_not_disturb_on"
            title: I18n.tr("Excluded players")
            settingKey: "mediaExcludePlayers"
            tags: ["media", "music", "exclude", "ignore", "player", "mpris"]

            SettingsTextFieldRow {
                id: excludeEditor
                leftIconName: "apps"
                text: I18n.tr("Name")
                description: I18n.tr("Matches player identity or desktop file name, case-insensitive")
                placeholderText: I18n.tr("App name or identity (e.g., firefox)")
                onAccepted: root.addExcludedPlayer()

                actions: [
                    DIconButton {
                        variant: "filled"
                        iconName: "add"
                        Accessible.name: I18n.tr("Add")
                        enabled: excludeEditor.value.trim() !== ""
                        onClicked: root.addExcludedPlayer()
                    },
                    DIconButton {
                        iconName: "apps"
                        tooltipText: I18n.tr("Browse")
                        onClicked: appBrowserPopup.show()
                    }
                ]
            }

            Repeater {
                model: SettingsData.mediaExcludePlayers

                delegate: SettingsRow {
                    required property string modelData
                    required property int index

                    title: modelData
                    iconName: "music_off"

                    DActionButton {
                        anchors.verticalCenter: parent.verticalCenter
                        iconName: "delete"
                        iconColor: Theme.error
                        Accessible.name: I18n.tr("Remove")
                        onClicked: SettingsData.removeMediaExcludePlayer(index)
                    }
                }
            }

            SettingsRow {
                visible: !SettingsData.mediaExcludePlayers?.length
                title: I18n.tr("No excluded players configured")
                titleColor: Theme.surfaceVariantText
            }
        }
    }

    AppBrowserPopup {
        id: appBrowserPopup
        appsModel: root.desktopApps
        parentModal: root.parentModal
        onAppSelected: appId => {
            var name = appId;
            if (name.endsWith(".desktop")) {
                name = name.slice(0, -8);
            }
            SettingsData.addMediaExcludePlayer(name);
        }
    }
}
