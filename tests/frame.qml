// Headless assertions for Config, Theme and the SearchField keymap.
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

        SearchField {
            id: frame
            width: host.width
            height: implicitHeight

            onMoveUp: suite.record("up")
            onMoveDown: suite.record("down")
            onMoveLeft: suite.record("left")
            onMoveRight: suite.record("right")
            onPageUp: suite.record("pageup")
            onPageDown: suite.record("pagedown")
            onNextCategory: suite.record("next")
            onPreviousCategory: suite.record("previous")
            onAccepted: suite.record("accepted")
            onCancelled: suite.record("cancelled")
        }
    }

    Timer {
        interval: 400
        running: true
        onTriggered: {
            // --- config layering ------------------------------------------
            suite.check("frameWidth from config.json", Config.frameWidth, 300);
            suite.check("frameHeight default", Config.frameHeight, 44);
            suite.check("frameFillOpacity default", Config.frameFillOpacity, 0.42);
            suite.check("topMargin default", Config.topMargin, 36);
            suite.check("whiskerLength default", Config.whiskerLength, 120);
            suite.check("hookLength default", Config.hookLength, 16);
            suite.check("visibleItems from --items", Config.visibleItems, 9);
            suite.check("prompt from --prompt", Config.prompt, "run:");

            // --- colours --------------------------------------------------
            suite.check("foreground from colorsFile", Theme.foreground, "#00ff00");
            suite.check("accent from accentKey", Theme.accent, "#0000ff");
            suite.check("danger falls back to color1", Theme.danger, "#ff0000");
            suite.check("muted is foreground at 0.45", Theme.muted.a.toFixed(2), "0.45");
            suite.check("unselected results stay strongly readable",
                Theme.resultMuted.a.toFixed(2), "0.90");
            suite.check("result shadow opposes result text",
                Theme.resultBackdrop.hslLightness.toFixed(0),
                Theme.resultForeground.hslLightness > 0.5 ? "0" : "1");
            suite.check("activeAccent tracks accent", Theme.activeAccent, Theme.accent);

            // --- the keymap -----------------------------------------------
            // Without category chips (dmenu, ">" commands) Tab keeps moving
            // the selection, and arrows are left to the text field.
            frame.tabCyclesCategories = false;
            frame.arrowsNavigate = false;
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
            // A plain letter is consumed by neither.
            suite.check("a plain letter is left to the field",
                frame.handleKey(Qt.Key_A, Qt.NoModifier), false);
            suite.check("Left is left to the field without a grid",
                frame.handleKey(Qt.Key_Left, Qt.NoModifier), false);
            suite.check("PageDown pages", suite.pressed(Qt.Key_PageDown, Qt.NoModifier), "pagedown");
            suite.check("PageUp pages", suite.pressed(Qt.Key_PageUp, Qt.NoModifier), "pageup");

            // With chips and a non-empty grid, Tab walks the categories and
            // plain Left/Right walk the grid; Shift/Ctrl+arrows still edit.
            frame.tabCyclesCategories = true;
            frame.arrowsNavigate = true;
            suite.check("Tab cycles categories", suite.pressed(Qt.Key_Tab, Qt.NoModifier), "next");
            suite.check("Shift+Tab cycles back",
                suite.pressed(Qt.Key_Tab, Qt.ShiftModifier), "previous");
            suite.check("Backtab cycles back",
                suite.pressed(Qt.Key_Backtab, Qt.ShiftModifier), "previous");
            suite.check("Left moves in the grid", suite.pressed(Qt.Key_Left, Qt.NoModifier), "left");
            suite.check("Right moves in the grid", suite.pressed(Qt.Key_Right, Qt.NoModifier), "right");
            suite.check("Shift+Left is left to the field",
                frame.handleKey(Qt.Key_Left, Qt.ShiftModifier), false);
            suite.check("Ctrl+Right is left to the field",
                frame.handleKey(Qt.Key_Right, Qt.ControlModifier), false);
            suite.check("Down still moves down in the grid",
                suite.pressed(Qt.Key_Down, Qt.NoModifier), "down");

            // --- resident --------------------------------------------------
            suite.check("resident flag is set by the runner",
                Quickshell.env("LINE_LAUNCHER_RESIDENT"), "1");
            suite.check("a piped menu is never resident", Config.resident, false);

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
