pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets
import "../../../../Common/niri/keep.js" as Keep
import "../../../../Common/niri/registry.js" as Registry

// « Keep this change? »: risky edits of the section go through edit() and come back after 15 s unless kept.
// The mockup floats ONE banner at the top of the page: NiriShell owns it and it mirrors the active
// section's keeper, which keeps its state (and the revert on leave) and drops its own rendering.
Rectangle {
    id: root

    property var risky: []
    property var keepState: Keep.idle()
    // The page banner's keeper, and the page banner mirroring this keeper: at most one of the two is set.
    property var mirror: null
    property var banner: null
    // The instance whose state is shown and acted on: the mirrored keeper, or this one.
    readonly property var shown: mirror ?? root
    readonly property int secondsLeft: shown.keepState.left
    readonly property bool asking: secondsLeft > 0
    // A real-time 1 s tick, not an animation: Theme durations are fractions of the animation base.
    readonly property int oneSecondMs: 1000
    // Banner width of the validated mockup; clamped to the parent in the banner itself.
    readonly property real bannerWidth: 520
    // The mockup names the changed setting before the warning; titles come from the page's search index.
    readonly property string what: Object.keys(shown.keepState.pending).map(key => titleOf(key)).filter(title => title !== "").join(", ")

    function edit(key, value) {
        keepState = Keep.edit(keepState, risky, key, NiriPageService.get(key), value);
        NiriPageService.set(key, value);
        if (asking)
            (banner ?? root).focusKeep();
    }

    function keep() {
        shown.keepState = Keep.idle();
    }

    function revert() {
        const back = Keep.restores(shown.keepState.pending, key => NiriPageService.get(key), key => NiriPageService.defaultOf(key));
        keep();
        back.forEach(r => r.reset ? NiriPageService.reset(r.key) : NiriPageService.set(r.key, r.value));
    }

    function focusKeep() {
        keepButton.forceActiveFocus();
    }

    function attach(who) {
        mirror = who;
    }

    function detach(who) {
        if (mirror === who)
            mirror = null;
    }

    // NiriShell's banner, found through the page's parents; a keeper without one renders itself.
    // The parent chain is walked through a var parameter: the host property exists on no static type.
    function bannerHostOf(item) {
        if (item && "keepBannerHost" in item && item.keepBannerHost && item.keepBannerHost !== root)
            return item.keepBannerHost;
        return null;
    }

    function findBanner() {
        for (let item = root.parent; item; item = item.parent) {
            const host = bannerHostOf(item);
            if (host)
                return host;
        }
        return null;
    }

    function titleOf(key) {
        for (const section of Registry.sections) {
            const hit = section.search.find(entry => entry.key === key);
            if (hit)
                return I18n.tr(hit.title);
        }
        return "";
    }

    // Leaving the section or Expert mode must not leave an unconfirmed change behind.
    Component.onDestruction: {
        if (banner) {
            banner.detach(root);
            banner = null;
        }
        if (!mirror && asking)
            revert();
    }

    Component.onCompleted: {
        if (mirror)
            return;
        const host = findBanner();
        if (!host)
            return;
        banner = host;
        host.attach(root);
    }

    visible: asking && banner === null
    opacity: asking ? 1 : 0
    width: Math.min(bannerWidth, (parent ? parent.width : 0) - Theme.spacingL * 2)
    implicitHeight: keepColumn.implicitHeight + Theme.spacingL * 2
    radius: Theme.cornerRadiusL
    color: Theme.surfaceContainerHighest
    border.width: Theme.outlineWidthFocused
    border.color: Theme.warning
    z: 100
    Accessible.role: Accessible.AlertMessage
    Accessible.name: keepTitle.text

    Behavior on opacity {
        enabled: !SettingsData.reduceMotion
        NumberAnimation {
            duration: Theme.mediumDuration
            easing.type: Theme.standardEasing
        }
    }

    // The countdown runs on the keeper only: the page banner mirrors it
    Timer {
        interval: root.oneSecondMs
        repeat: true
        running: root.mirror === null && root.asking
        onTriggered: {
            if (root.secondsLeft > 1) {
                root.keepState = {
                    "pending": root.keepState.pending,
                    "left": root.secondsLeft - 1
                };
                return;
            }
            root.revert();
        }
    }

    Column {
        id: keepColumn

        x: Theme.spacingL
        y: Theme.spacingL
        width: parent.width - Theme.spacingL * 2
        spacing: Theme.spacingS

        Row {
            width: parent.width
            spacing: Theme.spacingS

            DIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: "timer"
                size: Theme.iconSizeMedium
                color: Theme.warning
            }

            StyledText {
                id: keepTitle
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - Theme.iconSizeMedium - Theme.spacingS
                wrapMode: Text.WordWrap
                text: I18n.tr("Keep this change?", "niri page advanced, confirm a risky change")
                font.pixelSize: Theme.fontSizeLarge
                font.weight: Theme.fontWeightBold
                color: Theme.surfaceText
            }
        }

        StyledText {
            width: parent.width
            wrapMode: Text.WordWrap
            text: (root.what !== "" ? root.what + ". " : "") + I18n.tr("If you cannot see or type, wait.", "niri page advanced, a risky change reverts on its own")
            color: Theme.surfaceVariantText
        }

        Row {
            spacing: Theme.spacingS

            StyledText {
                anchors.baseline: secondsText.baseline
                text: root.secondsLeft
                font.pixelSize: Theme.fontSizeXLarge
                font.weight: Theme.fontWeightBold
                font.features: ({
                        "tnum": 1
                    })
                color: Theme.warning
            }

            StyledText {
                id: secondsText
                text: I18n.tr("s, then it reverts", "niri page advanced, after the seconds left before a risky change goes back")
                color: Theme.surfaceVariantText
            }
        }

        Flow {
            width: parent.width
            spacing: Theme.spacingS

            DButton {
                id: keepButton
                text: I18n.tr("Keep")
                backgroundColor: Theme.primary
                textColor: Theme.onPrimary
                onClicked: root.keep()
            }

            DButton {
                text: I18n.tr("Revert now", "niri page advanced, undo a risky change at once")
                onClicked: root.revert()
            }
        }
    }
}
