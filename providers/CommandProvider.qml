import QtQuick
import Quickshell
import Quickshell.Io
import "root:/" as Root

// Arbitrary shell commands. They participate in the normal combined search,
// while the optional ">" prefix still switches to command-only mode.
//
// The list shows previously executed commands, matched against whatever
// follows the ">". The typed command itself is always offered first, so a
// plain Enter runs exactly what was typed; navigating down runs a history
// entry instead.
Provider {
    id: root

    providerId: "command"
    prefix: ">"
    participatesWithoutPrefix: true

    // Its own history lives in history.json, so command launches stay out of
    // the shared drun cache.
    usesDrunHistory: false

    // Most recent first, rather than rofi's alphabetical order.
    orderWhenEmpty: "asIs"

    // A provider may claim its own accent while its prefix is active. Left
    // transparent by default, i.e. no claim; see Config.commandAccent.
    accent: Root.Config.commandAccent

    readonly property int historyLimit: 200

    property var history: []

    readonly property string historyPath: Root.Config.stateDir + "/history.json"

    FileView {
        id: historyFile

        path: root.historyPath
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        printErrors: false

        onLoaded: root.loadHistory()
        onLoadFailed: root.history = []
    }

    function loadHistory() {
        try {
            const text = historyFile.text();
            if (!text || text.trim() === "") {
                root.history = [];
                return;
            }
            const parsed = JSON.parse(text);
            root.history = Array.isArray(parsed)
                ? parsed.filter(entry => typeof entry === "string")
                : [];
        } catch (e) {
            root.history = [];
        }
    }

    function remember(command: string) {
        const trimmed = command.trim();
        if (trimmed === "") return;

        const next = [trimmed].concat(root.history.filter(entry => entry !== trimmed));
        root.history = next.slice(0, root.historyLimit);
        historyFile.setText(JSON.stringify(root.history));
    }

    function candidates(text: string): var {
        const typed = text.trim();
        const out = [];

        // The typed command comes first, unless history already holds it
        // verbatim -- in which case the history entry is the same thing and a
        // second row would just be a duplicate.
        if (typed !== "" && root.history.indexOf(typed) < 0) {
            out.push(root.candidate({
                "name": typed,
                "id": "command:" + typed,
                "payload": typed
            }));
        }

        for (let i = 0; i < root.history.length; i++) {
            const entry = root.history[i];
            out.push(root.candidate({
                "name": entry,
                "id": "command:" + entry,
                "payload": entry
            }));
        }

        return out;
    }

    function activate(payload: var) {
        root.remember(payload);
        root.runShell(payload, false);
    }
}
