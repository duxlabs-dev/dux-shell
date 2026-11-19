.pragma library

var FALLBACK = "comfortable";

// Sizes that do not change with the density.
var COMMON = { gaugeStroke: 4, barStroke: 6, badgeSize: 11, badgeGlyph: 9, badgeCut: 1.5, badgeOverhang: 4 };

var TABLE = {
    spacious: { pad: 20, gap: 12, powerButton: 64, button: 48, row: 56, tile: 16, chip: 36, fill: 160, fillSmall: 88, deviceRing: 80, heroRing: 208, heroRingList: 168, heroSmall: 72, heroNumberSmall: false, compact: false },
    comfortable: { pad: 16, gap: 10, powerButton: 56, button: 40, row: 52, tile: 12, chip: 32, fill: 136, fillSmall: 80, deviceRing: 72, heroRing: 184, heroRingList: 144, heroSmall: 72, heroNumberSmall: false, compact: false },
    compact: { pad: 12, gap: 8, powerButton: 48, button: 40, row: 48, tile: 8, chip: 32, fill: 112, fillSmall: 72, deviceRing: 64, heroRing: 184, heroRingList: 144, heroSmall: 72, heroNumberSmall: false, compact: true },
    dense: { pad: 8, gap: 4, powerButton: 40, button: 32, row: 40, tile: 4, chip: 28, fill: 88, fillSmall: 56, deviceRing: 56, heroRing: 184, heroRingList: 144, heroSmall: 56, heroNumberSmall: true, compact: true }
};

for (const name of Object.keys(TABLE))
    TABLE[name] = Object.assign({}, COMMON, TABLE[name]);

// `density` is the shell's Interface density; an unknown value gets the comfortable sizes.
function metrics(density) {
    return TABLE.hasOwnProperty(density) ? TABLE[density] : TABLE[FALLBACK];
}
