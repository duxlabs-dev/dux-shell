import QtQuick
import "../../Common/IslandKit.js" as Kit

// How a wing turns from a pill into a tile beside the open launcher (the "Tile transition" setting). This base is the plain
// morph; TileJelly, TileLiquid and TilePivot override its outputs, and may draw their own pieces as children (they fill the wing).
Item {
    id: tx

    // Inputs, bound by the wing.
    property Item wing
    property bool active: false
    property bool carded: false
    // The tile spring's raw value (overshoots past 1), its shape lead (capped at 1), and the tile share (0 when not carded).
    property real tile: 0
    property real tileShape: 0
    property real tileOf: 0
    property real restLength: 0
    property real pillThick: 0
    property real tileSide: 0
    property real tileThick: 0
    property real pillIconY: 0
    property real tileIconY: 0
    property bool gauged: false
    // The island's clock speed (DMS's animation speed): a variant's own springs run on it.
    property real pace: 1

    // Outputs, read by the wing.
    // Length and thickness while carded (the hover card still grows from these).
    property real length: Kit.mix(tx.restLength, tx.tileSide, tx.tileShape)
    property real thick: Kit.mix(tx.pillThick, tx.tileThick, tx.tileShape)
    property real iconY: Kit.mix(tx.pillIconY, tx.tileIconY, tx.tileOf)
    // Degrees the whole wing turns around the icon's center; the icon is turned back so it stays upright.
    property real turn: 0
    // False hides the stock bottom-up gauge, for a variant that draws its own liquid.
    property bool gaugeShown: true
    // False hides the wing's own body and flat gauge, for a variant that draws the whole bubble.
    property bool bodyShown: true
    // Icon shift along the wing, the value's opacity and the whole wing's (a variant's reduced-motion fade).
    property real iconDx: 0
    property real valueOpacity: 1
    property real fade: 1

    anchors.fill: parent
    visible: tx.active
}
