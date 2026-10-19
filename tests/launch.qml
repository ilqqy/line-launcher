// Every launch path, end to end: the real providers' activate(), through
// launch-app.sh, to a program that records what it was given.
//
// Run through tests/run.sh, which prepares $LINE_LAUNCHER_TEST_LAUNCH:
// `record` (writes its argv, cwd and one inherited variable to
// $RECORD_DIR/<first argument>), `fake-term` (logs its argv, then runs what
// follows -e), .desktop fixtures and a config naming both. A fake
// systemd-run on PATH and a stand-in user-manager socket send the wrapper
// down its scope path: the fake logs "<description>|<unit>" to
// $SYSTEMD_RUN_LOG and runs the command. tests/launch-wrapper.sh covers the
// wrapper's own arguments and fallbacks.
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

    readonly property string dir: Quickshell.env("LINE_LAUNCHER_TEST_LAUNCH") || ""
    readonly property string recordDir: suite.dir + "/out"

    DrunProvider {
        id: drun
    }
    ActionsProvider {
        id: actions
    }
    CommandProvider {
        id: commands
    }

    FileView {
        id: reader
        blockLoading: true
        printErrors: false
    }

    // The file's lines, or null while it does not exist.
    function lines(path: string): var {
        reader.path = "";
        reader.path = path;
        const text = reader.text();
        return text === "" ? null : text.split("\n").filter(line => line !== "");
    }

    function entry(id: string): var {
        return drun.entries.find(e => e.id === id) || null;
    }

    function action(name: string): var {
        const record = actions.prepared.find(r => r.entry.name === name);
        return record ? record.entry.payload : null;
    }

    readonly property string wrapper: Quickshell.shellPath("launch-app.sh")

    property int step: 0
    property double deadline: Date.now() + 5000

    Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            if (suite.step === 0) {
                // Wait for the fixture entries to be scanned.
                if ((!suite.entry("bench-plain") || !suite.entry("bench-term")) && Date.now() < suite.deadline) return;
                suite.check("fixture entries scanned", !!suite.entry("bench-plain") && !!suite.entry("bench-term"), true);

                suite.check("argv: the wrapper in front, labelled",
                    JSON.stringify(drun.launchCommand(["app", "x"], false, {"id": "i", "name": "N"})),
                    JSON.stringify(["sh", suite.wrapper, "--id", "i", "--name", "N", "--", "app", "x"]));
                suite.check("argv: the terminal inside the wrapper",
                    JSON.stringify(drun.launchCommand(["app"], true, {"id": "i", "name": "N"})),
                    JSON.stringify(["sh", suite.wrapper, "--id", "i", "--name", "N", "--",
                        suite.dir + "/fake-term", "-e", "app"]));

                drun.activate(suite.entry("bench-plain"));
                drun.activate(suite.entry("bench-term"));
                actions.activate(suite.action("Bench Action"));
                actions.activate(suite.action("Bench Terminal Action"));
                commands.activate(suite.dir + "/record command x 'y z'");
                // Forks a child and exits at once, like a daemonizing app.
                commands.activate("(sleep 0.3; " + suite.dir + "/record forked) &");

                suite.deadline = Date.now() + 5000;
                suite.step = 1;
                return;
            }

            const names = ["drun", "drun-term", "action", "action-term", "command", "forked"];
            const missing = names.filter(name => suite.lines(suite.recordDir + "/" + name) === null);
            if (missing.length > 0 && Date.now() < suite.deadline) return;
            suite.check("every launch ran", missing.join(","), "");

            const env = "env=from the launcher";
            const drunOut = suite.lines(suite.recordDir + "/drun") || [];
            suite.check("app: Exec arguments, quoted one intact, %U dropped",
                drunOut.filter(l => l.startsWith("arg=")).join("|"), "arg=drun|arg=two words");
            suite.check("app: started in its Path=", drunOut.indexOf("cwd=" + suite.dir + "/pathdir") >= 0, true);
            suite.check("app: inherits the launcher's environment", drunOut.indexOf(env) >= 0, true);

            const term = (suite.lines(suite.dir + "/terminal.log") || []).sort();
            suite.check("terminal app and terminal action go through Config.terminal",
                term.join("|"),
                ["-e " + suite.dir + "/record drun-term",
                 "-e sh -c " + suite.dir + "/record action-term"].sort().join("|"));

            suite.check("action: shell command with its arguments",
                (suite.lines(suite.recordDir + "/action") || []).filter(l => l.startsWith("arg=")).join("|"),
                "arg=action|arg=a b");
            suite.check("> command: run by sh with its arguments",
                (suite.lines(suite.recordDir + "/command") || []).filter(l => l.startsWith("arg=")).join("|"),
                "arg=command|arg=x|arg=y z");
            suite.check("a command that forks and exits: the child still runs",
                (suite.lines(suite.recordDir + "/forked") || []).indexOf("arg=forked") >= 0, true);

            // Every launch went through launch-app.sh's scope, labelled.
            const scopes = (suite.lines(Quickshell.env("SYSTEMD_RUN_LOG")) || []).map(line => line.split("|"));
            const described = scopes.map(scope => scope[0]).sort().join(" / ");
            suite.check("every launch got a scope, named for what it runs", described, [
                "(sleep 0.3; " + suite.dir + "/record forked) &",
                suite.dir + "/record command x 'y z'",
                "Bench Action", "Bench Plain", "Bench Term", "Bench Terminal Action"
            ].sort().join(" / "));
            const unit = description => (scopes.find(scope => scope[0] === description) || ["", ""])[1];
            suite.check("app scope unit: app-line\\x2dlauncher-<desktop id>-<pid>",
                /^app-line\\x2dlauncher-bench\\x2dplain-[0-9]+\.scope$/.test(unit("Bench Plain")), true);
            suite.check("action scope unit names the action",
                /^app-line\\x2dlauncher-action\\x2dBench\\x20Action-[0-9]+\.scope$/.test(unit("Bench Action")), true);

            console.log(suite.failures === 0 ? "PASS" : "FAIL (" + suite.failures + ")");
            Qt.exit(suite.failures === 0 ? 0 : 1);
        }
    }
}
