import { loadScript } from "./qml-script.mjs";

// The island kit and its decor clock, as the kit tests read them.
export const K = loadScript(new URL("../Common/IslandKit.js", import.meta.url));
export const KC = loadScript(new URL("../Common/IslandClock.js", import.meta.url));
