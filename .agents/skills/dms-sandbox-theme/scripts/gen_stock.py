#!/usr/bin/env python3
"""Turn a DMS registry theme.json into the --stock-colors JSON the shell would pass.

Mirrors Theme.buildMatugenColorsFromTheme in quickshell/Common/Theme.qml (role names and
fallbacks); re-check that function if templates start reading roles this doesn't emit.

  gen_stock.py THEME_JSON {dark|light} [--dark-variant FLAVOR[/ACCENT]] [--light-variant ...]

Variants default to the theme's variants.defaults. For "options" themes pass the option id.
The "default" variant follows MODE, as the shell does; getting this wrong makes light-mode
runs mix dark roles with light terminal colors.
"""
import argparse
import json
import sys


def merged(theme, mode, choice):
    d = dict(theme.get(mode) or {})
    v = theme.get("variants")
    if not v:
        return d
    if v.get("type") == "multi":
        flavor, _, accent = (choice or "").partition("/")
        dflt = (v.get("defaults") or {}).get(mode) or {}
        flavor = flavor or dflt.get("flavor")
        accent = accent or dflt.get("accent")
        fl = next((f for f in v["flavors"] if f["id"] == flavor), None)
        if fl is None:
            sys.exit(f"unknown flavor {flavor!r}; have {[f['id'] for f in v['flavors']]}")
        d.update(fl.get(mode) or {})
        ac = next((a for a in v["accents"] if a["id"] == accent), None)
        if ac is None:
            sys.exit(f"unknown accent {accent!r}; have {[a['id'] for a in v['accents']]}")
        d.update(ac.get(flavor) or {})
        return d
    option = choice or v.get("default")
    opt = next((o for o in v.get("options", []) if o["id"] == option), None)
    if opt is None:
        sys.exit(f"unknown option {option!r}; have {[o['id'] for o in v.get('options', [])]}")
    d.update(opt.get(mode) or {})
    return d


# role: (theme keys tried in order, dark default, light default); roles whose fallback differs by
# mode or is computed are in PER_MODE and ON_CONTAINER below.
ROLES = {
    "primary": (["primary"], None, None),
    "on_primary": (["primaryText"], None, None),
    "primary_container": (["primaryContainer"], None, None),
    "secondary": (["secondary"], None, None),
    "on_secondary": (["secondaryText", "primaryText"], None, None),
    "secondary_container": (["secondaryContainer", "surfaceContainerHigh"], None, None),
    "tertiary": (["tertiary", "secondary"], None, None),
    "on_tertiary": (["tertiaryText", "secondaryText", "primaryText"], None, None),
    "tertiary_container": (["tertiaryContainer", "secondaryContainer", "surfaceContainerHigh"], None, None),
    "error": (["error"], "#F2B8B5", "#B3261E"),
    "on_error": (["errorText"], "#601410", "#FFFFFF"),
    "error_container": (["errorContainer"], "#8C1D18", "#F9DEDC"),
    "on_error_container": (["errorContainerText"], "#F9DEDC", "#410E0B"),
    "surface": (["surface"], None, None),
    "on_surface": (["surfaceText"], None, None),
    "surface_variant": (["surfaceVariant"], None, None),
    "on_surface_variant": (["surfaceVariantText"], None, None),
    "surface_tint": (["surfaceTint"], None, None),
    "background": (["background"], None, None),
    "on_background": (["backgroundText"], None, None),
    "outline": (["outline"], None, None),
    "outline_variant": (["outlineVariant", "surfaceVariant"], None, None),
    "surface_container": (["surfaceContainer"], None, None),
    "surface_container_high": (["surfaceContainerHigh"], None, None),
    "surface_container_highest": (["surfaceContainerHighest", "surfaceContainerHigh"], None, None),
    "surface_container_low": (["surfaceContainerLow", "surface"], None, None),
    "surface_container_lowest": (["surfaceContainerLowest", "background"], None, None),
    "scrim": (["scrim"], "#000000", "#000000"),
    "shadow": (["shadow"], "#000000", "#000000"),
    "source_color": (["primary"], None, None),
    "primary_fixed": (["primaryFixed", "primaryContainer"], None, None),
    "primary_fixed_dim": (["primaryFixedDim", "primary"], None, None),
    "on_primary_fixed": (["onPrimaryFixed", "primaryText"], None, None),
    "on_primary_fixed_variant": (["onPrimaryFixedVariant", "primaryText"], None, None),
    "secondary_fixed": (["secondaryFixed", "secondary"], None, None),
    "secondary_fixed_dim": (["secondaryFixedDim", "secondary"], None, None),
    "on_secondary_fixed": (["onSecondaryFixed", "primaryText"], None, None),
    "on_secondary_fixed_variant": (["onSecondaryFixedVariant", "primaryText"], None, None),
    "tertiary_fixed": (["tertiaryFixed", "tertiary", "secondary"], None, None),
    "tertiary_fixed_dim": (["tertiaryFixedDim", "tertiary", "secondary"], None, None),
    "on_tertiary_fixed": (["onTertiaryFixed", "primaryText"], None, None),
    "on_tertiary_fixed_variant": (["onTertiaryFixedVariant", "primaryText"], None, None),
}


# role: (dark keys, light keys)
PER_MODE = {
    "surface_bright": (["surfaceBright", "surfaceContainerHighest", "surfaceContainerHigh"], ["surfaceBright", "surface"]),
    "surface_dim": (["surfaceDim", "background"], ["surfaceDim", "surfaceContainer"]),
}

# role: (container key, explicit text keys) -- Theme.qml onContainer()
ON_CONTAINER = {
    "on_primary_container": ("primaryContainer", ["onPrimaryContainer", "primaryContainerText"]),
    "on_secondary_container": ("secondaryContainer", ["onSecondaryContainer", "secondaryContainerText"]),
    "on_tertiary_container": ("tertiaryContainer", ["onTertiaryContainer", "tertiaryContainerText"]),
}


def luminance(hex_color):
    def lin(v):
        v /= 255
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    h = hex_color.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) for i in (0, 2, 4))
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)


def ratio(a, b):
    la, lb = luminance(a), luminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


def readable_on(background, candidates, target=4.5):
    """DCommon Contrast.readableOn: first candidate reaching target, else the best one."""
    best = candidates[0]
    for c in candidates:
        if ratio(c, background) >= target:
            return c
        if ratio(c, background) > ratio(best, background):
            best = c
    return best


def on_container(theme, container_key, explicit_keys):
    explicit = next((theme[k] for k in explicit_keys if theme.get(k)), None)
    if explicit:
        return explicit
    container, text, surface = theme.get(container_key), theme.get("surfaceText"), theme.get("surface")
    if not container or not text or not surface:
        return text
    return readable_on(container, [text, surface, "#ffffff", "#000000"])


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("theme")
    ap.add_argument("mode", choices=["dark", "light"])
    ap.add_argument("--dark-variant")
    ap.add_argument("--light-variant")
    a = ap.parse_args()

    theme = json.load(open(a.theme))
    dark, light = merged(theme, "dark", a.dark_variant), merged(theme, "light", a.light_variant)
    pick = lambda th, keys, dflt: next((th[k] for k in keys if th.get(k)), dflt)

    colors = {}
    for role, (keys, ddef, ldef) in ROLES.items():
        dv, lv = pick(dark, keys, ddef), pick(light, keys, ldef)
        if not dv and not lv:
            continue
        dv, lv = dv or lv, lv or dv
        colors[role] = {"dark": {"color": dv}, "light": {"color": lv}, "default": {"color": lv if a.mode == "light" else dv}}
    def put(role, dv, lv):
        if not dv and not lv:
            return
        dv, lv = dv or lv, lv or dv
        colors[role] = {"dark": {"color": dv}, "light": {"color": lv}, "default": {"color": lv if a.mode == "light" else dv}}
    for role, (dkeys, lkeys) in PER_MODE.items():
        put(role, pick(dark, dkeys, None), pick(light, lkeys, None))
    for role, (ckey, ekeys) in ON_CONTAINER.items():
        put(role, on_container(dark, ckey, ekeys), on_container(light, ckey, ekeys))
    for role, dk, lk in [("inverse_surface", "inverseSurface", "surface"), ("inverse_on_surface", "inverseOnSurface", "surfaceText"), ("inverse_primary", "inversePrimary", "primary")]:
        dv, lv = dark.get(dk) or light.get(lk), light.get(dk) or dark.get(lk)
        if dv or lv:
            colors[role] = {"dark": {"color": dv}, "light": {"color": lv}, "default": {"color": lv if a.mode == "light" else dv}}
    if "primary" not in colors:
        sys.exit("theme has no primary color for the chosen variant")
    json.dump(colors, sys.stdout)
    print()


if __name__ == "__main__":
    main()
