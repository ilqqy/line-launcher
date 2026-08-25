// Headless assertions for Config, Theme and SearchFrame.
//
// Run through tests/run.sh, which stages the repo root plus this file into a
// temp directory so that `qs -p` can resolve the shell types.
import QtQuick
import Quickshell

ShellRoot {
    id: suite

    property int failures: 0

    function check(label: string, actual: var, expected: var) {
        const ok = String(actual) === String(expected);
        if (!ok) suite.failures += 1;
        console.log((ok ? "ok   " : "FAIL ") + label
            + (ok ? "" : "  expected " + expected + ", got " + actual));
    }

    Item {
        id: host
        width: 1920
        height: 1080

        SearchFrame {
            id: frame
            width: host.width
            height: implicitHeight
            completion: "Steam"
        }
    }

    Timer {
        interval: 400
        running: true
        onTriggered: {
            // --- config layering ------------------------------------------
            suite.check("frameWidth from config.json", Config.frameWidth, 300);
            suite.check("whiskerLength default", Config.whiskerLength, 50);
            suite.check("hookLength default", Config.hookLength, 16);
            suite.check("visibleItems from --items", Config.visibleItems, 9);
            suite.check("prompt from --prompt", Config.prompt, "run:");

            // --- colours --------------------------------------------------
            suite.check("foreground from colorsFile", Theme.foreground, "#00ff00");
            suite.check("accent from accentKey", Theme.accent, "#0000ff");
            suite.check("danger falls back to color1", Theme.danger, "#ff0000");
            suite.check("muted is foreground at 0.45", Theme.muted.a.toFixed(2), "0.45");
            suite.check("activeAccent tracks accent", Theme.activeAccent, Theme.accent);

            // --- ghost text -----------------------------------------------
            frame.inputItem.text = "ste";
            suite.check("prefix match shows ghost", frame.ghostVisible, true);
            suite.check("ghost is the remainder", frame.ghostText, "am");

            frame.inputItem.text = "vlc";
            frame.completion = "Volume Control";
            suite.check("fuzzy non-prefix shows no ghost", frame.ghostVisible, false);
            suite.check("ghost text empty", frame.ghostText, "");

            frame.inputItem.text = "";
            frame.completion = "Steam";
            suite.check("empty query shows no ghost", frame.ghostVisible, false);

            // --- Tab accepts into the real field --------------------------
            frame.inputItem.text = "ste";
            frame.acceptCompletion();
            suite.check("Tab writes the completion", frame.inputItem.text, "Steam");
            suite.check("Tab leaves the caret at the end", frame.inputItem.cursorPosition, 5);

            // --- pixel snapping -------------------------------------------
            Config.devicePixelRatio = 2;
            suite.check("snap to half pixels at dpr 2", Config.snap(10.4), 10.5);
            Config.devicePixelRatio = 1;
            suite.check("snap to whole pixels at dpr 1", Config.snap(10.4), 10);

            console.log(suite.failures === 0
                ? "PASS"
                : "FAIL (" + suite.failures + ")");
            Qt.exit(suite.failures === 0 ? 0 : 1);
        }
    }
}
