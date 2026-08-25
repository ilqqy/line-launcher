// Colours-file auto-detection, and "auto" end to end.
//
// Run by run.sh with no colorsFile configured and a pywal file staged where
// pywal writes -- the situation of running `qs -p .` from the repo without the
// Nix module enabled, which is what made the launcher fall back to statics.
import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: suite

    property int failures: 0

    function check(label: string, actual: var, expected: var) {
        const ok = String(actual) === String(expected);
        if (!ok) suite.failures += 1;
        console.log((ok ? "ok   " : "FAIL ") + label
            + (ok ? "" : "  expected " + expected + ", got " + actual));
    }

    readonly property string cacheHome: Quickshell.env("XDG_CACHE_HOME") || ""

    // Sampled at the earliest moment anything can observe it. Detection has to
    // be settled by now or the launcher paints its first frame in the fallback
    // colours and snaps a frame later.
    property string fileAtCompletion: ""
    property string accentAtCompletion: ""

    Component.onCompleted: {
        suite.fileAtCompletion = Config.colorsFile;
        suite.accentAtCompletion = String(Theme.accent);
    }

    // Deferred: Qt.exit() emitted during Component.onCompleted arrives before
    // the engine has connected a receiver, and the process then never exits.
    Timer {
        interval: 0
        repeat: false
        running: true
        onTriggered: suite.run()
    }

    function run() {
        suite.check("nothing was configured",
            Config.explicitColorsFile, "");
        suite.check("the probe found the pywal file",
            Config.colorsFile, suite.cacheHome + "/wal/colors.json");
        suite.check("and reports how it got there",
            Config.colorsRule, "probed");
        suite.check("the format came from which probe hit",
            Config.colorsFormat, "pywal");

        // If the palette had not actually been read, every accessor would be
        // sitting on the builtin statics instead.
        suite.check("the palette parsed",
            String(Theme.foreground), "#c4c5c6");
        suite.check("not the builtin fallback",
            String(Theme.foreground) !== String(Config.fallbackColors.foreground), true);

        suite.check("accentKey defaults to auto", Config.accentKey, "auto");
        suite.check("auto resolved to a real key",
            Theme.autoAccent.key !== "", true);
        suite.check("auto did not pick a near-grey",
            ["color4", "color6"].indexOf(Theme.autoAccent.key) < 0, true);
        suite.check("the resolved key is what the accent came from",
            String(Theme.accent).toLowerCase(),
            String(Theme.autoAccent.color).toLowerCase());

        console.log("     " + Theme.describeAccent());

        suite.check("detection is settled before the first frame",
            suite.fileAtCompletion, Config.colorsFile);
        suite.check("so is the accent, with no fallback flash",
            suite.accentAtCompletion, String(Theme.accent));

        // A probed file has to be watched exactly like a configured one, so
        // regenerating the palette recolours a running launcher. Rewriting it
        // here is what pywal does on a wallpaper change; the new palette puts
        // the only saturated entry in color3.
        suite.beforeRewrite = String(Theme.accent);
        rewriter.setText(JSON.stringify({
            "special": {"foreground": "#c4c5c6", "background": "#13171b"},
            "colors": {
                "color0": "#13171b", "color1": "#c9c8c4", "color2": "#cdc9c6",
                "color3": "#1f8a3c", "color4": "#DCD2D5", "color5": "#d0cdc9",
                "color6": "#D3D9E6", "color7": "#c4c5c6"
            }
        }));
        watchdog.start();
    }

    property string beforeRewrite: ""

    FileView {
        id: rewriter
        path: Config.colorsFile
        blockWrites: true
        atomicWrites: true
        printErrors: false
    }

    // The watch is a filesystem notification, so it lands whenever it lands.
    // Polling until it does, with a ceiling, keeps the suite honest either way.
    property int polls: 0

    Timer {
        id: watchdog
        interval: 50
        repeat: true
        onTriggered: {
            suite.polls += 1;
            const changed = String(Theme.accent) !== suite.beforeRewrite;
            if (!changed && suite.polls < 40) return;

            watchdog.stop();
            suite.check("rewriting the probed file recolours in place", changed, true);
            suite.check("and the accent re-picks for the new palette",
                Theme.autoAccent.key, "color3");
            console.log("     " + suite.beforeRewrite + " -> " + Theme.accent
                + " after " + (suite.polls * watchdog.interval) + "ms");

            console.log(suite.failures === 0 ? "PASS" : "FAIL (" + suite.failures + ")");
            Qt.exit(suite.failures === 0 ? 0 : 1);
        }
    }
}
