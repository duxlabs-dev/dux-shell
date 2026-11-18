import QtQuick
import "../../../Common/QmlUtils.js" as QmlUtils

// Qt creates a component's whole tree in one uninterruptible step, so a long page is split into cards that each
// build as their own step once the page is on screen. Hide a card with `when`, not with the card's `visible`.
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

    onWantedChanged: {
        if (wanted)
            active = true;
    }

    width: parent?.width ?? 0
    visible: when
    active: false
    // A section opened by hand builds in place so its reveal animates over finished content
    asynchronous: section === null
    sourceComponent: content
}
