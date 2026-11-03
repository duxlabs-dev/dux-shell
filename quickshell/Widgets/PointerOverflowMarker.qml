import QtQuick

// Qt 6.11 caches at first hover that an item's pointer children fit inside it, then drops delivery outside it for good.
// A disabled MouseArea already off the parent still counts, receives nothing, and keeps that cache open at zero cost.
MouseArea {
    x: -1
    y: -1
    width: 1
    height: 1
    enabled: false
}
