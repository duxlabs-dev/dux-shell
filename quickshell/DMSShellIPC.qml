import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import Quickshell.Services.UPower
import qs.Common
import qs.Modules.DDash
import qs.Services
import qs.Modules.Settings.DisplayConfig

Item {
    id: root
    readonly property var log: Log.scoped("DMSShellIPC")

    required property var processListModalLoaderRef
    required property var controlCenterLoaderRef
    required property var dankDashPopoutLoaderRef
    required property var notepadSlideoutVariantsRef
    required property var hyprKeybindsModalLoaderRef
    required property var dankBarRepeater
    required property var hyprlandOverviewLoader
    required property var workspaceRenameModalLoaderRef
    required property var windowRuleModalLoaderRef
    required property var markupOverlayLoaderRef

    function getPreferredBar(refPropertyName) {
        const focusedScreenName = BarWidgetService.getFocusedScreenName();

        const bars = [];
        if (root.dankBarRepeater) {
            for (let i = 0; i < root.dankBarRepeater.count; i++)
                bars.push(...(root.dankBarRepeater.itemAt(i)?.item?.barVariants?.instances || []));
        }
        for (const screenName in BarWidgetService.frameHostedBars)
            bars.push(...BarWidgetService.frameBarsForScreen(screenName));

        const configOrder = SettingsData.barConfigs.map(config => config.id);
        const screenOrder = Quickshell.screens.map(screen => screen.name);
        const lastBarId = focusedScreenName ? SettingsData.lastUsedBarByScreen[focusedScreenName] : "";
        // Same order as BarWidgetService.resolveIpcWidget, so every IPC path picks the same bar.
        const rank = bar => {
            const screenName = bar.modelData?.name;
            const onFocused = !!focusedScreenName && screenName === focusedScreenName;
            const registration = refPropertyName ? BarWidgetService.registrationForItem(bar[refPropertyName]) : null;
            const tier = !refPropertyName || BarWidgetService.registrationShown(registration) ? 0 : BarWidgetService.registrationLive(registration) ? 1 : 2;
            const position = bar.barConfig?.position;
            return [bar.isIsland ? 1 : 0, onFocused ? 0 : 1, tier, onFocused && bar.barConfig?.id === lastBarId ? 0 : 1, screenOrder.indexOf(screenName), position === SettingsData.Position.Left || position === SettingsData.Position.Right ? 1 : 0, configOrder.indexOf(bar.barConfig?.id)];
        };
        const compare = (a, b) => {
            for (let i = 0; i < a.length; i++) {
                if (a[i] !== b[i])
                    return a[i] - b[i];
            }
            return 0;
        };

        let best = null;
        let bestRank = null;
        for (const bar of bars) {
            if (!bar || (refPropertyName && !bar[refPropertyName]))
                continue;
            const barRank = rank(bar);
            if (!best || compare(barRank, bestRank) < 0) {
                best = bar;
                bestRank = barRank;
            }
        }
        return best;
    }

    readonly property var defaultAppMimeTypes: ({
            browser: "x-scheme-handler/https",
            fileManager: "inode/directory",
            textEditor: "text/plain",
            imageViewer: "image/png",
            videoPlayer: "video/mp4",
            musicPlayer: "audio/mpeg",
            pdfReader: "application/pdf",
            mail: "x-scheme-handler/mailto",
            calendar: "x-scheme-handler/calendar"
        })

    function launchDesktopId(desktopId, appName) {
        if (!desktopId || desktopId.length === 0) {
            log.warn("No default app configured for:", appName);
            return false;
        }

        const entry = SessionService.resolveDesktopId(desktopId);
        if (!entry) {
            log.warn("Default app desktop entry not found:", desktopId, "for:", appName);
            return false;
        }

        SessionService.launchDesktopEntry(entry);
        AppUsageHistoryData.addAppUsage(entry);
        return true;
    }

    function launchDefaultMimeApp(appName, mimeType) {
        DMSService.sendRequest("mime.getDefault", {
            "mimeType": mimeType
        }, response => {
            if (response.error) {
                log.warn("Failed to resolve default app:", appName, response.error);
                return;
            }
            const result = response.result || {};
            root.launchDesktopId(result.desktopId || "", appName);
        });

        return `DEFAULTAPP_LAUNCH_REQUESTED: ${appName}`;
    }

    function parseIdleInhibitMinutes(duration) {
        if (duration === undefined || duration === null)
            return -1;
        const trimmed = String(duration).trim();
        if (!trimmed)
            return -1;
        const minutes = parseInt(trimmed, 10);
        if (isNaN(minutes) || minutes <= 0 || String(minutes) !== trimmed)
            return -1;
        return minutes;
    }

    function idleInhibitStatusMessage() {
        if (!SessionService.idleInhibited)
            return "Idle inhibit is disabled";
        if (SessionData.idleInhibitedUntil <= 0)
            return "Idle inhibit is enabled indefinitely";
        const remainingMs = Math.max(0, SessionData.idleInhibitedUntil - Date.now());
        const remainingMin = Math.ceil(remainingMs / 60000);
        return `Idle inhibit is enabled for ${remainingMin} more minute${remainingMin === 1 ? "" : "s"}`;
    }

    IpcHandler {
        function browser(): string {
            return root.launchDefaultMimeApp("browser", root.defaultAppMimeTypes.browser);
        }

        function fileManager(): string {
            return root.launchDefaultMimeApp("fileManager", root.defaultAppMimeTypes.fileManager);
        }

        function textEditor(): string {
            return root.launchDefaultMimeApp("textEditor", root.defaultAppMimeTypes.textEditor);
        }

        function imageViewer(): string {
            return root.launchDefaultMimeApp("imageViewer", root.defaultAppMimeTypes.imageViewer);
        }

        function videoPlayer(): string {
            return root.launchDefaultMimeApp("videoPlayer", root.defaultAppMimeTypes.videoPlayer);
        }

        function musicPlayer(): string {
            return root.launchDefaultMimeApp("musicPlayer", root.defaultAppMimeTypes.musicPlayer);
        }

        function pdfReader(): string {
            return root.launchDefaultMimeApp("pdfReader", root.defaultAppMimeTypes.pdfReader);
        }

        function mail(): string {
            return root.launchDefaultMimeApp("mail", root.defaultAppMimeTypes.mail);
        }

        function calendar(): string {
            return root.launchDefaultMimeApp("calendar", root.defaultAppMimeTypes.calendar);
        }

        target: "defaultApp"
    }

    IpcHandler {
        function open() {
            PopoutService.openPowerMenu();
            return "POWERMENU_OPEN_SUCCESS";
        }

        function close() {
            PopoutService.closePowerMenu();
            return "POWERMENU_CLOSE_SUCCESS";
        }

        function toggle() {
            PopoutService.togglePowerMenu();
            return "POWERMENU_TOGGLE_SUCCESS";
        }

        target: "powermenu"
    }

    IpcHandler {
        function open(): string {
            root.processListModalLoaderRef.active = true;
            Qt.callLater(() => {
                if (root.processListModalLoaderRef.item)
                    root.processListModalLoaderRef.item.show();
            });

            return "PROCESSLIST_OPEN_SUCCESS";
        }

        function close(): string {
            if (root.processListModalLoaderRef.item)
                root.processListModalLoaderRef.item.hide();

            return "PROCESSLIST_CLOSE_SUCCESS";
        }

        function toggle(): string {
            root.processListModalLoaderRef.active = true;
            Qt.callLater(() => {
                if (root.processListModalLoaderRef.item)
                    root.processListModalLoaderRef.item.toggle();
            });

            return "PROCESSLIST_TOGGLE_SUCCESS";
        }

        function focusOrToggle(): string {
            root.processListModalLoaderRef.active = true;
            Qt.callLater(() => {
                if (root.processListModalLoaderRef.item)
                    root.processListModalLoaderRef.item.focusOrToggle();
            });

            return "PROCESSLIST_FOCUS_OR_TOGGLE_SUCCESS";
        }

        target: "processlist"
    }

    IpcHandler {
        function open(): string {
            if (PopoutService.routeToIsland("controlcenter", null, false, ""))
                return "CONTROL_CENTER_OPEN_SUCCESS";
            const bar = root.getPreferredBar("controlCenterButtonRef");
            if (bar) {
                bar.triggerControlCenter();
                return "CONTROL_CENTER_OPEN_SUCCESS";
            }
            return "CONTROL_CENTER_OPEN_FAILED";
        }

        function openWith(section: string): string {
            if (PopoutService.routeToIsland("controlcenter", null, false, section))
                return "CONTROL_CENTER_OPEN_SUCCESS";
            const popout = root.controlCenterLoaderRef.item;
            if (popout?.shouldBeVisible) {
                popout.expandedSection = section;
                return "CONTROL_CENTER_OPEN_SUCCESS";
            }
            const bar = root.getPreferredBar("controlCenterButtonRef");
            if (!bar)
                return "CONTROL_CENTER_OPEN_FAILED";
            bar.triggerControlCenter();
            const opened = root.controlCenterLoaderRef.item;
            if (!opened)
                return "CONTROL_CENTER_OPEN_SUCCESS";
            if (opened.shouldBeVisible)
                opened.expandedSection = section;
            else
                opened.pendingSection = section;
            return "CONTROL_CENTER_OPEN_SUCCESS";
        }

        function back(): string {
            const content = root.controlCenterLoaderRef.item?.contentLoader?.item;
            if (!content)
                return "CONTROL_CENTER_BACK_FAILED";
            content.goBack();
            return "CONTROL_CENTER_BACK_SUCCESS";
        }

        // The island and the popout can both show the control center, so close and status cover both.
        function hide(): string {
            const islandClosed = PopoutService.closeIslandActivity("controlcenter");
            const popoutOpen = root.controlCenterLoaderRef.item?.shouldBeVisible ?? false;
            if (popoutOpen)
                root.controlCenterLoaderRef.item.close();
            return islandClosed || popoutOpen ? "CONTROL_CENTER_HIDE_SUCCESS" : "CONTROL_CENTER_HIDE_FAILED";
        }

        function toggle(): string {
            if (root.controlCenterLoaderRef.item?.shouldBeVisible) {
                root.controlCenterLoaderRef.item.close();
                return "CONTROL_CENTER_TOGGLE_SUCCESS";
            }
            if (PopoutService.routeToIsland("controlcenter", null, true, ""))
                return "CONTROL_CENTER_TOGGLE_SUCCESS";

            const bar = root.getPreferredBar("controlCenterButtonRef");
            if (bar) {
                bar.triggerControlCenter();
                return "CONTROL_CENTER_TOGGLE_SUCCESS";
            }
            return "CONTROL_CENTER_TOGGLE_FAILED";
        }

        function status(): string {
            const popoutOpen = root.controlCenterLoaderRef.item?.shouldBeVisible ?? false;
            return popoutOpen || PopoutService.islandControlCenterOpen ? "visible" : "hidden";
        }

        target: "control-center"
    }

    IpcHandler {
        // Screenshot region-select handshake
        function begin(): string {
            PopoutManager.screenshotActive = true;
            return "SCREENSHOT_MODE_ON";
        }

        function end(): string {
            PopoutManager.screenshotActive = false;
            return "SCREENSHOT_MODE_OFF";
        }

        function getSurfaces(): string {
            return JSON.stringify(PopoutManager.getActiveSurfaces());
        }

        // options: JSON {path, file, clipboard, notify} from `dms screenshot draw`.
        function draw(options: string): string {
            if (root.markupOverlayLoaderRef.active)
                return "DRAW_BUSY";
            let opts;
            try {
                opts = JSON.parse(options);
            } catch (e) {
                return "DRAW_FAILED";
            }
            if (!opts?.path)
                return "DRAW_FAILED";
            root.markupOverlayLoaderRef.active = true;
            const overlay = root.markupOverlayLoaderRef.item;
            if (!overlay)
                return "DRAW_FAILED";
            overlay.start(opts);
            return "DRAW_OPENED";
        }

        target: "screenshot"
    }

    function dashIslandActivity(tabId) {
        switch (tabId) {
        case "overview":
            return "home";
        case "media":
        case "wallpaper":
        case "weather":
            return tabId;
        default:
            return "";
        }
    }

    function routeDashToIsland(tabId, toggle) {
        const activity = dashIslandActivity(tabId);
        if (activity === "")
            return false;
        return PopoutService.routeToIsland(activity, null, toggle);
    }

    function resolveDashPosition(position) {
        switch ((position || "").toLowerCase()) {
        case "left":
            return "left";
        case "center":
            return "center";
        case "right":
            return "right";
        default:
            return "";
        }
    }

    function dashBar(position) {
        if (position)
            return root.getPreferredBar();
        return root.getPreferredBar("clockButtonRef") || root.getPreferredBar();
    }

    function openDash(tab, position) {
        const tabId = DashRegistry.resolveId(tab);
        if (!position && routeDashToIsland(tabId, false))
            return true;

        const bar = dashBar(position);
        if (!bar)
            return false;

        const dash = root.dankDashPopoutLoaderRef.item;
        if (dash && dash.shouldBeVisible && dash.triggerScreen?.name === bar.screen?.name) {
            if (position && bar.positionDash)
                bar.positionDash(dash, position);
            dash.requestTab(tabId);
            if (dash.updateSurfacePosition)
                dash.updateSurfacePosition();
            return true;
        }

        return bar.triggerDashTab(tabId, position);
    }

    function toggleDash(tab, position) {
        if (root.dankDashPopoutLoaderRef.item?.dashVisible) {
            root.dankDashPopoutLoaderRef.item.dashVisible = false;
            return true;
        }

        const tabId = DashRegistry.resolveId(tab);
        if (!position && routeDashToIsland(tabId, true))
            return true;

        const bar = dashBar(position);
        if (!bar)
            return false;
        return bar.triggerDashTab(tabId, position);
    }

    IpcHandler {
        function resolveTabIndex(tab: string): int {
            return Math.max(0, DashRegistry.indexOf(DashRegistry.resolveId(tab)));
        }

        function open(tab: string): string {
            return root.openDash(tab, "") ? "DASH_OPEN_SUCCESS" : "DASH_OPEN_FAILED";
        }

        function openAt(tab: string, position: string): string {
            return root.openDash(tab, root.resolveDashPosition(position)) ? "DASH_OPEN_SUCCESS" : "DASH_OPEN_FAILED";
        }

        function close(): string {
            const islandClosed = SettingsData.islandDashActivities.filter(activity => PopoutService.closeIslandActivity(activity)).length > 0;
            if (root.dankDashPopoutLoaderRef.item)
                root.dankDashPopoutLoaderRef.item.dashVisible = false;
            return islandClosed || root.dankDashPopoutLoaderRef.item ? "DASH_CLOSE_SUCCESS" : "DASH_CLOSE_FAILED";
        }

        function toggle(tab: string): string {
            return root.toggleDash(tab, "") ? "DASH_TOGGLE_SUCCESS" : "DASH_TOGGLE_FAILED";
        }

        function toggleAt(tab: string, position: string): string {
            return root.toggleDash(tab, root.resolveDashPosition(position)) ? "DASH_TOGGLE_SUCCESS" : "DASH_TOGGLE_FAILED";
        }

        target: "dash"
    }

    IpcHandler {
        function getFocusedScreenName() {
            return CompositorService.getFocusedScreenName();
        }

        function getActiveNotepadInstance() {
            if (root.notepadSlideoutVariantsRef.instances.length === 0) {
                return null;
            }

            if (root.notepadSlideoutVariantsRef.instances.length === 1) {
                return root.notepadSlideoutVariantsRef.instances[0];
            }

            var focusedScreen = getFocusedScreenName();
            if (focusedScreen && root.notepadSlideoutVariantsRef.instances.length > 0) {
                for (var i = 0; i < root.notepadSlideoutVariantsRef.instances.length; i++) {
                    var slideout = root.notepadSlideoutVariantsRef.instances[i];
                    if (slideout.modelData && slideout.modelData.name === focusedScreen) {
                        return slideout;
                    }
                }
            }

            for (var i = 0; i < root.notepadSlideoutVariantsRef.instances.length; i++) {
                var slideout = root.notepadSlideoutVariantsRef.instances[i];
                if (slideout.isVisible) {
                    return slideout;
                }
            }

            return root.notepadSlideoutVariantsRef.instances[0];
        }

        function open(): string {
            if (PopoutService.notepadResolvedMode === "popout") {
                PopoutService.openNotepadPopout();
                return "NOTEPAD_OPEN_SUCCESS";
            }
            var instance = getActiveNotepadInstance();
            if (instance) {
                instance.show();
                return "NOTEPAD_OPEN_SUCCESS";
            }
            return "NOTEPAD_OPEN_FAILED";
        }

        function openFile(path: string): string {
            if (!path)
                return open();
            if (PopoutService.notepadResolvedMode === "popout") {
                PopoutService.openNotepadPopoutWithFile(path);
                return "NOTEPAD_OPEN_FILE_SUCCESS";
            }
            var instance = getActiveNotepadInstance();
            if (instance) {
                instance.show();
                instance.loadedItem?.openExternalFile(path);
                return "NOTEPAD_OPEN_FILE_SUCCESS";
            }
            return "NOTEPAD_OPEN_FILE_FAILED";
        }

        function close(): string {
            if (PopoutService.notepadResolvedMode === "popout") {
                PopoutService.notepadPopout?.hide();
                return "NOTEPAD_CLOSE_SUCCESS";
            }
            var instance = getActiveNotepadInstance();
            if (instance) {
                instance.hide();
                return "NOTEPAD_CLOSE_SUCCESS";
            }
            return "NOTEPAD_CLOSE_FAILED";
        }

        function toggle(): string {
            if (PopoutService.notepadResolvedMode === "popout") {
                PopoutService.toggleNotepadPopout();
                return "NOTEPAD_TOGGLE_SUCCESS";
            }
            var instance = getActiveNotepadInstance();
            if (instance) {
                instance.toggle();
                return "NOTEPAD_TOGGLE_SUCCESS";
            }
            return "NOTEPAD_TOGGLE_FAILED";
        }

        function expand(): string {
            var instance = getActiveNotepadInstance();
            if (instance) {
                instance.expandedWidth = true;
                if (!instance.isVisible)
                    instance.show();
                return "NOTEPAD_EXPAND_SUCCESS";
            }
            return "NOTEPAD_EXPAND_FAILED";
        }

        function collapse(): string {
            var instance = getActiveNotepadInstance();
            if (instance) {
                instance.expandedWidth = false;
                if (!instance.isVisible)
                    instance.show();
                return "NOTEPAD_COLLAPSE_SUCCESS";
            }
            return "NOTEPAD_COLLAPSE_FAILED";
        }

        function toggleExpand(): string {
            var instance = getActiveNotepadInstance();
            if (instance) {
                instance.expandedWidth = !instance.expandedWidth;
                return "NOTEPAD_TOGGLE_EXPAND_SUCCESS";
            }
            return "NOTEPAD_TOGGLE_EXPAND_FAILED";
        }

        target: "notepad"
    }

    IpcHandler {
        function toggle(): string {
            SessionService.toggleIdleInhibit();
            return root.idleInhibitStatusMessage();
        }

        function enable(): string {
            SessionService.enableIdleInhibit();
            return root.idleInhibitStatusMessage();
        }

        function enableFor(minutes: string): string {
            const parsed = root.parseIdleInhibitMinutes(minutes);
            if (parsed < 0)
                return "Invalid duration. Use minutes, e.g. 60.";
            SessionService.enableIdleInhibit(parsed);
            return root.idleInhibitStatusMessage();
        }

        function disable(): string {
            SessionService.disableIdleInhibit();
            return "Idle inhibit is disabled";
        }

        function status(): string {
            return root.idleInhibitStatusMessage();
        }

        function reason(newReason: string): string {
            if (!newReason) {
                return `Current reason: ${SessionService.inhibitReason}`;
            }

            SessionService.setInhibitReason(newReason);
            return `Inhibit reason set to: ${newReason}`;
        }

        target: "inhibit"
    }

    IpcHandler {
        function list(): string {
            return MprisController.availablePlayers.map(p => p.identity).join("\n");
        }

        function play(): void {
            MprisController.play();
        }

        function pause(): void {
            MprisController.pause();
        }

        function playPause(): void {
            MprisController.playPause();
        }

        function previous(): void {
            MprisController.previousOrRewind();
        }

        function next(): void {
            MprisController.next();
        }

        function stop(): void {
            MprisController.stop();
        }

        function increment(step: string): string {
            if (MprisController.activePlayer && MprisController.activePlayer.volumeSupported) {
                const currentVolume = Math.round(MprisController.activePlayer.volume * 100);
                const stepValue = parseInt(step || "5");
                const newVolume = Math.max(0, Math.min(100, currentVolume + stepValue));

                MprisController.activePlayer.volume = newVolume / 100;
                return `Player volume increased to ${newVolume}%`;
            }
        }

        function decrement(step: string): string {
            if (MprisController.activePlayer && MprisController.activePlayer.volumeSupported) {
                const currentVolume = Math.round(MprisController.activePlayer.volume * 100);
                const stepValue = parseInt(step || "5");
                const newVolume = Math.max(0, Math.min(100, currentVolume - stepValue));

                MprisController.activePlayer.volume = newVolume / 100;
                return `Player volume decreased to ${newVolume}%`;
            }
        }

        function setvolume(percentage: string): string {
            if (MprisController.activePlayer && MprisController.activePlayer.volumeSupported) {
                const clampedVolume = Math.max(0, Math.min(100, percentage));
                MprisController.activePlayer.volume = clampedVolume / 100;
                return `Player volume set to ${clampedVolume}%`;
            }
        }

        target: "mpris"
    }

    IpcHandler {
        function toggle(provider: string): string {
            if (!provider)
                return "ERROR: No provider specified";

            KeybindsService.loadCheatsheet(provider);
            root.hyprKeybindsModalLoaderRef.active = true;

            if (!root.hyprKeybindsModalLoaderRef.item)
                return `KEYBINDS_TOGGLE_FAILED: ${provider}`;

            if (root.hyprKeybindsModalLoaderRef.item.shouldBeVisible)
                root.hyprKeybindsModalLoaderRef.item.close();
            else
                root.hyprKeybindsModalLoaderRef.item.open();
            return `KEYBINDS_TOGGLE_SUCCESS: ${provider}`;
        }

        function toggleWithPath(provider: string, path: string): string {
            if (!provider)
                return "ERROR: No provider specified";

            KeybindsService.loadCheatsheet(provider);
            root.hyprKeybindsModalLoaderRef.active = true;

            if (!root.hyprKeybindsModalLoaderRef.item)
                return `KEYBINDS_TOGGLE_FAILED: ${provider}`;

            if (root.hyprKeybindsModalLoaderRef.item.shouldBeVisible)
                root.hyprKeybindsModalLoaderRef.item.close();
            else
                root.hyprKeybindsModalLoaderRef.item.open();
            return `KEYBINDS_TOGGLE_SUCCESS: ${provider} (${path})`;
        }

        function open(provider: string): string {
            if (!provider)
                return "ERROR: No provider specified";

            KeybindsService.loadCheatsheet(provider);
            root.hyprKeybindsModalLoaderRef.active = true;

            if (!root.hyprKeybindsModalLoaderRef.item)
                return `KEYBINDS_OPEN_FAILED: ${provider}`;

            root.hyprKeybindsModalLoaderRef.item.open();
            return `KEYBINDS_OPEN_SUCCESS: ${provider}`;
        }

        function openWithPath(provider: string, path: string): string {
            if (!provider)
                return "ERROR: No provider specified";

            KeybindsService.loadCheatsheet(provider);
            root.hyprKeybindsModalLoaderRef.active = true;

            if (!root.hyprKeybindsModalLoaderRef.item)
                return `KEYBINDS_OPEN_FAILED: ${provider}`;

            root.hyprKeybindsModalLoaderRef.item.open();
            return `KEYBINDS_OPEN_SUCCESS: ${provider} (${path})`;
        }

        function close(): string {
            if (!root.hyprKeybindsModalLoaderRef.item)
                return "KEYBINDS_CLOSE_FAILED";

            root.hyprKeybindsModalLoaderRef.item.close();
            return "KEYBINDS_CLOSE_SUCCESS";
        }

        target: "keybinds"
    }

    IpcHandler {
        function openBinds(): string {
            if (!CompositorService.isHyprland)
                return "HYPR_NOT_AVAILABLE";

            KeybindsService.currentProvider = "hyprland";
            KeybindsService.loadBinds();
            root.hyprKeybindsModalLoaderRef.active = true;

            if (!root.hyprKeybindsModalLoaderRef.item)
                return "HYPR_KEYBINDS_OPEN_FAILED";

            root.hyprKeybindsModalLoaderRef.item.open();
            return "HYPR_KEYBINDS_OPEN_SUCCESS";
        }

        function closeBinds(): string {
            if (!CompositorService.isHyprland)
                return "HYPR_NOT_AVAILABLE";

            if (!root.hyprKeybindsModalLoaderRef.item)
                return "HYPR_KEYBINDS_CLOSE_FAILED";

            root.hyprKeybindsModalLoaderRef.item.close();
            return "HYPR_KEYBINDS_CLOSE_SUCCESS";
        }

        function toggleBinds(): string {
            if (!CompositorService.isHyprland)
                return "HYPR_NOT_AVAILABLE";

            KeybindsService.currentProvider = "hyprland";
            KeybindsService.loadBinds();
            root.hyprKeybindsModalLoaderRef.active = true;

            if (!root.hyprKeybindsModalLoaderRef.item)
                return "HYPR_KEYBINDS_TOGGLE_FAILED";

            if (root.hyprKeybindsModalLoaderRef.item.shouldBeVisible) {
                root.hyprKeybindsModalLoaderRef.item.close();
            } else {
                root.hyprKeybindsModalLoaderRef.item.open();
            }
            return "HYPR_KEYBINDS_TOGGLE_SUCCESS";
        }

        function toggleOverview(): string {
            if (!CompositorService.isHyprland || !root.hyprlandOverviewLoader.item) {
                return "HYPR_NOT_AVAILABLE";
            }
            root.hyprlandOverviewLoader.item.overviewOpen = !root.hyprlandOverviewLoader.item.overviewOpen;
            return root.hyprlandOverviewLoader.item.overviewOpen ? "OVERVIEW_OPEN_SUCCESS" : "OVERVIEW_CLOSE_SUCCESS";
        }

        function closeOverview(): string {
            if (!CompositorService.isHyprland || !root.hyprlandOverviewLoader.item) {
                return "HYPR_NOT_AVAILABLE";
            }
            root.hyprlandOverviewLoader.item.overviewOpen = false;
            return "OVERVIEW_CLOSE_SUCCESS";
        }

        function openOverview(): string {
            if (!CompositorService.isHyprland || !root.hyprlandOverviewLoader.item) {
                return "HYPR_NOT_AVAILABLE";
            }
            root.hyprlandOverviewLoader.item.overviewOpen = true;
            return "OVERVIEW_OPEN_SUCCESS";
        }

        target: "hypr"
    }

    // ! TODO - remove for v1.6
    IpcHandler {
        function wallpaper(): string {
            if (PopoutService.routeToIsland("wallpaper", null, true))
                return "WARN; deprecated, use dms ipc call dash toggle wallpaper instead";
            const bar = root.getPreferredBar("clockButtonRef") || root.getPreferredBar();
            if (bar) {
                bar.triggerWallpaperBrowser();
                return "WARN; deprecated, use dms ipc call dash toggle wallpaper instead";
            }
            return "ERROR: Failed to toggle wallpaper browser";
        }

        target: "dankdash"
    }

    function getBarConfig(selector: string, value: string): var {
        const barSelectors = ["id", "name", "index"];
        if (!barSelectors.includes(selector))
            return {
                error: "BAR_INVALID_SELECTOR"
            };
        const index = selector === "index" ? Number(value) : SettingsData.barConfigs.findIndex(bar => bar[selector] == value);
        const barConfig = SettingsData.barConfigs?.[index];
        if (!barConfig)
            return {
                error: "BAR_NOT_FOUND"
            };
        return {
            barConfig
        };
    }

    function withBarConfig(selector: string, value: string, allowIsland: bool, action: var): string {
        const {
            barConfig,
            error
        } = getBarConfig(selector, value);
        if (error)
            return error;
        if (!allowIsland && SettingsData.isIslandBarConfig(barConfig))
            return "BAR_IS_ISLAND";
        return action(barConfig);
    }

    IpcHandler {
        function reveal(selector: string, value: string): string {
            return withBarConfig(selector, value, false, bar => {
                SettingsData.updateBarConfig(bar.id, {
                    visible: true
                });
                return "BAR_SHOW_SUCCESS";
            });
        }

        function hide(selector: string, value: string): string {
            return withBarConfig(selector, value, false, bar => {
                SettingsData.updateBarConfig(bar.id, {
                    visible: false
                });
                return "BAR_HIDE_SUCCESS";
            });
        }

        function toggle(selector: string, value: string): string {
            return withBarConfig(selector, value, false, bar => {
                SettingsData.updateBarConfig(bar.id, {
                    visible: !bar.visible
                });
                return !bar.visible ? "BAR_SHOW_SUCCESS" : "BAR_HIDE_SUCCESS";
            });
        }

        function status(selector: string, value: string): string {
            return withBarConfig(selector, value, true, bar => bar.visible ? "visible" : "hidden");
        }

        function autoHide(selector: string, value: string): string {
            return withBarConfig(selector, value, false, bar => {
                SettingsData.updateBarConfig(bar.id, {
                    autoHide: true
                });
                return "BAR_AUTO_HIDE_SUCCESS";
            });
        }

        function manualHide(selector: string, value: string): string {
            return withBarConfig(selector, value, false, bar => {
                SettingsData.updateBarConfig(bar.id, {
                    autoHide: false
                });
                return "BAR_MANUAL_HIDE_SUCCESS";
            });
        }

        function toggleAutoHide(selector: string, value: string): string {
            return withBarConfig(selector, value, false, bar => {
                SettingsData.updateBarConfig(bar.id, {
                    autoHide: !bar.autoHide
                });
                return bar.autoHide ? "BAR_MANUAL_HIDE_SUCCESS" : "BAR_AUTO_HIDE_SUCCESS";
            });
        }

        function toggleReveal(selector: string, value: string): string {
            return withBarConfig(selector, value, false, bar => {
                if (!bar.autoHide)
                    return "BAR_AUTO_HIDE_DISABLED";
                if (!(bar.visible ?? true)) {
                    SettingsData.updateBarConfig(bar.id, {
                        visible: true
                    });
                    SettingsData.setBarIpcReveal(bar.id, true);
                    return "BAR_REVEAL_SUCCESS";
                }
                const revealed = SettingsData.toggleBarIpcReveal(bar.id);
                return revealed ? "BAR_REVEAL_SUCCESS" : "BAR_TUCK_SUCCESS";
            });
        }

        function getPosition(selector: string, value: string): string {
            return withBarConfig(selector, value, true, bar => ["top", "bottom", "left", "right"][bar.position] || "unknown");
        }

        function setPosition(selector: string, value: string, position: string): string {
            return withBarConfig(selector, value, true, bar => {
                const positionMap = {
                    "top": SettingsData.Position.Top,
                    "bottom": SettingsData.Position.Bottom,
                    "left": SettingsData.Position.Left,
                    "right": SettingsData.Position.Right
                };
                const posValue = positionMap[position.toLowerCase()];
                if (posValue === undefined)
                    return "BAR_INVALID_POSITION";
                SettingsData.updateBarConfig(bar.id, {
                    position: posValue
                });
                return "BAR_POSITION_SET_SUCCESS";
            });
        }

        target: "bar"
    }

    // Outside the handler so it stays a helper rather than a callable dock command.
    function dockConfigFor(selector: string): var {
        return SettingsData.dockConfigForAction(BarWidgetService.getFocusedScreenName(), selector);
    }

    IpcHandler {
        target: "dock"

        function reveal(): string {
            return revealFor("");
        }
        function hide(): string {
            return hideFor("");
        }
        function toggle(): string {
            return toggleFor("");
        }
        function status(): string {
            return statusFor("");
        }
        function revealFor(selector: string): string {
            const config = root.dockConfigFor(selector);
            if (!config)
                return "DOCK_NOT_FOUND";
            SettingsData.updateDockConfig(config.id, {
                enabled: true
            });
            return "DOCK_SHOW_SUCCESS";
        }
        function hideFor(selector: string): string {
            const config = root.dockConfigFor(selector);
            if (!config)
                return "DOCK_NOT_FOUND";
            SettingsData.updateDockConfig(config.id, {
                enabled: false
            });
            return "DOCK_HIDE_SUCCESS";
        }
        function toggleFor(selector: string): string {
            const config = root.dockConfigFor(selector);
            if (!config)
                return "DOCK_NOT_FOUND";
            return config.enabled ? hideFor(config.id) : revealFor(config.id);
        }
        function statusFor(selector: string): string {
            const config = root.dockConfigFor(selector);
            return config ? (config.enabled ? "visible" : "hidden") : "DOCK_NOT_FOUND";
        }
        function edit(): string {
            return editFor("");
        }
        function editFor(selector: string): string {
            const config = root.dockConfigFor(selector);
            if (!config)
                return "DOCK_NOT_FOUND";
            if (!config.enabled)
                return "DOCK_HIDDEN";
            BarWidgetService.dockEditRequested(config.id);
            return "DOCK_EDIT_SUCCESS";
        }
        function autoHide(): string {
            return autoHideFor("", true);
        }
        function manualHide(): string {
            return autoHideFor("", false);
        }
        function toggleAutoHide(): string {
            const config = root.dockConfigFor("");
            if (!config)
                return "DOCK_NOT_FOUND";
            return autoHideFor(config.id, !config.autoHide);
        }
        function autoHideFor(selector: string, enabled: bool): string {
            const config = root.dockConfigFor(selector);
            if (!config)
                return "DOCK_NOT_FOUND";
            SettingsData.updateDockConfig(config.id, {
                autoHide: enabled,
                smartAutoHide: false
            });
            return enabled ? "BAR_AUTO_HIDE_SUCCESS" : "BAR_MANUAL_HIDE_SUCCESS";
        }
    }

    IpcHandler {
        function open(): string {
            PopoutService.openSettings();
            return "SETTINGS_OPEN_SUCCESS";
        }

        function openWith(tab: string): string {
            if (!tab)
                return "SETTINGS_OPEN_FAILED: No tab specified";
            if (!SettingsTabs.resolvePage(tab))
                return `SETTINGS_OPEN_FAILED: Unknown tab ${tab}`;
            PopoutService.openSettingsWithTab(tab);
            return `SETTINGS_OPEN_SUCCESS: ${tab}`;
        }

        function close(): string {
            PopoutService.closeSettings();
            return "SETTINGS_CLOSE_SUCCESS";
        }

        function toggle(): string {
            PopoutService.toggleSettings();
            return "SETTINGS_TOGGLE_SUCCESS";
        }

        function toggleWith(tab: string): string {
            if (!tab)
                return "SETTINGS_TOGGLE_FAILED: No tab specified";
            if (!SettingsTabs.resolvePage(tab))
                return `SETTINGS_TOGGLE_FAILED: Unknown tab ${tab}`;
            PopoutService.toggleSettingsWithTab(tab);
            return `SETTINGS_TOGGLE_SUCCESS: ${tab}`;
        }

        function focusOrToggle(): string {
            PopoutService.focusOrToggleSettings();
            return "SETTINGS_FOCUS_OR_TOGGLE_SUCCESS";
        }

        function focusOrToggleWith(tab: string): string {
            if (!tab)
                return "SETTINGS_FOCUS_OR_TOGGLE_FAILED: No tab specified";
            if (!SettingsTabs.resolvePage(tab))
                return `SETTINGS_FOCUS_OR_TOGGLE_FAILED: Unknown tab ${tab}`;
            PopoutService.focusOrToggleSettingsWithTab(tab);
            return `SETTINGS_FOCUS_OR_TOGGLE_SUCCESS: ${tab}`;
        }

        function tabs(): string {
            return SettingsTabs.listPageIds().join("\n");
        }

        function get(key: string): string {
            return JSON.stringify(SettingsData?.[key]);
        }

        function dump(): string {
            return SettingsData.getCurrentSettingsJson();
        }

        function dumpSession(): string {
            return SessionData.getCurrentSessionJson();
        }

        function set(key: string, value: string): string {
            if (AdminPolicy.disableSettingsIpcSet)
                return "SETTINGS_SET_DISABLED";
            if (!(key in SettingsData)) {
                log.warn("Cannot set property, not found:", key);
                return "SETTINGS_INVALID_KEY";
            }

            const typeName = typeof SettingsData?.[key];

            try {
                switch (typeName) {
                case "boolean":
                    if (value === "true" || value === "false")
                        value = (value === "true");
                    else
                        throw `${value} is not a Boolean`;
                    break;
                case "number":
                    value = Number(value);
                    if (isNaN(value))
                        throw `${value} is not a Number`;
                    break;
                case "string":
                    value = String(value);
                    break;
                case "object":
                    // NOTE: Parsing lists is messed up upstream and not sure if we want
                    // to make sure objects are well structured or just let people set
                    // whatever they want but risking messed up settings.
                    // Objects & Arrays are disabled for now
                    // https://github.com/quickshell-mirror/quickshell/pull/22
                    throw "Setting Objects and Arrays not supported";
                default:
                    throw "Unsupported type";
                }

                log.warn("Setting:", key, value);
                SettingsData[key] = value;
                SettingsData.saveSettings();
                return "SETTINGS_SET_SUCCESS";
            } catch (e) {
                log.warn("Failed to set property:", key, "error:", e);
                return "SETTINGS_SET_FAILURE";
            }
        }

        target: "settings"
    }

    IpcHandler {
        function browse(type: string) {
            const modal = PopoutService.settingsModal;
            if (modal) {
                if (type === "wallpaper") {
                    modal.openWallpaperBrowser(false);
                } else if (type === "profile") {
                    modal.openProfileBrowser(false);
                }
            } else {
                PopoutService.openSettings();
            }
        }

        target: "file"
    }

    IpcHandler {
        function toggle(widgetId: string): string {
            if (!widgetId)
                return "ERROR: No widget ID specified";

            if (!BarWidgetService.ensureWidget(widgetId))
                return `WIDGET_NOT_FOUND: ${widgetId}`;

            const success = BarWidgetService.triggerWidgetPopout(widgetId);
            return success ? `WIDGET_TOGGLE_SUCCESS: ${widgetId}` : `WIDGET_TOGGLE_FAILED: ${widgetId}`;
        }

        function openWith(widgetId: string, mode: string): string {
            if (!widgetId)
                return "ERROR: No widget ID specified";
            if (!BarWidgetService.ensureWidget(widgetId))
                return `WIDGET_NOT_FOUND: ${widgetId}`;

            const widget = BarWidgetService.getWidgetOnFocusedScreen(widgetId);
            if (!widget)
                return `WIDGET_NOT_AVAILABLE: ${widgetId}`;
            if (typeof widget.openWithMode !== "function")
                return `WIDGET_OPEN_WITH_NOT_SUPPORTED: ${widgetId}`;

            widget.openWithMode(mode || "all");
            return `WIDGET_OPEN_WITH_SUCCESS: ${widgetId} ${mode}`;
        }

        function toggleWith(widgetId: string, mode: string): string {
            if (!widgetId)
                return "ERROR: No widget ID specified";
            if (!BarWidgetService.ensureWidget(widgetId))
                return `WIDGET_NOT_FOUND: ${widgetId}`;

            const widget = BarWidgetService.getWidgetOnFocusedScreen(widgetId);
            if (!widget)
                return `WIDGET_NOT_AVAILABLE: ${widgetId}`;
            if (typeof widget.toggleWithMode !== "function")
                return `WIDGET_TOGGLE_WITH_NOT_SUPPORTED: ${widgetId}`;

            widget.toggleWithMode(mode || "all");
            return `WIDGET_TOGGLE_WITH_SUCCESS: ${widgetId} ${mode}`;
        }

        function openQuery(widgetId: string, query: string): string {
            if (!widgetId)
                return "ERROR: No widget ID specified";
            if (!BarWidgetService.ensureWidget(widgetId))
                return `WIDGET_NOT_FOUND: ${widgetId}`;

            const widget = BarWidgetService.getWidgetOnFocusedScreen(widgetId);
            if (!widget)
                return `WIDGET_NOT_AVAILABLE: ${widgetId}`;
            if (typeof widget.openWithQuery !== "function")
                return `WIDGET_OPEN_QUERY_NOT_SUPPORTED: ${widgetId}`;

            widget.openWithQuery(query || "");
            return `WIDGET_OPEN_QUERY_SUCCESS: ${widgetId}`;
        }

        function toggleQuery(widgetId: string, query: string): string {
            if (!widgetId)
                return "ERROR: No widget ID specified";
            if (!BarWidgetService.ensureWidget(widgetId))
                return `WIDGET_NOT_FOUND: ${widgetId}`;

            const widget = BarWidgetService.getWidgetOnFocusedScreen(widgetId);
            if (!widget)
                return `WIDGET_NOT_AVAILABLE: ${widgetId}`;
            if (typeof widget.toggleWithQuery !== "function")
                return `WIDGET_TOGGLE_QUERY_NOT_SUPPORTED: ${widgetId}`;

            widget.toggleWithQuery(query || "");
            return `WIDGET_TOGGLE_QUERY_SUCCESS: ${widgetId}`;
        }

        function list(): string {
            const widgets = BarWidgetService.getRegisteredWidgetIds();
            if (widgets.length === 0)
                return "No widgets registered";

            const lines = [];
            for (const widgetId of widgets) {
                const widget = BarWidgetService.getWidgetOnFocusedScreen(widgetId);
                let state = "";
                if (widget?.effectiveVisible !== undefined)
                    state = widget.effectiveVisible ? " [visible]" : " [hidden]";
                lines.push(widgetId + state);
            }
            return lines.join("\n");
        }

        function status(widgetId: string): string {
            if (!widgetId)
                return "ERROR: No widget ID specified";

            if (!BarWidgetService.hasWidget(widgetId))
                return `WIDGET_NOT_FOUND: ${widgetId}`;

            const widget = BarWidgetService.getWidgetOnFocusedScreen(widgetId);
            if (!widget)
                return `WIDGET_NOT_AVAILABLE: ${widgetId}`;

            if (!widget.popoutTarget)
                return `WIDGET_NO_POPOUT: ${widgetId}`;
            return widget.popoutTarget.shouldBeVisible ? "visible" : "hidden";
        }

        function reveal(widgetId: string): string {
            if (!widgetId)
                return "ERROR: No widget ID specified";

            if (!BarWidgetService.hasWidget(widgetId))
                return `WIDGET_NOT_FOUND: ${widgetId}`;

            const widget = BarWidgetService.getWidgetOnFocusedScreen(widgetId);
            if (!widget)
                return `WIDGET_NOT_AVAILABLE: ${widgetId}`;

            if (typeof widget.setVisibilityOverride === "function") {
                widget.setVisibilityOverride(true);
                return `WIDGET_REVEAL_SUCCESS: ${widgetId}`;
            }
            return `WIDGET_REVEAL_NOT_SUPPORTED: ${widgetId}`;
        }

        function hide(widgetId: string): string {
            if (!widgetId)
                return "ERROR: No widget ID specified";

            if (!BarWidgetService.hasWidget(widgetId))
                return `WIDGET_NOT_FOUND: ${widgetId}`;

            const widget = BarWidgetService.getWidgetOnFocusedScreen(widgetId);
            if (!widget)
                return `WIDGET_NOT_AVAILABLE: ${widgetId}`;

            if (typeof widget.setVisibilityOverride === "function") {
                widget.setVisibilityOverride(false);
                return `WIDGET_HIDE_SUCCESS: ${widgetId}`;
            }
            return `WIDGET_HIDE_NOT_SUPPORTED: ${widgetId}`;
        }

        function reset(widgetId: string): string {
            if (!widgetId)
                return "ERROR: No widget ID specified";

            if (!BarWidgetService.hasWidget(widgetId))
                return `WIDGET_NOT_FOUND: ${widgetId}`;

            const widget = BarWidgetService.getWidgetOnFocusedScreen(widgetId);
            if (!widget)
                return `WIDGET_NOT_AVAILABLE: ${widgetId}`;

            if (typeof widget.clearVisibilityOverride === "function") {
                widget.clearVisibilityOverride();
                return `WIDGET_RESET_SUCCESS: ${widgetId}`;
            }
            return `WIDGET_RESET_NOT_SUPPORTED: ${widgetId}`;
        }

        function visibility(widgetId: string): string {
            if (!widgetId)
                return "ERROR: No widget ID specified";

            if (!BarWidgetService.hasWidget(widgetId))
                return `WIDGET_NOT_FOUND: ${widgetId}`;

            const widget = BarWidgetService.getWidgetOnFocusedScreen(widgetId);
            if (!widget)
                return `WIDGET_NOT_AVAILABLE: ${widgetId}`;

            if (widget.effectiveVisible !== undefined)
                return widget.effectiveVisible ? "visible" : "hidden";
            return "unknown";
        }

        target: "widget"
    }

    IpcHandler {
        function reload(pluginId: string): string {
            if (!pluginId)
                return "ERROR: No plugin ID specified";

            if (!PluginService.availablePlugins[pluginId])
                return `PLUGIN_NOT_FOUND: ${pluginId}`;

            if (!PluginService.isPluginLoaded(pluginId)) {
                const success = PluginService.enablePlugin(pluginId);
                return success ? `PLUGIN_RELOAD_SUCCESS: ${pluginId}` : `PLUGIN_RELOAD_FAILED: ${pluginId}`;
            }

            const success = PluginService.reloadPlugin(pluginId);
            return success ? `PLUGIN_RELOAD_SUCCESS: ${pluginId}` : `PLUGIN_RELOAD_FAILED: ${pluginId}`;
        }

        function enable(pluginId: string): string {
            if (!pluginId)
                return "ERROR: No plugin ID specified";

            if (!PluginService.availablePlugins[pluginId])
                return `PLUGIN_NOT_FOUND: ${pluginId}`;

            const success = PluginService.enablePlugin(pluginId);
            return success ? `PLUGIN_ENABLE_SUCCESS: ${pluginId}` : `PLUGIN_ENABLE_FAILED: ${pluginId}`;
        }

        function disable(pluginId: string): string {
            if (!pluginId)
                return "ERROR: No plugin ID specified";

            if (!PluginService.availablePlugins[pluginId])
                return `PLUGIN_NOT_FOUND: ${pluginId}`;

            const success = PluginService.disablePlugin(pluginId);
            return success ? `PLUGIN_DISABLE_SUCCESS: ${pluginId}` : `PLUGIN_DISABLE_FAILED: ${pluginId}`;
        }

        function toggle(pluginId: string): string {
            if (!pluginId)
                return "ERROR: No plugin ID specified";

            if (!PluginService.availablePlugins[pluginId])
                return `PLUGIN_NOT_FOUND: ${pluginId}`;

            const success = PluginService.togglePlugin(pluginId);
            return success ? `PLUGIN_TOGGLE_SUCCESS: ${pluginId}` : `PLUGIN_TOGGLE_FAILED: ${pluginId}`;
        }

        function list(): string {
            const plugins = PluginService.getAvailablePlugins();
            if (plugins.length === 0)
                return "No plugins available";
            return plugins.map(p => `${p.id} [${p.loaded ? "loaded" : "disabled"}]`).join("\n");
        }

        function status(pluginId: string): string {
            if (!pluginId)
                return "ERROR: No plugin ID specified";

            if (!PluginService.availablePlugins[pluginId])
                return `PLUGIN_NOT_FOUND: ${pluginId}`;

            return PluginService.isPluginLoaded(pluginId) ? "loaded" : "disabled";
        }

        target: "plugins"
    }

    IpcHandler {
        function toggle(): string {
            if (PopoutService.systemUpdatePopout?.shouldBeVisible) {
                PopoutService.systemUpdatePopout.close();
                return "SYSTEMUPDATER_TOGGLE_SUCCESS";
            }
            const bar = root.getPreferredBar("systemUpdateButtonRef");
            if (bar) {
                bar.triggerSystemUpdate();
                return "SYSTEMUPDATER_TOGGLE_SUCCESS";
            }
            return "SYSTEMUPDATER_TOGGLE_FAILED";
        }

        function open(): string {
            if (PopoutService.systemUpdatePopout?.shouldBeVisible)
                return "SYSTEMUPDATER_ALREADY_OPEN";
            const bar = root.getPreferredBar("systemUpdateButtonRef");
            if (bar) {
                bar.triggerSystemUpdate();
                return "SYSTEMUPDATER_OPEN_SUCCESS";
            }
            return "SYSTEMUPDATER_OPEN_FAILED";
        }

        function close(): string {
            PopoutService.closeSystemUpdate();
            return "SYSTEMUPDATER_CLOSE_SUCCESS";
        }

        function updatestatus(): string {
            if (SystemUpdateService.isChecking) {
                return "ERROR: already checking";
            }
            if (SystemUpdateService.backends.length === 0) {
                return "ERROR: no package manager available";
            }
            SystemUpdateService.checkForUpdates();
            return "SUCCESS: Now checking...";
        }

        target: "systemupdater"
    }

    IpcHandler {
        function open(): string {
            if (!PopoutService.clipboardHistoryModal) {
                return "CLIPBOARD_NOT_AVAILABLE";
            }
            PopoutService.openClipboardHistory();
            return "CLIPBOARD_OPEN_SUCCESS";
        }

        function close(): string {
            if (!PopoutService.clipboardHistoryModal) {
                return "CLIPBOARD_NOT_AVAILABLE";
            }
            PopoutService.closeClipboardHistory();
            return "CLIPBOARD_CLOSE_SUCCESS";
        }

        function toggle(): string {
            if (!PopoutService.clipboardHistoryModal) {
                return "CLIPBOARD_NOT_AVAILABLE";
            }
            PopoutService.toggleClipboardHistory();
            return "CLIPBOARD_TOGGLE_SUCCESS";
        }

        target: "clipboard"
    }

    // ! spotlight and launcher should be synonymous for backwards compat
    IpcHandler {
        function open(): string {
            PopoutService.openDankLauncherV2();
            return "LAUNCHER_OPEN_SUCCESS";
        }

        function close(): string {
            PopoutService.closeDankLauncherV2();
            return "LAUNCHER_CLOSE_SUCCESS";
        }

        function toggle(): string {
            PopoutService.toggleDankLauncherV2();
            return "LAUNCHER_TOGGLE_SUCCESS";
        }

        function openWith(mode: string): string {
            if (!mode)
                return "LAUNCHER_OPEN_FAILED: No mode specified";
            PopoutService.openDankLauncherV2WithMode(mode);
            return `LAUNCHER_OPEN_SUCCESS: ${mode}`;
        }

        function toggleWith(mode: string): string {
            if (!mode)
                return "LAUNCHER_TOGGLE_FAILED: No mode specified";
            PopoutService.toggleDankLauncherV2WithMode(mode);
            return `LAUNCHER_TOGGLE_SUCCESS: ${mode}`;
        }

        function openQuery(query: string): string {
            PopoutService.openDankLauncherV2WithQuery(query);
            return "LAUNCHER_OPEN_QUERY_SUCCESS";
        }

        function toggleQuery(query: string): string {
            PopoutService.toggleDankLauncherV2WithQuery(query);
            return "LAUNCHER_TOGGLE_QUERY_SUCCESS";
        }

        target: "launcher"
    }

    // ! spotlight and launcher should be synonymous for backwards compat
    IpcHandler {
        function open(): string {
            PopoutService.openDankLauncherV2();
            return "SPOTLIGHT_OPEN_SUCCESS";
        }

        function close(): string {
            PopoutService.closeDankLauncherV2();
            return "SPOTLIGHT_CLOSE_SUCCESS";
        }

        function toggle(): string {
            PopoutService.toggleDankLauncherV2();
            return "SPOTLIGHT_TOGGLE_SUCCESS";
        }

        function openWith(mode: string): string {
            if (!mode)
                return "SPOTLIGHT_OPEN_FAILED: No mode specified";
            PopoutService.openDankLauncherV2WithMode(mode);
            return `SPOTLIGHT_OPEN_SUCCESS: ${mode}`;
        }

        function toggleWith(mode: string): string {
            if (!mode)
                return "SPOTLIGHT_TOGGLE_FAILED: No mode specified";
            PopoutService.toggleDankLauncherV2WithMode(mode);
            return `SPOTLIGHT_TOGGLE_SUCCESS: ${mode}`;
        }

        function openQuery(query: string): string {
            PopoutService.openDankLauncherV2WithQuery(query);
            return "SPOTLIGHT_OPEN_QUERY_SUCCESS";
        }

        function toggleQuery(query: string): string {
            PopoutService.toggleDankLauncherV2WithQuery(query);
            return "SPOTLIGHT_TOGGLE_QUERY_SUCCESS";
        }

        target: "spotlight"
    }

    IpcHandler {
        function open(): string {
            PopoutService.openSpotlightBar();
            return "SPOTLIGHT_BAR_OPEN_SUCCESS";
        }

        function close(): string {
            PopoutService.closeSpotlightBar();
            return "SPOTLIGHT_BAR_CLOSE_SUCCESS";
        }

        function toggle(): string {
            PopoutService.toggleSpotlightBar();
            return "SPOTLIGHT_BAR_TOGGLE_SUCCESS";
        }

        function openWith(mode: string): string {
            if (!mode)
                return "SPOTLIGHT_BAR_OPEN_FAILED: No mode specified";
            PopoutService.openSpotlightBarWithMode(mode);
            return `SPOTLIGHT_BAR_OPEN_SUCCESS: ${mode}`;
        }

        function toggleWith(mode: string): string {
            if (!mode)
                return "SPOTLIGHT_BAR_TOGGLE_FAILED: No mode specified";
            PopoutService.toggleSpotlightBarWithMode(mode);
            return `SPOTLIGHT_BAR_TOGGLE_SUCCESS: ${mode}`;
        }

        function openQuery(query: string): string {
            PopoutService.openSpotlightBarWithQuery(query);
            return "SPOTLIGHT_BAR_OPEN_QUERY_SUCCESS";
        }

        function toggleQuery(query: string): string {
            PopoutService.toggleSpotlightBarWithQuery(query);
            return "SPOTLIGHT_BAR_TOGGLE_QUERY_SUCCESS";
        }

        target: "spotlight-bar"
    }

    IpcHandler {
        function info(message: string): string {
            if (!message)
                return "ERROR: No message specified";

            ToastService.showInfo(message);
            return "TOAST_INFO_SUCCESS";
        }

        function infoWith(message: string, details: string, command: string, category: string): string {
            if (!message)
                return "ERROR: No message specified";

            ToastService.showInfo(message, details, command, category);
            return "TOAST_INFO_SUCCESS";
        }

        function warn(message: string): string {
            if (!message)
                return "ERROR: No message specified";

            ToastService.showWarning(message);
            return "TOAST_WARN_SUCCESS";
        }

        function warnWith(message: string, details: string, command: string, category: string): string {
            if (!message)
                return "ERROR: No message specified";

            ToastService.showWarning(message, details, command, category);
            return "TOAST_WARN_SUCCESS";
        }

        function error(message: string): string {
            if (!message)
                return "ERROR: No message specified";

            ToastService.showError(message);
            return "TOAST_ERROR_SUCCESS";
        }

        function errorWith(message: string, details: string, command: string, category: string): string {
            if (!message)
                return "ERROR: No message specified";

            ToastService.showError(message, details, command, category);
            return "TOAST_ERROR_SUCCESS";
        }

        function hide(): string {
            ToastService.hideToast();
            return "TOAST_HIDE_SUCCESS";
        }

        function dismiss(category: string): string {
            if (!category)
                return "ERROR: No category specified";

            ToastService.dismissCategory(category);
            return "TOAST_DISMISS_SUCCESS";
        }

        function status(): string {
            if (!ToastService.toastVisible)
                return "hidden";

            const levels = ["info", "warn", "error"];
            return `visible:${levels[ToastService.currentLevel]}:${ToastService.currentMessage}`;
        }

        target: "toast"
    }

    IpcHandler {
        function open(): string {
            FirstLaunchService.showWelcome();
            return "WELCOME_OPEN_SUCCESS";
        }

        function doctor(): string {
            FirstLaunchService.showDoctor();
            return "WELCOME_DOCTOR_SUCCESS";
        }

        function page(pageNum: string): string {
            const num = parseInt(pageNum) || 0;
            FirstLaunchService.showGreeter(num);
            return `WELCOME_PAGE_SUCCESS: ${num}`;
        }

        target: "welcome"
    }

    IpcHandler {
        function toggleOverlay(instanceId: string): string {
            if (!instanceId)
                return "ERROR: No instance ID specified";

            const instance = SettingsData.getDesktopWidgetInstance(instanceId);
            if (!instance)
                return `DESKTOP_WIDGET_NOT_FOUND: ${instanceId}`;

            const currentValue = instance.config?.showOnOverlay ?? false;
            SettingsData.updateDesktopWidgetInstanceConfig(instanceId, {
                showOnOverlay: !currentValue
            });
            return !currentValue ? `DESKTOP_WIDGET_OVERLAY_ENABLED: ${instanceId}` : `DESKTOP_WIDGET_OVERLAY_DISABLED: ${instanceId}`;
        }

        function setOverlay(instanceId: string, enabled: string): string {
            if (!instanceId)
                return "ERROR: No instance ID specified";

            const instance = SettingsData.getDesktopWidgetInstance(instanceId);
            if (!instance)
                return `DESKTOP_WIDGET_NOT_FOUND: ${instanceId}`;

            const enabledBool = enabled === "true" || enabled === "1";
            SettingsData.updateDesktopWidgetInstanceConfig(instanceId, {
                showOnOverlay: enabledBool
            });
            return enabledBool ? `DESKTOP_WIDGET_OVERLAY_ENABLED: ${instanceId}` : `DESKTOP_WIDGET_OVERLAY_DISABLED: ${instanceId}`;
        }

        function list(): string {
            const instances = SettingsData.desktopWidgetInstances || [];
            if (instances.length === 0)
                return "No desktop widgets configured";
            return instances.map(i => `${i.id} [${i.widgetType}] ${i.name || i.widgetType} ${i.enabled ? "[enabled]" : "[disabled]"}`).join("\n");
        }

        function status(instanceId: string): string {
            if (!instanceId)
                return "ERROR: No instance ID specified";

            const instance = SettingsData.getDesktopWidgetInstance(instanceId);
            if (!instance)
                return `DESKTOP_WIDGET_NOT_FOUND: ${instanceId}`;

            const enabled = instance.enabled ?? true;
            const overlay = instance.config?.showOnOverlay ?? false;
            const overview = instance.config?.showOnOverview ?? false;
            const clickThrough = instance.config?.clickThrough ?? false;
            const syncPosition = instance.config?.syncPositionAcrossScreens ?? false;
            return `enabled: ${enabled}, overlay: ${overlay}, overview: ${overview}, clickThrough: ${clickThrough}, syncPosition: ${syncPosition}`;
        }

        function enable(instanceId: string): string {
            if (!instanceId)
                return "ERROR: No instance ID specified";

            const instance = SettingsData.getDesktopWidgetInstance(instanceId);
            if (!instance)
                return `DESKTOP_WIDGET_NOT_FOUND: ${instanceId}`;

            SettingsData.updateDesktopWidgetInstance(instanceId, {
                enabled: true
            });
            return `DESKTOP_WIDGET_ENABLED: ${instanceId}`;
        }

        function disable(instanceId: string): string {
            if (!instanceId)
                return "ERROR: No instance ID specified";

            const instance = SettingsData.getDesktopWidgetInstance(instanceId);
            if (!instance)
                return `DESKTOP_WIDGET_NOT_FOUND: ${instanceId}`;

            SettingsData.updateDesktopWidgetInstance(instanceId, {
                enabled: false
            });
            return `DESKTOP_WIDGET_DISABLED: ${instanceId}`;
        }

        function toggleEnabled(instanceId: string): string {
            if (!instanceId)
                return "ERROR: No instance ID specified";

            const instance = SettingsData.getDesktopWidgetInstance(instanceId);
            if (!instance)
                return `DESKTOP_WIDGET_NOT_FOUND: ${instanceId}`;

            const currentValue = instance.enabled ?? true;
            SettingsData.updateDesktopWidgetInstance(instanceId, {
                enabled: !currentValue
            });
            return !currentValue ? `DESKTOP_WIDGET_ENABLED: ${instanceId}` : `DESKTOP_WIDGET_DISABLED: ${instanceId}`;
        }

        function toggleClickThrough(instanceId: string): string {
            if (!instanceId)
                return "ERROR: No instance ID specified";

            const instance = SettingsData.getDesktopWidgetInstance(instanceId);
            if (!instance)
                return `DESKTOP_WIDGET_NOT_FOUND: ${instanceId}`;

            const currentValue = instance.config?.clickThrough ?? false;
            SettingsData.updateDesktopWidgetInstanceConfig(instanceId, {
                clickThrough: !currentValue
            });
            return !currentValue ? `DESKTOP_WIDGET_CLICK_THROUGH_ENABLED: ${instanceId}` : `DESKTOP_WIDGET_CLICK_THROUGH_DISABLED: ${instanceId}`;
        }

        function setClickThrough(instanceId: string, enabled: string): string {
            if (!instanceId)
                return "ERROR: No instance ID specified";

            const instance = SettingsData.getDesktopWidgetInstance(instanceId);
            if (!instance)
                return `DESKTOP_WIDGET_NOT_FOUND: ${instanceId}`;

            const enabledBool = enabled === "true" || enabled === "1";
            SettingsData.updateDesktopWidgetInstanceConfig(instanceId, {
                clickThrough: enabledBool
            });
            return enabledBool ? `DESKTOP_WIDGET_CLICK_THROUGH_ENABLED: ${instanceId}` : `DESKTOP_WIDGET_CLICK_THROUGH_DISABLED: ${instanceId}`;
        }

        function toggleSyncPosition(instanceId: string): string {
            if (!instanceId)
                return "ERROR: No instance ID specified";

            const instance = SettingsData.getDesktopWidgetInstance(instanceId);
            if (!instance)
                return `DESKTOP_WIDGET_NOT_FOUND: ${instanceId}`;

            const currentValue = instance.config?.syncPositionAcrossScreens ?? false;
            SettingsData.updateDesktopWidgetInstanceConfig(instanceId, {
                syncPositionAcrossScreens: !currentValue
            });
            return !currentValue ? `DESKTOP_WIDGET_SYNC_POSITION_ENABLED: ${instanceId}` : `DESKTOP_WIDGET_SYNC_POSITION_DISABLED: ${instanceId}`;
        }

        function setSyncPosition(instanceId: string, enabled: string): string {
            if (!instanceId)
                return "ERROR: No instance ID specified";

            const instance = SettingsData.getDesktopWidgetInstance(instanceId);
            if (!instance)
                return `DESKTOP_WIDGET_NOT_FOUND: ${instanceId}`;

            const enabledBool = enabled === "true" || enabled === "1";
            SettingsData.updateDesktopWidgetInstanceConfig(instanceId, {
                syncPositionAcrossScreens: enabledBool
            });
            return enabledBool ? `DESKTOP_WIDGET_SYNC_POSITION_ENABLED: ${instanceId}` : `DESKTOP_WIDGET_SYNC_POSITION_DISABLED: ${instanceId}`;
        }

        function edit(): string {
            DesktopWidgetRegistry.editing = true;
            return "DESKTOP_WIDGET_EDITOR_OPENED";
        }

        target: "desktopWidget"
    }

    IpcHandler {
        function open(): string {
            root.workspaceRenameModalLoaderRef.active = true;
            if (root.workspaceRenameModalLoaderRef.item) {
                if (CompositorService.isAqueous)
                    return root.workspaceRenameModalLoaderRef.item.show("") ? "WORKSPACE_RENAME_MODAL_OPENED" : "WORKSPACE_RENAME_UNAVAILABLE";
                root.workspaceRenameModalLoaderRef.item.show(root.workspaceRenameModalLoaderRef.item.focusedWorkspaceName());
                return "WORKSPACE_RENAME_MODAL_OPENED";
            }
            return "WORKSPACE_RENAME_MODAL_NOT_FOUND";
        }

        function close(): string {
            if (root.workspaceRenameModalLoaderRef.item) {
                root.workspaceRenameModalLoaderRef.item.hide();
                return "WORKSPACE_RENAME_MODAL_CLOSED";
            }
            return "WORKSPACE_RENAME_MODAL_NOT_FOUND";
        }

        function toggle(): string {
            root.workspaceRenameModalLoaderRef.active = true;
            if (root.workspaceRenameModalLoaderRef.item) {
                if (root.workspaceRenameModalLoaderRef.item.visible) {
                    root.workspaceRenameModalLoaderRef.item.hide();
                    return "WORKSPACE_RENAME_MODAL_CLOSED";
                }
                if (CompositorService.isAqueous)
                    return root.workspaceRenameModalLoaderRef.item.show("") ? "WORKSPACE_RENAME_MODAL_OPENED" : "WORKSPACE_RENAME_UNAVAILABLE";
                root.workspaceRenameModalLoaderRef.item.show(root.workspaceRenameModalLoaderRef.item.focusedWorkspaceName());
                return "WORKSPACE_RENAME_MODAL_OPENED";
            }
            return "WORKSPACE_RENAME_MODAL_NOT_FOUND";
        }

        target: "workspace-rename"
    }

    IpcHandler {
        function toggle(name: string): string {
            if (!CompositorService.isHyprland)
                return "SCRATCHPAD_UNSUPPORTED_COMPOSITOR";
            CompositorService.toggleSpecialWorkspace(name);
            return "SCRATCHPAD_TOGGLED";
        }

        function move(name: string): string {
            if (!CompositorService.isHyprland)
                return "SCRATCHPAD_UNSUPPORTED_COMPOSITOR";
            const active = ToplevelManager.activeToplevel;
            if (!active)
                return "SCRATCHPAD_NO_FOCUSED_WINDOW";
            CompositorService.moveWindowToSpecial(active, name || "special");
            return "SCRATCHPAD_MOVED";
        }

        function restore(): string {
            if (!CompositorService.isHyprland)
                return "SCRATCHPAD_UNSUPPORTED_COMPOSITOR";
            const active = ToplevelManager.activeToplevel;
            if (!active)
                return "SCRATCHPAD_NO_FOCUSED_WINDOW";
            if (!CompositorService.windowScratchpadName(active))
                return "SCRATCHPAD_WINDOW_NOT_IN_SCRATCHPAD";
            CompositorService.moveWindowOutOfSpecial(active);
            return "SCRATCHPAD_RESTORED";
        }

        target: "scratchpad"
    }

    IpcHandler {
        function getFocusedWindow() {
            const active = ToplevelManager.activeToplevel;
            if (!active)
                return null;
            return {
                appId: active.appId || "",
                title: active.title || ""
            };
        }

        function open(): string {
            if (!CompositorService.isNiri && !CompositorService.isHyprland && !CompositorService.isMango)
                return "WINDOW_RULES_UNSUPPORTED_COMPOSITOR";
            root.windowRuleModalLoaderRef.active = true;
            if (root.windowRuleModalLoaderRef.item) {
                root.windowRuleModalLoaderRef.item.show(getFocusedWindow());
                return "WINDOW_RULE_MODAL_OPENED";
            }
            return "WINDOW_RULE_MODAL_NOT_FOUND";
        }

        function close(): string {
            if (root.windowRuleModalLoaderRef.item) {
                root.windowRuleModalLoaderRef.item.hide();
                return "WINDOW_RULE_MODAL_CLOSED";
            }
            return "WINDOW_RULE_MODAL_NOT_FOUND";
        }

        function toggle(): string {
            if (!CompositorService.isNiri && !CompositorService.isHyprland && !CompositorService.isMango)
                return "WINDOW_RULES_UNSUPPORTED_COMPOSITOR";
            root.windowRuleModalLoaderRef.active = true;
            if (root.windowRuleModalLoaderRef.item) {
                if (root.windowRuleModalLoaderRef.item.visible) {
                    root.windowRuleModalLoaderRef.item.hide();
                    return "WINDOW_RULE_MODAL_CLOSED";
                }
                root.windowRuleModalLoaderRef.item.show(getFocusedWindow());
                return "WINDOW_RULE_MODAL_OPENED";
            }
            return "WINDOW_RULE_MODAL_NOT_FOUND";
        }

        target: "window-rules"
    }

    IpcHandler {
        function cycle(): string {
            return NiriService.cycleSingleOutput();
        }

        function listProfiles(): string {
            const profiles = DisplayConfigState.validatedProfiles;
            const activeId = SessionData.getActiveDisplayProfile(CompositorService.compositor);
            const matchedId = DisplayConfigState.matchedProfile;
            const lines = [];

            for (const id in profiles) {
                const p = profiles[id];
                if (!p.name)
                    continue;
                const flags = [];
                if (id === activeId)
                    flags.push("active");
                if (id === matchedId)
                    flags.push("matched");
                const flagStr = flags.length > 0 ? " [" + flags.join(",") + "]" : "";
                lines.push(p.name + flagStr + " -> " + JSON.stringify(Object.keys(p.outputs)));
            }

            if (lines.length === 0)
                return "No profiles configured";
            return lines.join("\n");
        }

        function setProfile(profileName: string): string {
            if (!profileName)
                return "ERROR: No profile name specified";

            if (SettingsData.displayProfileAutoSelect)
                return "ERROR: Auto profile selection is enabled. Use toggleAuto first";

            const profiles = DisplayConfigState.validatedProfiles;
            let profileId = null;

            for (const id in profiles) {
                if (profiles[id].name === profileName) {
                    profileId = id;
                    break;
                }
            }

            if (!profileId)
                return `ERROR: Profile not found: ${profileName}`;

            DisplayConfigState.activateProfile(profileId);
            return `PROFILE_SET_SUCCESS: ${profileName}`;
        }

        function cycleProfile(): string {
            if (SettingsData.displayProfileAutoSelect)
                return "ERROR: Auto profile selection is enabled. Use toggleAuto first";

            const profiles = DisplayConfigState.validatedProfiles;
            const ids = Object.keys(profiles).filter(id => profiles[id].name);
            if (ids.length === 0)
                return "ERROR: No profiles configured";

            const activeId = SessionData.getActiveDisplayProfile(CompositorService.compositor);
            const idx = ids.indexOf(activeId);
            const nextId = ids[(idx + 1) % ids.length];
            DisplayConfigState.activateProfile(nextId);
            return `PROFILE_SET_SUCCESS: ${profiles[nextId].name}`;
        }

        function toggleAuto(): string {
            SettingsData.displayProfileAutoSelect = !SettingsData.displayProfileAutoSelect;
            SettingsData.saveSettings();
            if (SettingsData.displayProfileAutoSelect)
                DisplayConfigState.applyAutoConfig();
            return `Auto profile selection: ${SettingsData.displayProfileAutoSelect ? "enabled" : "disabled"}`;
        }

        function status(): string {
            const auto = SettingsData.displayProfileAutoSelect ? "on" : "off";
            const activeId = SessionData.getActiveDisplayProfile(CompositorService.compositor);
            const matchedId = DisplayConfigState.matchedProfile;
            const profiles = DisplayConfigState.validatedProfiles;
            const activeName = profiles[activeId]?.name || "none";
            const matchedName = profiles[matchedId]?.name || "none";
            const currentOutputs = JSON.stringify(DisplayConfigState.currentOutputSet);

            return `auto: ${auto}\nactive: ${activeName}\nmatched: ${matchedName}\noutputs: ${currentOutputs}`;
        }

        function current(): string {
            return JSON.stringify(DisplayConfigState.currentOutputSet);
        }

        function refresh(): string {
            DisplayConfigState.currentOutputSet = DisplayConfigState.buildCurrentOutputSet();
            DisplayConfigState.validateProfiles();
            return "Refreshed output state";
        }

        target: "outputs"
    }

    IpcHandler {
        target: "mic"

        function setvolume(percentage: string): string {
            return AudioService.setMicVolume(parseInt(percentage));
        }

        function increment(step: string): string {
            return AudioService.incrementMicVolume(step);
        }

        function decrement(step: string): string {
            return AudioService.decrementMicVolume(step);
        }

        function mute(): string {
            return AudioService.toggleMicMute();
        }

        function status(): string {
            if (!AudioService.source || !AudioService.source.audio) {
                return "No audio source available";
            }

            const volume = Math.round(AudioService.source.audio.volume * 100);
            const muteStatus = AudioService.source.audio.muted ? " (muted)" : "";
            return `Microphone: ${volume}%${muteStatus}`;
        }
    }

    IpcHandler {
        function list(): string {
            const items = SystemTray.items.values;
            if (items.length === 0)
                return "No tray items available";

            return items.map(item => {
                const id = item?.id || "";
                const title = item?.tooltipTitle || "";
                const fullKey = title ? `${id}::${title}` : id;
                const hasMenu = item?.hasMenu ? " [menu]" : "";
                return fullKey + hasMenu;
            }).join("\n");
        }

        function activate(itemId: string): string {
            const item = TrayMenuManager.findTrayItem(itemId);
            if (!item)
                return `ERROR: Tray item not found: ${itemId}`;

            item.activate();
            return `SUCCESS: Activated ${itemId}`;
        }

        function menu(itemId: string): string {
            const item = TrayMenuManager.findTrayItem(itemId);
            if (!item)
                return `ERROR: Tray item not found: ${itemId}`;

            if (!item.hasMenu)
                return `ERROR: Tray item has no menu: ${itemId}`;

            TrayMenuManager.requestOpenMenu(itemId, BarWidgetService.getFocusedScreenName());
            return `SUCCESS: Requested menu ${itemId}`;
        }

        function status(itemId: string): string {
            const item = TrayMenuManager.findTrayItem(itemId);
            if (!item)
                return `ERROR: Tray item not found: ${itemId}`;

            const id = item?.id || "";
            const title = item?.tooltipTitle || "";
            const hasMenu = item?.hasMenu || false;
            const onlyMenu = item?.onlyMenu || false;

            return `id: ${id}\ntitle: ${title}\nhasMenu: ${hasMenu}\nonlyMenu: ${onlyMenu}`;
        }

        target: "tray"
    }

    IpcHandler {
        function open(): string {
            if (!PowerProfileWatcher.available)
                return "ERROR: power-profiles-daemon not available";

            PopoutService.openPowerProfileModal();
            return "POWERPROFILE_OPEN_SUCCESS";
        }

        function close(): string {
            PopoutService.closePowerProfileModal();
            return "POWERPROFILE_CLOSE_SUCCESS";
        }

        function toggle(): string {
            if (!PowerProfileWatcher.available)
                return "ERROR: power-profiles-daemon not available";

            PopoutService.togglePowerProfileModal();
            return "POWERPROFILE_TOGGLE_SUCCESS";
        }

        function list(): string {
            if (!PowerProfileWatcher.available)
                return "ERROR: power-profiles-daemon not available";

            return PowerProfileWatcher.availableProfiles.map(profile => PowerProfileWatcher.profileSlug(profile)).join("\n");
        }

        function status(): string {
            if (!PowerProfileWatcher.available)
                return "ERROR: power-profiles-daemon not available";

            return PowerProfileWatcher.profileSlug(PowerProfiles.profile);
        }

        function set(profile: string): string {
            if (!PowerProfileWatcher.available)
                return "ERROR: power-profiles-daemon not available";

            if (!profile)
                return "ERROR: No profile specified";

            const parsed = PowerProfileWatcher.parseProfileSlug(profile);
            if (parsed === -1)
                return "ERROR: Unknown power profile. Supported options: power-saver, balanced, performance";

            if (parsed === PowerProfile.Performance && !PowerProfiles.hasPerformanceProfile)
                return "ERROR: Performance profile not supported by hardware";

            if (!PowerProfileWatcher.applyProfile(parsed))
                return "ERROR: Failed to set power profile";

            return "POWERPROFILE_SET_SUCCESS";
        }

        function cycle(): string {
            if (!PowerProfileWatcher.available)
                return "ERROR: power-profiles-daemon not available";

            if (!PowerProfileWatcher.cycleProfile())
                return "ERROR: Failed to set power profile";

            return "POWERPROFILE_CYCLE_SUCCESS";
        }

        target: "powerprofile"
    }
}
