    // ------------------------------------------------------ resident harness
    //
    // Appended by tests/run.sh in place of shell.qml's window section, the
    // same way tests/baseline/run.sh builds the search baseline: everything
    // above this point is shell.qml verbatim, run with LINE_LAUNCHER_RESIDENT=1,
    // so show(), hide(), toggle() and the reset are the real ones. The panel
    // and the window are stubbed; LauncherPanel.reset() itself is covered by
    // tests/panel.qml. Nothing maps a surface here, so `entered` is set by
    // hand where a real show would have set it.

    QtObject {
        id: frame
        property string text: ""
        property int resets: 0
        function focusInput() {}
        function reset() {
            frame.text = "";
            frame.resets += 1;
        }
    }

    QtObject {
        id: window
        property var screen: null
    }

    property int failures: 0

    function check(label: string, actual: var, expected: var) {
        const ok = String(actual) === String(expected);
        if (!ok) shell.failures += 1;
        console.log((ok ? "ok   " : "FAIL ") + label
            + (ok ? "" : "  expected " + expected + ", got " + actual));
    }

    // Another process recording a launch in the shared history file.
    FileView {
        id: historyWriter
        path: Config.drunCachePath
        blockWrites: true
        atomicWrites: true
        printErrors: false
    }

    property int step: 0

    // Longer than either exit animation, so each step starts settled.
    Timer {
        interval: 300
        repeat: true
        running: true
        onTriggered: {
            if (shell.step === 0) {
                shell.check("resident mode is on", Config.resident, true);
                shell.check("the IPC target is enabled", ipc.enabled, true);
                shell.check("starts hidden", shell.shown, false);

                shell.show();
                shell.check("show() shows", shell.shown, true);
                shell.check("show() resolves the screen", shell.screenResolved, true);
                shell.check("show() resets the panel", frame.resets, 1);
                shell.entered = true;

                // A session that leaves state behind, then Esc.
                frame.text = "fire";
                shell.currentIndex = 3;
                activation.armedItem = {"name": "Power off"};
                shell.toggle();
                shell.check("toggle() while open starts the close", shell.closing, shell.closeFade);
                shell.check("still shown during the exit animation", shell.shown, true);
            } else if (shell.step === 1) {
                shell.check("hidden after the exit animation", shell.shown, false);
                shell.check("entrance rearmed", shell.entered, false);
                shell.check("query cleared", frame.text, "");
                shell.check("selection back on the first result", shell.currentIndex, 0);
                shell.check("nothing armed", activation.armedItem, null);
                shell.check("activation unlocked", activation.closing, false);
                shell.check("not closing", shell.closing, shell.closeNone);

                shell.hide();
                shell.check("hide() while hidden does nothing", shell.closing, shell.closeNone);

                shell.toggle();
                shell.check("toggle() while hidden shows", shell.shown, true);
                shell.entered = true;
                shell.toggle();
                shell.check("second toggle() closes", shell.closing, shell.closeFade);
                frame.text = "half typed";
                shell.toggle();
                shell.check("toggle() during the exit cancels it", shell.closing, shell.closeNone);
                shell.check("and stays shown", shell.shown, true);
                shell.check("and starts clean", frame.text, "");
            } else if (shell.step === 2) {
                shell.check("a cancelled exit does not hide later", shell.shown, true);
                const resets = frame.resets;
                shell.show();
                shell.check("show() while open is a no-op", frame.resets, resets);

                historyWriter.setText("7 resident-test.desktop\n");
            } else if (shell.step === 3) {
                shell.check("history written elsewhere is re-read",
                    shell.drunHistory["resident-test.desktop"] !== undefined, true);

                // Key-repeat on the toggle binding: 50 toggles land open.
                for (let i = 0; i < 50; i++) shell.toggle();
                shell.check("50 toggles from open end open", shell.shown && shell.closing === shell.closeNone, true);
                shell.toggle();
            } else {
                shell.check("and the 51st closes it", shell.shown, false);

                console.log(shell.failures === 0
                    ? "PASS"
                    : "FAIL (" + shell.failures + ")");
                Qt.exit(shell.failures === 0 ? 0 : 1);
            }
            shell.step += 1;
        }
    }
}
