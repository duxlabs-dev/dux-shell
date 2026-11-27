import QtQuick
import Quickshell

QtObject {
    required property Singleton service
    property var modules: null
    property bool active: true

    property bool _held: false
    property bool _alive: true
    // What was actually added, so release matches it even after `modules` changes.
    property var _heldModules: null

    function _add(list) {
        if (typeof service.addRef !== "function")
            service.refCount++;
        else
            service.addRef(list ?? []);
    }

    function _remove(list) {
        if (typeof service.addRef !== "function")
            service.refCount--;
        else
            service.removeRef(list ?? []);
    }

    function sync(wanted) {
        if (wanted === _held)
            return;
        _held = wanted;
        if (wanted) {
            _heldModules = modules;
            _add(_heldModules);
            return;
        }
        _remove(_heldModules);
        _heldModules = null;
    }

    // Add before remove so modules in both lists never drop to zero refs.
    function _swap() {
        if (!_held || JSON.stringify(modules) === JSON.stringify(_heldModules))
            return;
        const old = _heldModules;
        _heldModules = modules;
        _add(_heldModules);
        _remove(old);
    }
    function _syncActive() {
        if (_alive)
            sync(active);
    }

    // Deferred: adding or releasing changes service data, which the bindings driving `modules` and `active` may read.
    onModulesChanged: Qt.callLater(_swap)
    onActiveChanged: Qt.callLater(_syncActive)
    Component.onCompleted: sync(active)
    Component.onDestruction: {
        _alive = false;
        sync(false);
    }
}
