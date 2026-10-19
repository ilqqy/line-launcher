// The application list refreshes while the launcher runs -- what a resident
// launcher relies on to see applications installed after it started.
//
// Run through tests/run.sh, which points XDG_DATA_HOME and XDG_DATA_DIRS at
// fixtures under $LINE_LAUNCHER_TEST_XDG: `plain/` holds a .desktop file, and
// `profile` is a symlink to `gen1`, switched the way a Nix profile switch
// replaces it. DrunProvider is the real one, on Quickshell's DesktopEntries.
import QtQuick
import Quickshell
import Quickshell.Io
import "providers"

ShellRoot {
    id: suite

    property int failures: 0

    function check(label: string, actual: var, expected: var) {
        const ok = String(actual) === String(expected);
        if (!ok) suite.failures += 1;
        console.log((ok ? "ok   " : "FAIL ") + label
            + (ok ? "" : "  expected " + expected + ", got " + actual));
    }

    readonly property string xdg: Quickshell.env("LINE_LAUNCHER_TEST_XDG") || ""

    DrunProvider {
        id: drun
    }

    function ids(): string {
        return drun.entries.map(entry => entry.id).sort().join(",");
    }

    function entry(name: string): string {
        return "[Desktop Entry]\nType=Application\nName=" + name + "\nExec=true\n";
    }

    Process {
        id: runner
    }

    function run(script: string) {
        runner.command = ["sh", "-c", script];
        runner.running = true;
    }

    // Each step makes a change, then waits (up to 5s) for the list it expects.
    readonly property var steps: [
        {
            "label": "initial scan sees the plain dir and the profile",
            "expect": "one,two"
        },
        {
            "label": "a .desktop file dropped into a watched dir appears",
            "write": ["plain/applications/three.desktop", "Three"],
            "expect": "one,three,two"
        },
        {
            "label": "a profile switch (symlink replaced) is picked up",
            "switchProfile": true,
            "expect": "four,one,three"
        },
        {
            "label": "a removed .desktop file disappears",
            "remove": "plain/applications/three.desktop",
            "expect": "four,one"
        }
    ]

    property int step: 0
    property double deadline: 0
    property bool waiting: false

    Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            if (suite.step >= suite.steps.length) {
                console.log(suite.failures === 0 ? "PASS" : "FAIL (" + suite.failures + ")");
                Qt.exit(suite.failures === 0 ? 0 : 1);
                return;
            }

            const step = suite.steps[suite.step];
            if (!suite.waiting) {
                if (step.write) {
                    suite.run("printf '%s' '" + suite.entry(step.write[1]) + "' >'"
                        + suite.xdg + "/" + step.write[0] + "'");
                } else if (step.switchProfile) {
                    // Like a Nix profile switch: a new generation, then an
                    // atomic rename over the old symlink.
                    suite.run("cd '" + suite.xdg + "' && mkdir -p gen2/share/applications"
                        + " && printf '%s' '" + suite.entry("Four") + "' >gen2/share/applications/four.desktop"
                        + " && ln -s gen2 profile.new && mv -T profile.new profile");
                } else if (step.remove) {
                    suite.run("rm -- '" + suite.xdg + "/" + step.remove + "'");
                }
                suite.deadline = Date.now() + 5000;
                suite.waiting = true;
                return;
            }

            if (suite.ids() !== step.expect && Date.now() < suite.deadline) return;
            suite.check(step.label, suite.ids(), step.expect);
            suite.waiting = false;
            suite.step += 1;
        }
    }
}
