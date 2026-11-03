import QtQuick
import qs.Services

QtObject {
    id: root

    property bool active: true
    property bool held: false

    onActiveChanged: sync()
    Component.onCompleted: sync()
    Component.onDestruction: {
        if (held)
            LyricsService.removeRef();
    }

    function sync() {
        if (active === held)
            return;
        held = active;
        if (active) {
            LyricsService.addRef();
            return;
        }
        LyricsService.removeRef();
    }
}
