pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Geometry and behaviour settings.
//
// Values are merged, lowest precedence first:
//   1. `builtinDefaults` below (last-resort fallback, used when nothing else
//      can be read -- this is the ONLY place literals live in the QML sources)
//   2. /etc/xdg/line-launcher/config.json   (nixosModules.default)
//   3. $XDG_CONFIG_HOME/line-launcher/config.json  (homeManagerModules.default)
//      or $LINE_LAUNCHER_CONFIG when --config was passed
//   4. environment overrides set by launcher.sh from the CLI flags
Singleton {
    id: root

    readonly property var builtinDefaults: ({
        "font": null,
        "fontSize": 14,
        "colorsFile": null,
        "colorsFormat": null,
        "accentKey": "auto",
        "colors": {
            "foreground": "#c5c8c6",
            "background": "#1d1f21",
            "accent": "#5f87d7",
            "danger": "#d75f5f"
        },
        "glowEnabled": true,
        "glowRadius": 8,
        "glowOpacity": 0.55,
        "auraRadius": 20,
        "auraOpacity": 0.35,
        "frameWidth": 260,
        "whiskerLength": 50,
        "hookLength": 16,
        "visibleItems": 5,
        "listPerspective": 0,
        "maxCharacters": 60,
        "terminal": null,
        "commandAccent": null,
        "drunCache": null,
        "matchingMethod": "normal",
        "normalizeMatch": false,
        "sortMatches": false,
        "sortingMethod": "normal",
        "matchFields": "name,generic,exec,categories,keywords",
        "preferNameMatch": true,
        "actions": []
    })

    // ---------------------------------------------------------------- paths

    readonly property string homeDir: Quickshell.env("HOME") || ""
    readonly property string xdgConfigHome: Quickshell.env("XDG_CONFIG_HOME") || (root.homeDir + "/.config")

    readonly property string xdgCacheHome: Quickshell.env("XDG_CACHE_HOME") || (root.homeDir + "/.cache")
    readonly property string xdgStateHome: Quickshell.env("XDG_STATE_HOME") || (root.homeDir + "/.local/state")
    readonly property string stateDir: root.xdgStateHome + "/line-launcher"

    readonly property string systemConfigPath: "/etc/xdg/line-launcher/config.json"
    readonly property string userConfigPath: Quickshell.env("LINE_LAUNCHER_CONFIG")
        || (root.xdgConfigHome + "/line-launcher/config.json")

    // --------------------------------------------------------------- merged

    property var data: root.builtinDefaults

    function parseFile(view: var): var {
        try {
            const text = view.text();
            if (!text || text.trim() === "") return ({});
            const parsed = JSON.parse(text);
            return (parsed && typeof parsed === "object") ? parsed : ({});
        } catch (e) {
            return ({});
        }
    }

    // One level of nesting is enough for our schema: only `colors` is an object.
    function mergeInto(target: var, source: var) {
        for (const key in source) {
            const value = source[key];
            if (value === null || value === undefined) continue;
            if (typeof value === "object" && !Array.isArray(value)
                    && typeof target[key] === "object" && !Array.isArray(target[key])) {
                const nested = {};
                mergeInto(nested, target[key]);
                mergeInto(nested, value);
                target[key] = nested;
            } else {
                target[key] = value;
            }
        }
    }

    function reload() {
        const merged = {};
        mergeInto(merged, root.builtinDefaults);
        mergeInto(merged, root.parseFile(systemConfigFile));
        mergeInto(merged, root.parseFile(userConfigFile));
        root.data = merged;

        // An explicit colorsFile arriving in the config switches probing off,
        // and one being removed switches it back on.
        root.detectColors();
    }

    FileView {
        id: systemConfigFile
        path: root.systemConfigPath
        watchChanges: true
        blockLoading: true
        printErrors: false
        // `text()` still returns the previous contents when fileChanged
        // fires; reload() re-reads and emits loaded with the new bytes.
        onFileChanged: systemConfigFile.reload()
        onLoaded: root.reload()
        onLoadFailed: root.reload()
    }

    FileView {
        id: userConfigFile
        path: root.userConfigPath
        watchChanges: true
        blockLoading: true
        printErrors: false
        onFileChanged: userConfigFile.reload()
        onLoaded: root.reload()
        onLoadFailed: root.reload()
    }

    Component.onCompleted: root.reload()

    // ------------------------------------------------------- CLI overrides

    readonly property int itemsOverride: parseInt(Quickshell.env("LINE_LAUNCHER_ITEMS") || "", 10)
    readonly property bool ghostDisabled: (Quickshell.env("LINE_LAUNCHER_NO_GHOST") || "") !== ""

    // --------------------------------------------------------- typography

    readonly property string fontFamily: root.data.font || ""
    readonly property int fontSize: root.data.fontSize

    // ----------------------------------------------------------- geometry

    readonly property int frameWidth: root.data.frameWidth
    readonly property int whiskerLength: root.data.whiskerLength
    readonly property int hookLength: root.data.hookLength
    readonly property real strokeWidth: 2

    readonly property int visibleItems: !isNaN(root.itemsOverride) && root.itemsOverride > 0
        ? root.itemsOverride
        : root.data.visibleItems

    // How much of the receding fan the result lane draws. 0 is a straight
    // dropdown -- even steps, no tilt, no narrowing -- and 1 is the full
    // projection. Clamped, since the geometry between the two is a blend and
    // anything outside it is not.
    readonly property real listPerspective:
        Math.max(0, Math.min(1, root.data.listPerspective))

    // Result-row metrics. Derived from the font size rather than exposed as
    // options: they are proportions of the type, not independent knobs.
    readonly property int iconSize: Math.round(root.fontSize * 1.5)

    // Quickshell's icon provider hands back the largest theme size that is
    // <= the requested sourceSize. Asking for the exact rendered size gets a
    // smaller pixmap scaled up, which is what made icons blurry: a 21px
    // request returns a 16px pixmap.
    //
    // 22 is deliberately absent. Most themes are scalable and honour any
    // request, but fixed-size entries are common at 16 and 24 and a 22px
    // request rounds down to 16 for them -- Firefox on this machine does
    // exactly that.
    readonly property var themeIconSizes: [16, 24, 32, 48, 64, 96, 128, 256]

    // Over-request by a quarter so the result is never smaller than the slot
    // even when a theme's sizes are sparse. Downscaling with smooth and mipmap
    // stays sharp; upscaling does not.
    readonly property real iconSizeMargin: 1.25

    function themeIconSize(pixels: real): int {
        for (let i = 0; i < root.themeIconSizes.length; i++) {
            if (root.themeIconSizes[i] >= pixels) return root.themeIconSizes[i];
        }
        return root.themeIconSizes[root.themeIconSizes.length - 1];
    }

    // What to ask the icon loader for: the rendered size in device pixels,
    // with margin, rounded up to a standard theme size.
    readonly property int iconPixelSize: root.themeIconSize(
        Math.ceil(root.iconSize * root.iconSizeMargin
            * (root.devicePixelRatio > 0 ? root.devicePixelRatio : 1)))
    readonly property int rowHeight: Math.round(root.fontSize * 2.4)
    readonly property int rowStep: Math.round(root.fontSize * 3.0)
    readonly property real cornerRadius: 4
    readonly property real frameToListGap: Math.round(root.fontSize * 1.6)

    // --------------------------------------------------------------- glow

    // Two halos, and they are not the same effect.
    //
    //   glow*  the legibility halo under the text, the strokes and the icons.
    //          Palette background, tight and dim: it exists so a 2px stroke
    //          survives a pale wallpaper, not so it can be seen.
    //   aura*  the accent halo around the selection outline, and nowhere
    //          else. Wider, softer, and in the colour the outline already is.
    //
    // Radii are quoted at the default font size and scale with it. A halo is a
    // proportion of the type it sits under -- 8px around 14px text is a rim,
    // 8px around 28px text is a hairline -- so a launcher configured larger
    // gets a proportionally larger halo rather than a thinner-looking one.
    readonly property real typeScale: root.builtinDefaults.fontSize > 0
        ? root.fontSize / root.builtinDefaults.fontSize
        : 1

    readonly property bool glowEnabled: root.data.glowEnabled !== false

    readonly property real glowRadius: root.data.glowRadius * root.typeScale
    readonly property real glowOpacity: root.data.glowOpacity
    readonly property real auraRadius: root.data.auraRadius * root.typeScale
    readonly property real auraOpacity: root.data.auraOpacity

    // ----------------------------------------------------------- behaviour

    readonly property bool ghostEnabled: !root.ghostDisabled
    readonly property string prompt: Quickshell.env("LINE_LAUNCHER_PROMPT") || ""

    // The layer-shell namespace, handed to the compositor verbatim: whatever
    // --namespace was given, that is the string Hyprland's layerrules match
    // on. Empty only if someone exports the variable empty, and layer-shell
    // wants a name, so the default stands in for that.
    readonly property string namespace: Quickshell.env("LINE_LAUNCHER_NAMESPACE") || "line-launcher"

    readonly property int maxCharacters: root.data.maxCharacters
    readonly property string terminal: root.data.terminal || ""
    readonly property var actions: root.data.actions || []

    // A provider may claim its own accent while its prefix is active. Only
    // reachable through a raw config.json key today, since the Nix modules do
    // not expose it; a transparent value means "no claim".
    readonly property color commandAccent: root.data.commandAccent || "transparent"

    // ------------------------------------------------------------ rofi search

    // Passed straight through to rofi-search.js. Defaults are stock
    // `rofi -dump-config` values. Raw config.json keys only; the Nix modules
    // do not expose them.
    readonly property string matchingMethod: root.data.matchingMethod || "normal"
    readonly property bool normalizeMatch: root.data.normalizeMatch === true
    readonly property bool sortMatches: root.data.sortMatches === true
    readonly property string sortingMethod: root.data.sortingMethod || "normal"
    readonly property string matchFields: root.data.matchFields || "name,generic,exec,categories,keywords"
    readonly property bool preferNameMatch: root.data.preferNameMatch !== false

    // rofi's own launch history, in rofi's rofi3.druncache format. Point this
    // at ~/.cache/rofi3.druncache to share history with rofi itself.
    readonly property string drunCachePath: {
        const configured = root.data.drunCache || "";
        if (configured === "") return root.xdgCacheHome + "/line-launcher.druncache";
        return configured.startsWith("/") ? configured : (root.xdgCacheHome + "/" + configured);
    }

    // ------------------------------------------------------------ dmenu mode

    // launcher.sh stages piped stdin into a file and names an output file.
    // Their presence is what puts the launcher into dmenu mode.
    readonly property string dmenuInputPath: Quickshell.env("LINE_LAUNCHER_DMENU_IN") || ""
    readonly property string dmenuOutputPath: Quickshell.env("LINE_LAUNCHER_DMENU_OUT") || ""
    readonly property bool dmenuMode: root.dmenuInputPath !== ""

    // ---------------------------------------------------------- colour cfg

    readonly property string explicitColorsFile: root.data.colorsFile || ""
    readonly property string explicitColorsFormat: root.data.colorsFormat || ""

    // Where each supported generator writes by default. Probed in this order
    // when no colorsFile is configured; the one that hits decides the format
    // too, so `qs -p .` with no config file at all still picks up the
    // wallpaper colours.
    readonly property var colorsCandidates: [
        {"path": root.xdgCacheHome + "/wal/colors.json", "format": "pywal"},
        {"path": root.xdgCacheHome + "/wallust/colors.json", "format": "wallust"},
        {"path": root.xdgCacheHome + "/matugen/colors.json", "format": "matugen"}
    ]

    // Existence probes for the candidates above.
    //
    // blockLoading does not mean "load eagerly" -- it means "block when the
    // contents are asked for". A FileView's `loaded` stays false until
    // something actually reads it, so testing `loaded` from a binding reports
    // "missing" for a file that is right there. Measured: with blockLoading
    // set and a real file, `loaded` was still false one full event-loop pass
    // after construction, and only text() flipped it.
    //
    // So text() is the probe. It blocks, it returns "" rather than throwing
    // when the file is not there, and after it returns `loaded` is truthful.
    // A palette file is a couple of kilobytes, so the read costs nothing worth
    // optimising, and doing it synchronously means the first frame is already
    // painted in the right colours.
    component ColorsProbe: FileView {
        id: probe

        property int slot: 0

        // An empty path switches the probe off entirely once an explicit
        // colorsFile has been configured.
        path: root.explicitColorsFile === "" ? root.colorsCandidates[slot].path : ""
        blockLoading: true
        printErrors: false
        // A file that does not exist yet -- a machine that has not run pywal
        // yet -- starts working the moment it appears.
        watchChanges: true

        onFileChanged: {
            probe.reload();
            root.detectColors();
        }
        onLoadFailed: root.detectColors()
    }

    ColorsProbe {
        id: walProbe
        slot: 0
    }
    ColorsProbe {
        id: wallustProbe
        slot: 1
    }
    ColorsProbe {
        id: matugenProbe
        slot: 2
    }

    readonly property var colorsProbes: [walProbe, wallustProbe, matugenProbe]

    property var detectedColors: null

    function detectColors() {
        if (root.explicitColorsFile !== "") {
            root.detectedColors = null;
            return;
        }

        for (let i = 0; i < root.colorsProbes.length; i++) {
            // An unreadable or empty palette file is treated as absent: there
            // is nothing to parse out of it either way, and the next candidate
            // may well be real.
            if (root.colorsProbes[i].text().length > 0) {
                root.detectedColors = root.colorsCandidates[i];
                return;
            }
        }

        root.detectedColors = null;
    }

    // "explicit" | "probed" | "none" -- reported in the startup log line so a
    // launcher that came up with the wrong colours can be diagnosed without
    // instrumenting anything.
    readonly property string colorsRule: {
        if (root.explicitColorsFile !== "") return "explicit";
        return root.detectedColors !== null ? "probed" : "none";
    }

    readonly property string colorsFile: root.explicitColorsFile !== ""
        ? root.explicitColorsFile
        : (root.detectedColors !== null ? root.detectedColors.path : "")

    readonly property string colorsFormat: {
        // An explicitly configured format always wins, whether or not the file
        // itself was configured.
        if (root.explicitColorsFormat !== "") return root.explicitColorsFormat;
        if (root.detectedColors !== null) return root.detectedColors.format;
        return "pywal";
    }

    // "auto" resolves at colour-load time to whichever palette entry sits
    // furthest from the foreground; Theme owns that decision because it is the
    // only thing that has parsed the palette. Any other value names a key
    // directly and is passed straight through.
    readonly property string accentKey: root.data.accentKey || "auto"

    readonly property var fallbackColors: root.data.colors || root.builtinDefaults.colors

    // ------------------------------------------------------ pixel snapping

    // Set from shell.qml, which is the only place with a Screen attached
    // property. 2px strokes land on device pixels only when their coordinates
    // are rounded in device space.
    property real devicePixelRatio: 1

    function snap(value: real): real {
        const ratio = root.devicePixelRatio > 0 ? root.devicePixelRatio : 1;
        return Math.round(value * ratio) / ratio;
    }
}
