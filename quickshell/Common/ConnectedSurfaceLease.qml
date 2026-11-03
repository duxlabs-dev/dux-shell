pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: root

    required property string claimPrefix
    required property string slot
    required property var isCurrentOwner

    property bool exclusive: false
    property bool requirePresentedState: false
    property bool retractsDock: false

    property string screenName: ""
    property bool enabled: false
    property bool active: false
    property bool presented: false
    property bool dockBlocked: false
    property string dockSide: ""
    property bool renewTokenOnRecovery: true

    property string claimId: ""
    property string claimedScreenName: ""
    property string claimedSlot: ""
    property int _claimSerial: 0

    signal recoveryRequested

    visible: false

    function _nextClaimId() {
        _claimSerial += 1;
        return claimPrefix + ":" + (new Date()).getTime() + ":" + _claimSerial + ":" + Math.floor(Math.random() * 1000000);
    }

    function _isCurrent(name) {
        return !!name && !!isCurrentOwner(name);
    }

    function _hasOwner(name, ownerId) {
        return !!name && ConnectedModeState.hasSurfaceOwner(name, claimedSlot || slot, ownerId);
    }

    function _hasState(name, ownerId) {
        return !requirePresentedState || ConnectedModeState.hasSurfaceDescriptor(name, claimedSlot || slot, ownerId);
    }

    function _shouldRecover() {
        return active && enabled && _isCurrent(screenName);
    }

    function requestRecovery() {
        if (!_shouldRecover())
            return false;
        recoveryRequested();
        return true;
    }

    function checkRecovery() {
        if (!_shouldRecover())
            return false;
        if (claimedScreenName === screenName && _hasOwner(screenName, claimId) && _hasState(screenName, claimId))
            return false;
        recoveryRequested();
        return true;
    }

    function beginClaim() {
        if (claimId && retractsDock)
            ConnectedModeState.releaseDockRetract(claimId);
        claimId = _nextClaimId();
        claimedScreenName = "";
        return claimId;
    }

    function _syncDockRetract() {
        if (!claimId || !retractsDock)
            return;
        if (dockBlocked && presented && dockSide)
            ConnectedModeState.requestDockRetract(claimId, screenName, dockSide);
        else
            ConnectedModeState.releaseDockRetract(claimId);
    }

    function publish(state, forceClaim) {
        if (!enabled || !screenName || !state) {
            release();
            return false;
        }

        if ((claimedScreenName && claimedScreenName !== screenName) || (claimedSlot && claimedSlot !== slot))
            release();

        const current = _isCurrent(screenName);
        const claiming = !!forceClaim || !claimId;
        if (claiming && !current)
            return false;
        if (!claimId)
            beginClaim();

        let published = claiming ? ConnectedModeState.claimSurface(screenName, slot, state, claimId, exclusive) : ConnectedModeState.updateSurface(screenName, slot, state, claimId);
        if (!published && !claiming && current) {
            if (renewTokenOnRecovery)
                beginClaim();
            else if (retractsDock)
                ConnectedModeState.releaseDockRetract(claimId);
            published = ConnectedModeState.claimSurface(screenName, slot, state, claimId, exclusive);
        }
        if (!published)
            return false;

        claimedScreenName = screenName;
        claimedSlot = slot;
        _syncDockRetract();
        return true;
    }

    function _updateMotion(patch) {
        if (!enabled || !claimId || !claimedScreenName)
            return false;
        if (!_hasOwner(claimedScreenName, claimId)) {
            requestRecovery();
            return false;
        }
        return ConnectedModeState.setSurfaceMotion(claimedScreenName, claimedSlot || slot, claimId, patch);
    }

    function updateAnim(animX, animY) {
        return _updateMotion({
            "animX": animX,
            "animY": animY
        });
    }

    function updateBody(bodyX, bodyY, bodyW, bodyH) {
        return _updateMotion({
            "bodyX": bodyX,
            "bodyY": bodyY,
            "bodyW": bodyW,
            "bodyH": bodyH
        });
    }

    function release() {
        if (!claimId) {
            claimedScreenName = "";
            claimedSlot = "";
            return false;
        }

        const releasedClaimId = claimId;
        const releasedScreenName = claimedScreenName;
        const releasedSlot = claimedSlot || slot;
        claimId = "";
        claimedScreenName = "";
        claimedSlot = "";

        if (retractsDock)
            ConnectedModeState.releaseDockRetract(releasedClaimId);
        if (releasedScreenName)
            return ConnectedModeState.releaseSurface(releasedScreenName, releasedSlot, releasedClaimId);
        return false;
    }

    Component.onDestruction: release()
}
