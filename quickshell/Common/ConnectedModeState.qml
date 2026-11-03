pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "ConnectedSurfaceDescriptor.js" as SurfaceDescriptor

Singleton {
    id: root

    property var surfaceDescriptors: ({})
    property var surfaceMotion: ({})
    property var surfaceRevisions: ({})
    property var dockRetractRequests: ({})
    property var popoutMotionHandoff: null

    // One notifying object per claimed slot keeps animation frames from invalidating every descriptor binding.
    Component {
        id: motionComponent

        QtObject {
            property var frame: ({
                    "bodyX": 0,
                    "bodyY": 0,
                    "bodyW": 0,
                    "bodyH": 0,
                    "animX": 0,
                    "animY": 0
                })
        }
    }

    function surfaceSlot(kind, instanceId) {
        const slot = SurfaceDescriptor.slotForKind(kind);
        return instanceId ? slot + ":" + instanceId : slot;
    }

    function _motionKey(screenName, slot) {
        return screenName + "|" + slot;
    }

    function _stored(screenName, slot) {
        return screenName ? surfaceDescriptors[screenName]?.[slot] ?? null : null;
    }

    function surfaceDescriptor(screenName, slot) {
        const base = _stored(screenName, slot) ?? SurfaceDescriptor.empty(slot.split(":")[0], screenName);
        const motion = surfaceMotion[_motionKey(screenName, slot)];
        if (!motion)
            return base;
        return SurfaceDescriptor.normalize(motion.frame, base);
    }

    function surfaceDescriptorsOfKind(screenName, kind) {
        const screen = screenName ? surfaceDescriptors[screenName] : null;
        if (!screen)
            return [];
        return Object.keys(screen).filter(slot => slot === kind || slot.startsWith(kind + ":")).map(slot => surfaceDescriptor(screenName, slot));
    }

    function surfaceOwnerId(screenName, slot) {
        return _stored(screenName, slot)?.ownerId ?? "";
    }

    function hasSurfaceOwner(screenName, slot, ownerId) {
        return !!ownerId && surfaceOwnerId(screenName, slot) === ownerId;
    }

    function hasSurfaceDescriptor(screenName, slot, ownerId) {
        const descriptor = _stored(screenName, slot);
        return !!descriptor && descriptor.phase !== "hidden" && (!ownerId || descriptor.ownerId === ownerId);
    }

    function claimSurface(screenName, slot, state, ownerId, exclusive) {
        if (!screenName || !slot || !state || !ownerId)
            return false;
        if (exclusive) {
            for (const name of Object.keys(surfaceDescriptors)) {
                if (name !== screenName)
                    releaseSurface(name, slot, "");
            }
        }
        return _writeSurface(screenName, slot, state, ownerId);
    }

    function updateSurface(screenName, slot, state, ownerId) {
        if (!state || !hasSurfaceOwner(screenName, slot, ownerId))
            return false;
        return _writeSurface(screenName, slot, state, ownerId);
    }

    function _bumpSurfaceRevision(screenName) {
        surfaceRevisions = Object.assign({}, surfaceRevisions, {
            [screenName]: (surfaceRevisions[screenName] ?? 0) + 1
        });
    }

    function _writeSurface(screenName, slot, state, ownerId) {
        const stored = _stored(screenName, slot);
        const previous = surfaceDescriptor(screenName, slot);
        let next = SurfaceDescriptor.normalize(Object.assign({}, state, {
            "ownerId": ownerId,
            "screenName": screenName,
            "revision": previous.revision
        }), previous);
        if (SurfaceDescriptor.same(previous, next))
            return true;
        next = SurfaceDescriptor.withRevision(next, previous.revision + 1);
        const screen = Object.assign({}, surfaceDescriptors[screenName]);
        screen[slot] = next;
        surfaceDescriptors = Object.assign({}, surfaceDescriptors, {
            [screenName]: screen
        });
        if (!stored || stored.ownerId !== next.ownerId || stored.visible !== next.visible)
            _bumpSurfaceRevision(screenName);
        const key = _motionKey(screenName, slot);
        const motion = surfaceMotion[key] ?? motionComponent.createObject(root);
        motion.frame = {
            "bodyX": next.bodyRect.x,
            "bodyY": next.bodyRect.y,
            "bodyW": next.bodyRect.width,
            "bodyH": next.bodyRect.height,
            "animX": next.animationOffset.x,
            "animY": next.animationOffset.y
        };
        if (!surfaceMotion[key])
            surfaceMotion = Object.assign({}, surfaceMotion, {
                [key]: motion
            });
        return true;
    }

    function releaseSurface(screenName, slot, ownerId) {
        const current = _stored(screenName, slot);
        if (!current || (ownerId && current.ownerId !== ownerId))
            return false;
        const screen = Object.assign({}, surfaceDescriptors[screenName]);
        delete screen[slot];
        const next = Object.assign({}, surfaceDescriptors);
        if (Object.keys(screen).length)
            next[screenName] = screen;
        else
            delete next[screenName];
        surfaceDescriptors = next;
        _dropMotion([_motionKey(screenName, slot)]);
        _bumpSurfaceRevision(screenName);
        return true;
    }

    function setSurfaceMotion(screenName, slot, ownerId, patch) {
        if (!patch || !hasSurfaceOwner(screenName, slot, ownerId))
            return false;
        const motion = surfaceMotion[_motionKey(screenName, slot)];
        if (!motion)
            return false;
        let frame = null;
        for (const key in patch) {
            const value = Number(patch[key]);
            if (isNaN(value) || !(key in motion.frame) || motion.frame[key] === value)
                continue;
            frame = frame ?? Object.assign({}, motion.frame);
            frame[key] = value;
        }
        if (frame)
            motion.frame = frame;
        return true;
    }

    function _dropMotion(keys) {
        const dropped = keys.filter(key => surfaceMotion[key]);
        if (!dropped.length)
            return;
        const next = Object.assign({}, surfaceMotion);
        for (const key of dropped) {
            next[key].destroy();
            delete next[key];
        }
        surfaceMotion = next;
    }

    function savePopoutMotion(ownerId, screenName, barSide, rect, velocity) {
        if (!hasSurfaceOwner(screenName, "popout", ownerId))
            return;
        popoutMotionHandoff = {
            "ownerId": ownerId,
            "screen": screenName,
            "barSide": barSide,
            "rect": Qt.rect(rect.x, rect.y, rect.width, rect.height),
            "velocity": Qt.vector4d(velocity.x, velocity.y, velocity.z, velocity.w)
        };
    }

    function takePopoutMotion(screenName, barSide) {
        const handoff = popoutMotionHandoff;
        popoutMotionHandoff = null;
        if (!handoff || handoff.screen !== screenName || handoff.barSide !== barSide || !hasSurfaceOwner(screenName, "popout", handoff.ownerId))
            return null;
        return handoff;
    }

    function requestDockRetract(requesterId, screenName, side) {
        if (!requesterId || !screenName || !side)
            return false;
        const existing = dockRetractRequests[requesterId];
        if (existing && existing.screenName === screenName && existing.side === side)
            return true;
        dockRetractRequests = Object.assign({}, dockRetractRequests, {
            [requesterId]: {
                "screenName": screenName,
                "side": side
            }
        });
        return true;
    }

    function releaseDockRetract(requesterId) {
        if (!requesterId || !dockRetractRequests[requesterId])
            return false;
        const next = Object.assign({}, dockRetractRequests);
        delete next[requesterId];
        dockRetractRequests = next;
        return true;
    }

    function dockRetractActiveForSide(screenName, side) {
        if (!screenName || !side)
            return false;
        return Object.values(dockRetractRequests).some(request => request.screenName === screenName && request.side === side);
    }

    function _pruneKeyed(dict, keep) {
        const next = {};
        let changed = false;
        for (const key in dict) {
            if (keep(key, dict[key]))
                next[key] = dict[key];
            else
                changed = true;
        }
        return changed ? next : null;
    }

    function _pruneOrphanDocks() {
        if (typeof SettingsData === "undefined" || !SettingsData.dockConfigs)
            return;
        const validDockIds = new Set((SettingsData.dockConfigs || []).map(config => config?.id).filter(Boolean));
        for (const screenName of Object.keys(surfaceDescriptors)) {
            const screen = surfaceDescriptors[screenName];
            if (!screen)
                continue;
            for (const slot of Object.keys(screen)) {
                if (slot.startsWith("dock:")) {
                    const dockId = slot.substring(5);
                    if (!validDockIds.has(dockId))
                        releaseSurface(screenName, slot, "");
                } else if (slot === "dock" && !validDockIds.has("")) {
                    releaseSurface(screenName, slot, "");
                }
            }
        }
    }

    function _pruneToLiveScreens() {
        const live = new Set((Quickshell.screens || []).map(screen => screen?.name).filter(Boolean));
        const descriptors = _pruneKeyed(surfaceDescriptors, name => live.has(name));
        if (descriptors)
            surfaceDescriptors = descriptors;
        const revisions = _pruneKeyed(surfaceRevisions, name => live.has(name));
        if (revisions)
            surfaceRevisions = revisions;
        const retract = _pruneKeyed(dockRetractRequests, (_, request) => live.has(request.screenName));
        if (retract)
            dockRetractRequests = retract;
        _dropMotion(Object.keys(surfaceMotion).filter(key => !live.has(key.split("|")[0])));
        _pruneOrphanDocks();
    }

    Connections {
        target: Quickshell
        function onScreensChanged() {
            screenPruneAction.schedule();
        }
    }

    Connections {
        target: SettingsData
        function onDockConfigsChanged() {
            dockPruneAction.schedule();
        }
    }

    DeferredAction {
        id: screenPruneAction
        onTriggered: root._pruneToLiveScreens()
    }

    DeferredAction {
        id: dockPruneAction
        onTriggered: root._pruneOrphanDocks()
    }
}
