import QtQuick

QtObject {
    property Item row: null
    property real translation: 0
    property bool detached: false

    function begin(item) {
        if (row)
            return;
        translation = 0;
        detached = false;
        row = item;
    }

    function drag(item, value) {
        if (row !== item)
            return;
        const distance = Math.abs(value);
        if (!detached && distance >= NotificationMetrics.swipeDetachDistance)
            detached = true;
        else if (detached && distance <= NotificationMetrics.swipeAttachDistance)
            detached = false;
        translation = value;
    }

    function end(item) {
        if (row !== item)
            return;
        row = null;
        detached = false;
        translation = 0;
    }
}
