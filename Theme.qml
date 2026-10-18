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
        return typeof value === "string" && /^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(value);
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

    // The palette background. It tints the panel glass and decides light or
    // dark, so a light scheme gets a light panel rather than a black one.
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
    // accent stops standing out from the text. So "auto" measures instead, picking
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

    // Palette-derived contrast colours: white on dark palettes and black on
    // light ones, plus muted variants. Part of Theme's colour API; the panel
    // itself draws with the design tokens below.
    readonly property color queryForeground:
        root.background.hslLightness < 0.5 ? "#ffffff" : "#000000"

    readonly property real mutedAlpha: 0.45
    readonly property color muted: Qt.alpha(root.foreground, root.mutedAlpha)

    readonly property color resultForeground: root.queryForeground
    readonly property real resultMutedAlpha: 0.9
    readonly property color resultMuted: Qt.alpha(root.resultForeground, root.resultMutedAlpha)
    readonly property color resultBackdrop:
        root.resultForeground.hslLightness > 0.5 ? "#000000" : "#ffffff"

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

    // ======================================================= design tokens
    //
    // Everything the launcher panel draws with: colours, radii, sizes,
    // spacing and durations. Components read these and nothing else, so the
    // whole look is retuned here.
    //
    // Light or dark follows the current palette: whatever pywal, wallust or
    // matugen resolved as the background decides, and a wallpaper change
    // that flips it flips the panel with it.

    readonly property bool dark: root.background.hslLightness < 0.5

    // ---------------------------------------------------------------- type

    // The configured font (programs.line-launcher.font), else Inter.
    readonly property string uiFont: root.fontFamily !== "" ? root.fontFamily : "Inter"
    // Inter ships an optical-size cut for large text, as SF has Display.
    readonly property string displayFont: root.uiFont === "Inter" ? "Inter Display" : root.uiFont

    readonly property int searchFontSize: 22
    readonly property int searchFontWeight: Font.Light
    readonly property int labelFontSize: 12
    readonly property int chipFontSize: 13
    readonly property int chipFontWeight: Font.Medium
    readonly property int rowFontSize: 14
    readonly property int sectionFontSize: 12
    readonly property int sectionFontWeight: Font.DemiBold
    readonly property int emptyTitleSize: 15
    readonly property int emptyBodySize: 13

    // -------------------------------------------------------------- colour

    // Text and glyphs are white or black at fixed alphas, as on macOS, so they
    // keep their contrast over whatever the blur brings through.
    readonly property color ink: root.dark ? "#ffffff" : "#000000"
    readonly property color textPrimary: Qt.alpha(root.ink, root.dark ? 0.92 : 0.86)
    readonly property color textSecondary: Qt.alpha(root.ink, root.dark ? 0.58 : 0.54)
    readonly property color textTertiary: Qt.alpha(root.ink, root.dark ? 0.36 : 0.32)
    readonly property color placeholder: Qt.alpha(root.ink, root.dark ? 0.40 : 0.34)
    readonly property color glyph: root.textSecondary

    // The glass. Tinted with the palette background so the panel sits in the
    // wallpaper's colour family; Hyprland's layer blur supplies the frost.
    // The fill alpha must stay above the layer rule's ignore_alpha (0.15) or
    // the blur is dropped.
    readonly property real panelOpacity: root.dark ? 0.60 : 0.72
    readonly property color panelFill: Qt.alpha(root.background, root.panelOpacity)
    readonly property color panelBorder: root.dark ? Qt.alpha("#ffffff", 0.10) : Qt.alpha("#000000", 0.08)
    readonly property color divider: Qt.alpha(root.ink, root.dark ? 0.09 : 0.08)

    // Kept below ignore_alpha (0.15): a shadow pixel above it would get the
    // blur behind it too, and the shadow would turn into a frosted halo.
    readonly property color shadowColor: Qt.rgba(0, 0, 0, root.dark ? 0.14 : 0.10)

    readonly property color selectionFill: Qt.alpha(root.ink, root.dark ? 0.13 : 0.08)
    readonly property color dangerFill: Qt.alpha(root.danger, 0.24)

    readonly property color chipFill: Qt.alpha(root.ink, root.dark ? 0.07 : 0.05)
    readonly property color chipHoverFill: Qt.alpha(root.ink, root.dark ? 0.13 : 0.10)
    readonly property color chipText: root.textSecondary
    readonly property color chipActiveFill: root.activeAccent
    // Relative luminance of the accent decides the label on it.
    readonly property real accentLuminance:
        0.2126 * root.activeAccent.r + 0.7152 * root.activeAccent.g + 0.0722 * root.activeAccent.b
    readonly property color chipActiveText: root.accentLuminance > 0.65 ? Qt.alpha("#000000", 0.85) : "#ffffff"

    readonly property color clearFill: Qt.alpha(root.ink, root.dark ? 0.26 : 0.22)
    readonly property color clearHoverFill: Qt.alpha(root.ink, root.dark ? 0.40 : 0.34)
    readonly property color clearGlyph: root.dark ? Qt.alpha("#000000", 0.75) : "#ffffff"

    readonly property color caret: root.activeAccent
    readonly property color textSelection: Qt.alpha(root.activeAccent, 0.35)

    readonly property color fallbackIconFill: Qt.alpha(root.ink, root.dark ? 0.10 : 0.07)

    // --------------------------------------------------------------- radii

    readonly property int radiusPanel: 20
    readonly property int radiusTile: 14
    readonly property int radiusRow: 10

    // ------------------------------------------------------ sizes, spacing

    readonly property int panelPadding: 20
    readonly property int panelBottomPadding: 10
    // Where the panel's centre sits, as a fraction of the free height above
    // it: a little above the middle, at the optical centre.
    readonly property real panelVerticalBias: 0.42

    readonly property int searchHeight: 56
    readonly property int searchGlyphSize: 20
    readonly property int searchGap: 12
    readonly property int clearSize: 18

    readonly property int sectionGap: 12
    readonly property int chipHeight: 28
    readonly property int chipPaddingX: 13
    readonly property int chipSpacing: 6

    readonly property int gridColumns: 5
    readonly property int cellWidth: 120
    readonly property int cellHeight: 116
    readonly property int tileInset: 4
    readonly property int iconSize: 56
    readonly property int iconTop: 14
    readonly property int iconLabelGap: 8
    readonly property int labelLines: 2
    readonly property int labelSidePadding: 8
    // A fraction of a row past the third, so the cut-off row under the edge
    // fade says "this scrolls".
    readonly property real gridVisibleRows: 3.4
    readonly property int pageRows: 3

    readonly property int rowHeight: 40
    readonly property int rowSpacing: 2
    readonly property int rowIconSize: 22
    readonly property int rowPaddingX: 12
    readonly property int listInset: 10
    readonly property int listPageRows: 8

    readonly property int fadeSize: 28
    readonly property int shadowBlur: 48
    readonly property int shadowOffsetY: 16

    readonly property int emptyGlyphSize: 40

    // Derived layout, top to bottom: field, hairline, chips, results.
    readonly property int chipsY: root.searchHeight + 1 + root.sectionGap
    readonly property int resultsY: root.chipsY + root.chipHeight + 10
    readonly property int gridWidth: root.gridColumns * root.cellWidth
    readonly property int resultsHeight: Math.round(root.cellHeight * root.gridVisibleRows)
    readonly property int panelWidth: root.gridWidth + 2 * root.panelPadding
    readonly property int panelHeight: root.resultsY + root.resultsHeight + root.panelBottomPadding

    // --------------------------------------------------------------- icons

    readonly property string fallbackIcon: "application-x-executable"
    readonly property string commandIcon: "utilities-terminal"

    // ----------------------------------------------------------- durations

    // Open and close are the same gesture run both ways. Close is quicker
    // because the shell quits on a fixed clock -- 120ms after Esc or a click
    // outside, 160ms after a launch -- and the last frame has to land before
    // the earlier of the two.
    readonly property int openDuration: 150
    readonly property int closeDuration: 110
    readonly property real closedScale: 0.96

    readonly property int highlightDuration: 140
    readonly property int minTravel: 33
    readonly property int scrollDuration: 180
    readonly property int chipDuration: 180
    readonly property int hoverDuration: 120
    readonly property int fadeDuration: 120
    readonly property int pressDuration: 90
    readonly property real pressedScale: 0.92
    readonly property int caretBlink: 530
}
