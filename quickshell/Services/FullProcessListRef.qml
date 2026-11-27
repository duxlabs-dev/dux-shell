import QtQuick

// Asks DgopService for every process instead of the top rows of its sort while active.
QtObject {
    property bool active: false

    property bool _held: false

    function sync(wanted) {
        if (wanted === _held)
            return;
        _held = wanted;
        if (wanted)
            DgopService.requestFullProcessList();
        else
            DgopService.releaseFullProcessList();
    }

    onActiveChanged: sync(active)
    Component.onCompleted: sync(active)
    Component.onDestruction: sync(false)
}
