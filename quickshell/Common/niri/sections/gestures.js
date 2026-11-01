.pragma library

// niri defaults: niri-config/src/gestures.rs (DndEdgeViewScroll, DndEdgeWorkspaceSwitch).
var defaults = {
    "gestures.dndViewWidth": 30,
    "gestures.dndWorkspaceHeight": 50
};

var stored = {
    "gestures.dndViewWidth": "page",
    "gestures.dndWorkspaceHeight": "page"
};

var search = [
    { key: "gestures.dndViewWidth", title: "Side edges scroll while dragging", words: ["drag", "edge", "scroll", "dnd"] },
    { key: "gestures.dndWorkspaceHeight", title: "Top and bottom edges switch workspace while dragging", words: ["drag", "edge", "workspace", "dnd"] }
];

function toKdl(state) {
    const view = state["gestures.dndViewWidth"];
    const ws = state["gestures.dndWorkspaceHeight"];
    return [
        { block: "gestures.dnd-edge-view-scroll", lines: view === defaults["gestures.dndViewWidth"] ? [] : ["trigger-width " + view] },
        { block: "gestures.dnd-edge-workspace-switch", lines: ws === defaults["gestures.dndWorkspaceHeight"] ? [] : ["trigger-height " + ws] }
    ];
}
