.pragma library
.import "sections/look.js" as Look
.import "sections/columns.js" as Columns
.import "sections/advanced.js" as Advanced

.import "sections/close.js" as Close
.import "sections/workspaces.js" as Workspaces
.import "sections/session.js" as Session
.import "sections/startup.js" as Startup
.import "sections/rules.js" as Rules
.import "sections/gestures.js" as Gestures
.import "sections/animations.js" as Animations
.import "sections/corners.js" as Corners
.import "sections/input.js" as Input

// Each section lot adds one `.import "sections/<id>.js" as <Id>` line above and one entry:
// { id: "<menu section id>", defaults: <Id>.defaults, toKdl: <Id>.toKdl, search: <Id>.search, stored: <Id>.stored },
var sections = [
    { id: "windows", defaults: Look.defaults, toKdl: Look.toKdl, search: Look.search, stored: Look.stored },
    { id: "windows", defaults: Columns.defaults, toKdl: Columns.toKdl, search: Columns.search, stored: Columns.stored },
    { id: "advanced", defaults: Advanced.defaults, toKdl: Advanced.toKdl, search: Advanced.search, stored: Advanced.stored },
    { id: "workspaces", defaults: Close.defaults, toKdl: Close.toKdl, search: Close.search, stored: Close.stored },
    { id: "workspaces", defaults: Workspaces.defaults, toKdl: Workspaces.toKdl, search: Workspaces.search, stored: Workspaces.stored },
    { id: "workspaces", defaults: Session.defaults, toKdl: Session.toKdl, search: Session.search, stored: Session.stored },
    { id: "startup", defaults: Startup.defaults, toKdl: Startup.toKdl, search: Startup.search, stored: Startup.stored },
    { id: "windows", defaults: Rules.defaults, toKdl: Rules.toKdl, search: Rules.search, stored: Rules.stored },
    { id: "gestures", defaults: Gestures.defaults, toKdl: Gestures.toKdl, search: Gestures.search, stored: Gestures.stored },
    { id: "animations", defaults: Animations.defaults, toKdl: Animations.toKdl, search: Animations.search, stored: Animations.stored },
    { id: "gestures", defaults: Corners.defaults, toKdl: Corners.toKdl, search: Corners.search, stored: Corners.stored },
    { id: "input", defaults: Input.defaults, toKdl: Input.toKdl, search: Input.search, stored: Input.stored },
];
