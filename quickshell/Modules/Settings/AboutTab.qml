import QtQuick
import QtQuick.Effects
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets
import qs.Widgets

Item {
    id: root

    property var parentModal: null

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    readonly property string assetsDir: "file://" + Theme.shellDir + "/assets/"
    readonly property string githubUrl: "https://github.com/duxlabs-dev/dux-shell"
    readonly property string kofiUrl: "https://ko-fi.com/duxlabs"
    readonly property string discordUrl: "https://discord.gg/ppWTpKmPgT"

    readonly property var compositor: {
        switch (true) {
        case CompositorService.isHyprland:
            return {
                logo: "hyprland.svg",
                url: "https://hypr.land",
                label: I18n.tr("Hyprland website"),
                discordUrl: "https://discord.com/invite/hQ9XvMUjjr",
                discordLabel: I18n.tr("Hyprland Discord server")
            };
        case CompositorService.isSway:
            return {
                logo: "sway.svg",
                url: "https://swaywm.org",
                label: I18n.tr("Sway website")
            };
        case CompositorService.isScroll:
            return {
                logo: "sway.svg",
                url: "https://github.com/dawsers/scroll",
                label: I18n.tr("Scroll GitHub")
            };
        case CompositorService.isMiracle:
            return {
                logo: "miraclewm.svg",
                url: "https://github.com/miracle-wm-org/miracle-wm",
                label: "miracle-wm"
            };
        case CompositorService.isMango:
            return {
                logo: "mango.png",
                url: "https://github.com/mangowm/mango",
                label: I18n.tr("mangowc GitHub"),
                discordUrl: "https://discord.gg/CPjbDxesh5",
                discordLabel: I18n.tr("mangowc Discord server")
            };
        case CompositorService.isLabwc:
            return {
                logo: "labwc.png",
                url: "https://labwc.github.io/",
                label: I18n.tr("LabWC website"),
                ircUrl: "https://web.libera.chat/gamja/?channels=#labwc"
            };
        case CompositorService.isAqueous:
            return {
                logo: "aqueous.svg",
                url: "",
                label: "Aqueous"
            };
        case CompositorService.isUmbriel:
            return {
                logo: "umbriel.svg",
                url: "https://github.com/noctalia-dev/umbriel",
                label: "Umbriel"
            };
        case CompositorService.isNiri:
            return {
                logo: "niri.svg",
                url: "https://github.com/niri-wm/niri",
                label: I18n.tr("niri GitHub"),
                matrixUrl: "https://matrix.to/#/#niri:matrix.org",
                redditUrl: "https://reddit.com/r/niri"
            };
        default:
            return {
                logo: "niri.svg",
                url: "https://github.com/niri-wm/niri",
                label: I18n.tr("niri GitHub")
            };
        }
    }

    function host(url) {
        return url.replace(/^https?:\/\//, "").replace(/\/$/, "");
    }

    function versionText() {
        const running = SystemUpdateService.shellRunning;
        if (!SystemUpdateService.sysupdateAvailable || !running)
            return ShellVersionService.shellVersion ? `dms ${ShellVersionService.shellVersion}` : "dms";
        if (SystemUpdateService.shellChannel !== "git")
            return /^\d/.test(running) ? `dms v${running}` : `dms ${running}`;
        // COPR builds (0.0.git.N.hash) carry no base version; the VERSION file does.
        const base = running.startsWith("0.0.git") ? ShellVersionService.semverVersion : running.replace(/^v/, "").split("+")[0];
        const build = SystemUpdateService.shellGitBuild;
        return build > 0 ? `dms (git) v${base}-${build}` : `dms (git) ${running}`;
    }

    component LogoImage: Image {
        width: Theme.iconSize
        height: Theme.iconSize
        sourceSize: Qt.size(Theme.iconSize, Theme.iconSize)
        smooth: true
        fillMode: Image.PreserveAspectFit
    }

    SettingsPage {
        ReleaseHero {
            DButton {
                anchors.horizontalCenter: parent.horizontalCenter
                text: I18n.tr("Support DMS", "about page hero button, opens the Ko-fi donation page")
                iconName: "favorite"
                backgroundColor: Theme.primary
                textColor: Theme.onPrimary
                tooltipText: root.host(root.kofiUrl)
                onClicked: Qt.openUrlExternally(root.kofiUrl)
            }
        }

        SettingsCard {
            SettingsRow {
                body: StyledText {
                    text: I18n.tr('DMS is a modern, highly customizable desktop shell that looks great out of the box, without sacrificing the freedom to make it your own.<br/><br/>Built with %1 and %2, it brings together panels, widgets, system controls, and more into a cohesive desktop experience.', 'about page blurb, %1 is a Quickshell link, %2 is a Go link').arg(`<a href="https://quickshell.org" style="text-decoration:none; color:${Theme.primary};">Quickshell</a>`).arg(`<a href="https://go.dev" style="text-decoration:none; color:${Theme.primary};">Go</a>`)
                    textFormat: Text.RichText
                    font.pixelSize: Theme.fontSizeMedium
                    linkColor: Theme.primary
                    onLinkActivated: url => Qt.openUrlExternally(url)
                    color: Theme.surfaceVariantText
                    width: parent.width
                    wrapMode: Text.WordWrap

                    HoverHandler {
                        cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor
                    }
                }
            }
        }

        SettingsCard {
            SettingsLinkRow {
                iconName: "menu_book"
                title: I18n.tr("Docs")
                subtitle: root.host(Site.docs)
                url: Site.docs
            }

            SettingsLinkRow {
                iconName: "extension"
                title: I18n.tr("Plugins")
                subtitle: root.host(Site.plugins)
                url: Site.plugins
            }

            SettingsLinkRow {
                iconName: "code"
                title: "GitHub"
                subtitle: root.host(root.githubUrl)
                url: root.githubUrl
            }
        }

        SettingsCard {
            title: I18n.tr("Community", "about page card title, chat and community links")

            SettingsLinkRow {
                visible: root.compositor.url !== ""
                title: root.compositor.label
                subtitle: root.host(root.compositor.url)
                url: root.compositor.url
                leading: LogoImage {
                    source: root.assetsDir + root.compositor.logo
                }
            }

            SettingsLinkRow {
                title: "niri/dux Discord"
                subtitle: root.host(root.discordUrl)
                url: root.discordUrl
                leading: LogoImage {
                    source: root.assetsDir + "discord.svg"
                }
            }

            SettingsLinkRow {
                visible: (root.compositor.discordUrl ?? "") !== ""
                title: root.compositor.discordLabel ?? ""
                subtitle: root.host(root.compositor.discordUrl ?? "")
                url: root.compositor.discordUrl ?? ""
                leading: LogoImage {
                    source: root.assetsDir + "discord.svg"
                }
            }

            SettingsLinkRow {
                visible: (root.compositor.matrixUrl ?? "") !== ""
                title: I18n.tr("niri Matrix chat")
                subtitle: "matrix.org"
                url: root.compositor.matrixUrl ?? ""
                leading: LogoImage {
                    source: root.assetsDir + "matrix-logo-white.svg"
                    sourceSize: Qt.size(28, 18)
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        colorization: 1
                        colorizationColor: Theme.surfaceText
                    }
                }
            }

            SettingsLinkRow {
                visible: (root.compositor.redditUrl ?? "") !== ""
                title: I18n.tr("r/niri subreddit")
                subtitle: root.host(root.compositor.redditUrl ?? "")
                url: root.compositor.redditUrl ?? ""
                leading: LogoImage {
                    source: root.assetsDir + "reddit.svg"
                }
            }

            SettingsLinkRow {
                visible: (root.compositor.ircUrl ?? "") !== ""
                iconName: "forum"
                title: I18n.tr("LabWC IRC channel")
                subtitle: "libera.chat"
                url: root.compositor.ircUrl ?? ""
            }
        }

        SettingsCard {
            visible: DMSService.isConnected
            iconName: "dns"
            title: I18n.tr("Backend", "noun, settings label for the backend service in use")

            SettingsRow {
                title: I18n.tr("Version")
                trailingBadge: DMSService.cliVersion || "—"
            }

            SettingsRow {
                title: I18n.tr("API", "about page card title, application programming interface version")
                trailingBadge: `v${DMSService.apiVersion}`
            }

            SettingsRow {
                title: I18n.tr("Status")
                trailingBadge: I18n.tr("Connected")

                DBadge {
                    color: Theme.success
                }
            }

            SettingsRow {
                visible: DMSService.capabilities.length > 0
                title: I18n.tr("Capabilities")
                body: Flow {
                    width: parent.width
                    spacing: Theme.spacingS

                    Repeater {
                        model: DMSService.capabilities

                        DBadge {
                            required property string modelData
                            text: modelData
                            color: Theme.primaryHover
                            textColor: Theme.primary
                        }
                    }
                }
            }
        }

        SettingsCard {
            iconName: "build"
            title: I18n.tr("Tools", "about page card title for welcome and system check")

            SettingsNavRow {
                iconName: "system_update_alt"
                title: I18n.tr("Software updates", "settings page, modal and bar widget title, DMS and system package updates")
                hint: root.versionText()
                onClicked: keyboard => root.parentModal?.navigateTo("updater", keyboard)
            }

            SettingsNavRow {
                iconName: "waving_hand"
                title: I18n.tr("Show welcome")
                onClicked: FirstLaunchService.showWelcome()
            }

            SettingsNavRow {
                iconName: "vital_signs"
                title: I18n.tr("System check")
                onClicked: FirstLaunchService.showDoctor()
            }
        }

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: `<a href="${root.githubUrl}/blob/master/LICENSE" style="text-decoration:none; color:${Theme.surfaceVariantText};">${I18n.tr('MIT License')}</a>`
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.surfaceVariantText
            textFormat: Text.RichText
            wrapMode: Text.NoWrap
            onLinkActivated: url => Qt.openUrlExternally(url)

            HoverHandler {
                cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor
            }
        }
    }
}
