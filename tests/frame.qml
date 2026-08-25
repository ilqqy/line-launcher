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

    // Every signal the frame has emitted, newest last. A real QKeyEvent cannot
    // be built from QML, so the keymap is driven through handleKey() and read
    // back from here.
    property var signals: []

    function pressed(key: int, modifiers: int): string {
        suite.signals = [];
        frame.handleKey(key, modifiers);
        return suite.signals.join("+");
    }

    function record(name: string) {
        suite.signals = suite.signals.concat([name]);
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

            onMoveUp: suite.record("up")
            onMoveDown: suite.record("down")
            onAccepted: suite.record("accepted")
            onCancelled: suite.record("cancelled")
            onCompletionRequested: suite.record("completion")
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

            // --- accepting the completion ---------------------------------
            // No key is bound to this since Tab became a move key; the field
            // API is still what does the writing.
            frame.inputItem.text = "ste";
            frame.acceptCompletion();
            suite.check("acceptCompletion writes the completion", frame.inputItem.text, "Steam");
            suite.check("acceptCompletion leaves the caret at the end", frame.inputItem.cursorPosition, 5);

            // --- the keymap -----------------------------------------------
            suite.check("Tab moves down", suite.pressed(Qt.Key_Tab, Qt.NoModifier), "down");
            suite.check("Shift+Tab moves up",
                suite.pressed(Qt.Key_Tab, Qt.ShiftModifier), "up");
            suite.check("Backtab moves up",
                suite.pressed(Qt.Key_Backtab, Qt.ShiftModifier), "up");
            suite.check("Down still moves down", suite.pressed(Qt.Key_Down, Qt.NoModifier), "down");
            suite.check("Ctrl+n still moves down",
                suite.pressed(Qt.Key_N, Qt.ControlModifier), "down");
            suite.check("Up still moves up", suite.pressed(Qt.Key_Up, Qt.NoModifier), "up");
            suite.check("Enter accepts", suite.pressed(Qt.Key_Return, Qt.NoModifier), "accepted");
            suite.check("Esc cancels", suite.pressed(Qt.Key_Escape, Qt.NoModifier), "cancelled");
            // "down" alone, not "down+completion": Tab moves and does nothing
            // else. A plain letter is consumed by neither.
            suite.check("a plain letter is left to the field",
                frame.handleKey(Qt.Key_A, Qt.NoModifier), false);

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
