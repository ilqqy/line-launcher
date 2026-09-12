// Covers the ported rofi search path: matching, the ranked merge of
// applications with actions, rofi's druncache format, and the provider
// interface the core talks to.
import QtQuick
import Quickshell
import Quickshell.Io
import "providers"
import "rofi-search.js" as RofiSearch

ShellRoot {
    id: suite

    property int failures: 0

    function check(label: string, actual: var, expected: var) {
        const ok = String(actual) === String(expected);
        if (!ok) suite.failures += 1;
        console.log((ok ? "ok   " : "FAIL ") + label
            + (ok ? "" : "  expected " + expected + ", got " + actual));
    }

    property ActionsProvider actions: ActionsProvider {}
    property CommandProvider commands: CommandProvider {}
    property DmenuProvider dmenu: DmenuProvider {available: true}

    // A stand-in for the application set, in the same candidate shape
    // DrunProvider produces.
    function app(name, exec, generic, keywords) {
        return {
            "name": name,
            "genericName": generic || "",
            "exec": exec || "",
            "categories": [],
            "keywords": keywords || [],
            "comment": "",
            "entry": {
                "name": name,
                "icon": "",
                "id": name.toLowerCase().replace(/ /g, "-") + ".desktop",
                "source": null,
                "payload": null,
                "confirm": false,
                "value": name
            }
        };
    }

    readonly property var sampleApps: [
        suite.app("Steam", "steam"),
        suite.app("Volume Control", "pavucontrol", "Volume Control"),
        suite.app("LACT", "lact"),
        suite.app("Firefox", "firefox", "Web Browser", ["browser", "internet"])
    ]

    // Reads the dmenu output file back through a fresh view, so the assertion
    // sees what actually landed on disk rather than what was handed to
    // setText.
    function readBack(): string {
        verify.reload();
        return verify.text();
    }

    property var verifyView: FileView {
        id: verify
        path: Config.dmenuOutputPath
        blockLoading: true
        printErrors: false
    }

    // Mirrors shell.qml's rank() for an empty query.
    function restingOrder(records: var, history: var): var {
        const known = records.filter(record =>
            RofiSearch.historySortIndex(record, history) !== null);
        return RofiSearch.sortApplicationsLikeRofi(known, history)
            .map(record => record.entry);
    }

    function names(results) {
        return results.map(entry => entry.name).join(",");
    }

    readonly property var searchOptions: ({
        "matchingMethod": "normal",
        "normalizeMatch": false,
        "sort": false,
        "sortingMethod": "normal",
        "matchFieldsSpec": "name,generic,exec,categories,keywords",
        "preferNameMatch": true
    })

    function search(text, records, history) {
        const options = {};
        for (const key in suite.searchOptions) options[key] = suite.searchOptions[key];
        options.drunHistory = history || {};
        options.useDrunHistory = true;
        return RofiSearch.search(text, records, options);
    }

    Timer {
        interval: 400
        running: true
        onTriggered: {
            // --- rofi matching --------------------------------------------
            suite.check("prefix query finds the app",
                suite.names(suite.search("ste", suite.sampleApps)), "Steam");

            suite.check("empty pattern matches nothing, as in rofi",
                suite.search("", suite.sampleApps).length, 0);

            suite.check("tokenised query matches across a name",
                suite.names(suite.search("volume control", suite.sampleApps)), "Volume Control");

            suite.check("exec field is matched",
                suite.names(suite.search("pavucontrol", suite.sampleApps)), "Volume Control");

            suite.check("keywords are matched",
                suite.names(suite.search("internet", suite.sampleApps)), "Firefox");

            suite.check("a name hit outranks an exec hit",
                suite.names(suite.search("f", suite.sampleApps)).split(",")[0], "Firefox");

            suite.check("negation excludes any matching keyword",
                suite.names(suite.search("-internet", suite.sampleApps)), "LACT,Steam,Volume Control");
            suite.check("negation excludes an executable match even if the name differs",
                suite.names(suite.search("-pavucontrol", suite.sampleApps)), "Firefox,LACT,Steam");
            suite.check("negation works when only an absent field is enabled",
                RofiSearch.search("-browser", [suite.app("Bare", "bare")], {
                    matchFieldsSpec: "keywords"
                }).length, 1);

            // --- history ordering -----------------------------------------
            const history = RofiSearch.parseDrunHistory("2 lact.desktop\n1 steam.desktop\n0 firefox.desktop\n");
            suite.check("history parses to rofi sort indices", history["lact.desktop"], 3);

            suite.check("rofi's own sort is history then alphabetical",
                suite.names(RofiSearch.sortApplicationsLikeRofi(suite.sampleApps, history)
                    .map(record => record.entry)),
                "LACT,Steam,Firefox,Volume Control");

            // shell.qml drops that alphabetical tail. It mirrors this exact
            // pair of calls; the resting order is frecency and nothing else,
            // because alphabetical order just parks the selection on whatever
            // sorts first.
            suite.check("the resting order is frecency only",
                suite.names(suite.restingOrder(suite.sampleApps, history)),
                "LACT,Steam,Firefox");

            suite.check("an untouched entry is absent until it is launched",
                suite.names(suite.restingOrder(suite.sampleApps, history))
                    .indexOf("Volume Control"), -1);

            suite.check("an empty history rests on an empty list",
                suite.restingOrder(suite.sampleApps, ({})).length, 0);

            const afterOne = RofiSearch.parseDrunHistory("0 volume-control.desktop\n");
            suite.check("one launch is enough to populate it",
                suite.names(suite.restingOrder(suite.sampleApps, afterOne)),
                "Volume Control");

            // --- druncache round-trip, rofi's exact format ----------------
            let cache = "";
            cache = RofiSearch.recordDrunLaunch(cache, "steam.desktop");
            suite.check("first launch writes one rebased line", cache, "0 steam.desktop\n");

            cache = RofiSearch.recordDrunLaunch(cache, "lact.desktop");
            suite.check("second launch goes to the top",
                cache, "1 lact.desktop\n0 steam.desktop\n");

            cache = RofiSearch.recordDrunLaunch(cache, "steam.desktop");
            suite.check("relaunch promotes without duplicating",
                cache, "1 steam.desktop\n0 lact.desktop\n");

            // --- actions share the applications' list ---------------------
            const actionRecords = suite.actions.candidates("");
            suite.check("actions come from config.json", actionRecords.length, 2);

            const merged = suite.sampleApps.concat(actionRecords);
            suite.check("action found by name",
                suite.names(suite.search("power", merged)), "Power off");
            suite.check("action found by its exec line",
                suite.names(suite.search("systemctl", merged)), "Power off");
            suite.check("applications and actions rank in one list",
                suite.names(suite.search("l", merged)).indexOf("Lock") >= 0, true);

            const confirmAction = suite.search("power", merged)[0];
            suite.check("confirm survives to the result", confirmAction.confirm, true);
            suite.check("actions opt into shared history",
                suite.actions.usesDrunHistory, true);

            // --- command provider -----------------------------------------
            suite.check("typed command is offered first",
                suite.commands.candidates("htop")[0].entry.name, "htop");
            suite.check("command history is not the drun cache",
                suite.commands.usesDrunHistory, false);
            suite.check("command prefix is >", suite.commands.prefix, ">");
            suite.check("commands also join normal search",
                suite.commands.participatesWithoutPrefix, true);

            const discord = suite.app("Discord", "discord");
            const combinedCommands = [discord].concat(suite.commands.candidates("disc"));
            suite.check("an application ranks above the raw typed command",
                suite.names(suite.search("disc", combinedCommands)), "Discord,disc");
            suite.check("the raw command remains available after the application",
                suite.search("disc", combinedCommands)[1].source.providerId, "command");
            suite.check("a command with no application match is still first",
                suite.names(suite.search("cliphist wipe",
                    suite.commands.candidates("cliphist wipe"))), "cliphist wipe");

            suite.commands.history = ["ls -a", "ls -l", "echo z", "echo a"];
            suite.check("command flags are literal rather than negated",
                suite.names(suite.search("ls -l", suite.commands.candidates("ls -l"))), "ls -l");
            suite.check("typed command precedes alphabetically earlier history",
                suite.names(suite.search("z", suite.commands.candidates("z"))).split(",")[0], "z");
            suite.check("command history retains recency after matching",
                suite.names(suite.search("echo", suite.commands.candidates("echo"))), "echo,echo z,echo a");
            suite.check("regex settings do not reinterpret shell syntax",
                suite.names(RofiSearch.search("printf [", suite.commands.candidates("printf ["), {
                    matchingMethod: "regex"
                })), "printf [");
            suite.check("commands ignore application match-field restrictions",
                suite.names(RofiSearch.search("ls -l", suite.commands.candidates("ls -l"), {
                    matchFieldsSpec: "exec"
                })), "ls -l");

            // --- dmenu ------------------------------------------------------
            suite.dmenu.lines = [
                "plain line",
                "abc123\tthe second column",
                "x\t" + "y".repeat(80)
            ];
            const piped = suite.dmenu.candidates("");
            suite.check("untabbed line displays whole", piped[0].entry.name, "plain line");
            suite.check("tabbed line displays column two", piped[1].entry.name, "the second column");
            suite.check("tabbed line returns the whole line",
                piped[1].entry.value, "abc123\tthe second column");
            suite.check("display truncates at maxCharacters",
                piped[2].entry.name.length, Config.maxCharacters);
            suite.check("truncated line still returns in full",
                piped[2].entry.value.length, 82);
            suite.check("piped order is preserved", suite.dmenu.orderWhenEmpty, "asIs");
            suite.check("dmenu mode detected from the environment", Config.dmenuMode, true);
            suite.check("empty dmenu uses caller order",
                RofiSearch.emptyOrderMode(null, true), "asIs");
            suite.check("empty application search remains history-only",
                RofiSearch.emptyOrderMode(null, false), "history");
            suite.check("a prefixed provider keeps its own empty ordering",
                RofiSearch.emptyOrderMode(suite.commands, false), "asIs");

            // The whole point of dmenu mode: activate writes the original
            // line, not the displayed column, and blockWrites puts it on disk
            // before the process can exit.
            suite.dmenu.activate("beta\tsecond column");
            suite.check("activate writes the original line to the output file",
                JSON.stringify(suite.readBack()), JSON.stringify("beta\tsecond column\n"));

            console.log(suite.failures === 0 ? "PASS" : "FAIL (" + suite.failures + ")");
            Qt.exit(suite.failures === 0 ? 0 : 1);
        }
    }
}
