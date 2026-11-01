.pragma library
.import "../../niriKdl.js" as Kdl

// Programs started at login live in DMS Applications > Autostart; this page keeps only the environment.
var defaults = {
    "startup.env": {}
};

var stored = {
    "startup.env": "page"
};

var search = [
    {
        key: "startup.env",
        title: "Environment",
        words: ["environment", "variables", "env", "startup", "login", "autostart"]
    }
];

// The name is written bare into KDL, so anything else could break or inject config.
var namePattern = /^[A-Za-z_][A-Za-z0-9_]*$/;

function parseEnv(text) {
    const i = text.indexOf("=");
    if (i < 0)
        return null;
    const name = text.slice(0, i).trim();
    if (!namePattern.test(name))
        return null;
    return { name: name, value: text.slice(i + 1) };
}

function toKdl(state) {
    const env = state["startup.env"] || {};
    const lines = Object.keys(env).filter(name => namePattern.test(name) && typeof env[name] === "string").map(name => name + " " + Kdl.kdlString(env[name]));
    return [{ block: "environment", lines: lines }];
}
