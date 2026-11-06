.pragma library

// Icons for programs without a desktop entry, one row per program family, names in lower case.
// Every program in a row shows the first of its icons the theme has, then the row's logo from assets/.
// Icon names differ between themes, so list each spelling, best first.
const PROGRAM_ICONS = [
    {
        programs: ["dms", "dsearch"],
        logo: "danklogo.svg"
    },
    {
        programs: ["hyprland", "start-hyprland"],
        logo: "hyprland.svg"
    },
    {
        programs: ["niri"],
        logo: "niri.svg"
    },
    {
        programs: ["sway", "scroll"],
        logo: "sway.svg"
    },
    {
        programs: ["mango"],
        logo: "mango.png"
    },
    {
        programs: ["labwc"],
        logo: "labwc.png"
    },
    {
        programs: ["miracle-wm"],
        logo: "miraclewm.svg"
    },
    {
        programs: ["umbriel"],
        logo: "umbriel.svg"
    },
    {
        programs: ["docker", "dockerd", "docker-proxy", "docker-init", "docker-compose"],
        icons: ["docker", "docker-desktop"]
    },
    {
        programs: ["node", "npm", "npx"],
        icons: ["nodejs"]
    },
    {
        programs: ["jetbrainsd"],
        icons: ["jetbrains-toolbox"]
    }
];
