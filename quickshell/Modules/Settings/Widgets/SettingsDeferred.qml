import QtQuick
import "../../../Common/QmlUtils.js" as QmlUtils

// Qt creates a component's whole tree in one uninterruptible step, so a long page is split into cards: SettingsPage
// builds its first screen, the rest build once the page is on screen. Hide a card with `when`, not `visible`.
Loader {
    id: root

    default property Component content
    property bool when: true
    readonly property Item pageHost: {
        for (let p = parent; p; p = p.parent) {
            if (p.pageSettled !== undefined)
                return p;
        }
        return null;
    }
    readonly property Item section: QmlUtils.findParentCollapsible(parent)
    // Not `visible`: that is false inside a collapsed section, which is exactly when a search has to build this
    readonly property bool wanted: when && (pageHost?.pageSettled ?? true) && (section?.contentWanted ?? true)

    readonly property Item page: {
        for (let p = parent; p; p = p.parent) {
            if (p.firstScreenBuilt !== undefined)
                return p;
        }
        return null;
    }

    onWantedChanged: {
        if (!wanted)
            return;
        if (section === null && page) {
            page.buildLater(root);
            return;
        }
        active = true;
    }
    onWhenChanged: {
        if (when)
            page?.buildFirstScreen();
    }
    onLoaded: page?.cardBuilt()

    function buildNow() {
        if (active)
            return;
        asynchronous = false;
        active = true;
    }

    width: parent?.width ?? 0
    visible: when
    active: false
    // A section opened by hand builds in place so its reveal animates over finished content
    asynchronous: section === null
    sourceComponent: content
}
