pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "color.js" as Colour

// Colours.
//
// Config.colorsFile, when set, is watched at runtime through a second
// FileView. Re-running pywal/wallust/matugen rewrites that file, the watcher
// fires, and every binding below re-evaluates -- a running launcher recolours
// with no restart and no rebuild.
//
// If the file is missing, unreadable, or malformed, every accessor falls back
// to the static colours from config.json, and those in turn fall back to
// Config.builtinDefaults. Nothing here can throw.
Singleton {
    id: root

    // ------------------------------------------------------- watched source

    property var palette: ({})

    FileView {
        id: colorsFile
        path: Config.colorsFile
        watchChanges: true
        blockLoading: true
        printErrors: false
        // `text()` still returns the previous contents when fileChanged
        // fires; reload() re-reads and emits loaded with the new bytes. This
        // is what makes a wallpaper change recolour a running launcher.
        onFileChanged: colorsFile.reload()
        onLoaded: root.reloadPalette()
        onLoadFailed: root.palette = ({})
        // Config resolves its path by probing, so it can arrive after this
        // view is built. reloadPalette() reads through text(), which blocks,
        // so the new palette is in place before this handler returns.
        onPathChanged: root.reloadPalette()
    }

    function reloadPalette() {
        if (Config.colorsFile === "") {
            root.palette = ({});
            return;
        }
        try {
            const text = colorsFile.text();
            const parsed = JSON.parse(text);
            root.palette = (parsed && typeof parsed === "object") ? parsed : ({});
        } catch (e) {
            root.palette = ({});
        }
    }

    Component.onCompleted: root.reloadPalette()

    // ------------------------------------------------------------- parsing

    function isColor(value: var): bool {
        return typeof value === "string" && /^#[0-9a-fA-F]{3,8}$/.test(value);
    }

    // Walks a list of candidate lookups and returns the first that yields
    // something that actually looks like a colour.
    function pick(candidates: var): var {
        for (let i = 0; i < candidates.length; i++) {
            if (root.isColor(candidates[i])) return candidates[i];
        }
        return null;
    }

    function at(object: var, key: string): var {
        return (object && typeof object === "object") ? object[key] : undefined;
    }

    // pywal and wallust both write a pywal-shaped file most of the time, but
    // wallust can also emit the palette flat at the top level, so both shapes
    // are probed for both formats.
    readonly property var walColors: root.at(root.palette, "colors") || root.palette
    readonly property var walSpecial: root.at(root.palette, "special") || root.palette

    // matugen nests by scheme; when generated with a single scheme the roles
    // sit at the top level instead.
    readonly property var matugenRoles: {
        const colors = root.at(root.palette, "colors");
        return root.at(colors, "dark") || root.at(colors, "light") || colors || root.palette;
    }

    readonly property var parsedForeground: {
        if (Config.colorsFormat === "matugen") {
            return root.pick([
                root.at(root.matugenRoles, "on_surface"),
                root.at(root.matugenRoles, "on_background"),
                root.at(root.matugenRoles, "on_primary_container")
            ]);
        }
        return root.pick([
            root.at(root.walSpecial, "foreground"),
            root.at(root.walColors, "color7"),
            root.at(root.walColors, "color15")
        ]);
    }

    // The legibility glow's colour. Deliberately the palette background rather
    // than plain black: on a light scheme the halo has to be light too, or the
    // glow that is meant to make pale text readable would outline it in soot.
    readonly property var parsedBackground: {
        if (Config.colorsFormat === "matugen") {
            return root.pick([
                root.at(root.matugenRoles, "surface"),
                root.at(root.matugenRoles, "background"),
                root.at(root.matugenRoles, "surface_container")
            ]);
        }
        return root.pick([
            root.at(root.walSpecial, "background"),
            root.at(root.walColors, "color0")
        ]);
    }

    // ------------------------------------------------------ accent selection

    // Which palette entries are eligible when accentKey is "auto". color0 and
    // color7-15 are excluded on purpose: 0 is the background shade and 8-15 are
    // the bright variants of 1-7, so including them would mostly offer the same
    // hues twice.
    readonly property var accentCandidateKeys: [
        "color1", "color2", "color3", "color4", "color5", "color6"
    ]

    // A fixed accent key is a bet that one slot of the palette will always be
    // distinct from the foreground, and that bet loses on any near-monochrome
    // wallpaper: every candidate comes back a slightly different grey and the
    // outline disappears against the rows. So "auto" measures instead, picking
    // whichever entry is furthest from the resolved foreground in CIEDE2000.
    // Recomputed on every palette reload, so a new wallpaper re-picks.
    readonly property var autoAccent: {
        const foreground = root.parsedForeground || Config.fallbackColors.foreground;

        let best = {"key": "", "color": "", "distance": -1};
        for (let i = 0; i < root.accentCandidateKeys.length; i++) {
            const key = root.accentCandidateKeys[i];
            const value = root.at(root.walColors, key);
            if (!root.isColor(value)) continue;

            const distance = Colour.deltaE2000(value, String(foreground));
            if (distance > best.distance) {
                best = {"key": key, "color": value, "distance": distance};
            }
        }
        return best;
    }

    // An explicit key in the config always wins over the measurement.
    readonly property string resolvedAccentKey: Config.accentKey === "auto"
        ? root.autoAccent.key
        : Config.accentKey

    readonly property var parsedAccent: {
        if (Config.colorsFormat === "matugen") {
            return root.pick([
                root.at(root.matugenRoles, "primary"),
                root.at(root.matugenRoles, "tertiary"),
                root.at(root.matugenRoles, "secondary")
            ]);
        }
        // An empty resolvedAccentKey (auto found no usable candidate) misses
        // and falls through, same as a key naming an entry that is not there.
        return root.pick([
            root.at(root.walColors, root.resolvedAccentKey),
            root.at(root.walColors, "color4"),
            root.at(root.walSpecial, "foreground")
        ]);
    }

    readonly property var parsedDanger: {
        if (Config.colorsFormat === "matugen") {
            return root.pick([
                root.at(root.matugenRoles, "error"),
                root.at(root.matugenRoles, "on_error_container")
            ]);
        }
        return root.pick([
            root.at(root.walColors, "color1"),
            root.at(root.walColors, "color9")
        ]);
    }

    // ------------------------------------------------------------- exposed

    readonly property color foreground: root.parsedForeground || Config.fallbackColors.foreground
    readonly property color background: root.parsedBackground || Config.fallbackColors.background
    readonly property color accent: root.parsedAccent || Config.fallbackColors.accent
    readonly property color danger: root.parsedDanger || Config.fallbackColors.danger

    // Maximum-contrast query colour. The field is the one place where muted
    // wallpaper-derived foregrounds must not make user input look like ghost
    // text: use white on dark palettes and black on light ones.
    readonly property color queryForeground:
        root.background.hslLightness < 0.5 ? "#ffffff" : "#000000"

    readonly property real mutedAlpha: 0.45
    readonly property color muted: Qt.alpha(root.foreground, root.mutedAlpha)

    // Result rows sit over the wallpaper and also receive the lane's depth
    // fade, so sharing the prompt's quiet 45% alpha makes lower rows too hard
    // to read. Keep them subdued, but give them enough contrast to scan.
    readonly property real resultMutedAlpha: 0.62
    readonly property color resultMuted: Qt.alpha(root.foreground, root.resultMutedAlpha)

    // A provider may claim its own accent (CommandProvider does, once the ">"
    // prefix is active). Setting this to a transparent colour means "no
    // override, use the global accent". The transition is animated so
    // switching prefixes recolours smoothly rather than snapping.
    property color accentOverride: "transparent"

    readonly property bool hasAccentOverride: root.accentOverride.a > 0

    property color activeAccent: root.hasAccentOverride ? root.accentOverride : root.accent

    Behavior on activeAccent {
        ColorAnimation {
            duration: 180
            easing.type: Easing.OutCubic
        }
    }

    // ---------------------------------------------------------- diagnostics

    // Which palette file was used, by which rule, and what "auto" resolved to
    // -- all on one line, at startup, every run. Both decisions are invisible
    // in the UI and wrong-looking colours are otherwise indistinguishable from
    // a parser bug, so this exists to make them answerable without adding
    // instrumentation after the fact.
    property bool decisionsLogged: false

    function describeAccent(): string {
        if (Config.colorsFormat === "matugen") {
            return String(root.accent) + " (matugen primary role)";
        }
        if (Config.accentKey !== "auto") {
            return Config.accentKey + " " + String(root.accent) + " (explicit)";
        }
        if (root.autoAccent.key === "") {
            return String(root.accent) + " (auto found no usable palette entry, fell back)";
        }
        return root.autoAccent.key + " " + root.autoAccent.color
            + " (auto, deltaE2000 " + root.autoAccent.distance.toFixed(1)
            + " from foreground " + String(root.foreground) + ")";
    }

    function logDecisions() {
        if (root.decisionsLogged) return;
        root.decisionsLogged = true;

        const source = Config.colorsFile !== ""
            ? Config.colorsFile + " (" + Config.colorsRule + ", " + Config.colorsFormat + ")"
            : "none (no colorsFile set and nothing found by probing); using config.json statics";

        console.info("line-launcher: colors=" + source + "; accent=" + root.describeAccent());
    }

    // Deferred by one event-loop pass so the probes in Config and this file's
    // own FileView have both settled before anything is reported.
    Timer {
        interval: 0
        repeat: false
        running: true
        onTriggered: root.logDecisions()
    }

    // --------------------------------------------------------------- fonts

    readonly property string fontFamily: Config.fontFamily
    readonly property int fontSize: Config.fontSize
}
