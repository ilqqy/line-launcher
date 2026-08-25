import QtQuick
import Quickshell
import Quickshell.Io
import "root:/" as Root

// dmenu replacement. Active only when launcher.sh found stdin was not a tty
// and staged the piped lines into a file; the application providers switch
// themselves off in that case.
//
// A line containing tabs displays its second tab-separated column but returns
// the whole original line, matching rofi's -display-columns 2.
Provider {
    id: root

    providerId: "dmenu"
    available: Root.Config.dmenuMode

    // Line positions mean nothing across runs, and piped menus should come out
    // in the order they were piped in.
    usesDrunHistory: false
    orderWhenEmpty: "asIs"

    property var lines: []

    FileView {
        id: input

        path: Root.Config.dmenuInputPath
        blockLoading: true
        printErrors: false

        onLoaded: root.loadLines()
        onLoadFailed: root.lines = []
    }

    FileView {
        id: output

        path: Root.Config.dmenuOutputPath
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        printErrors: true
    }

    function loadLines() {
        const text = input.text();
        if (!text) {
            root.lines = [];
            return;
        }

        // A trailing newline is a line terminator, not an empty final entry.
        const raw = text.split("\n");
        if (raw.length > 0 && raw[raw.length - 1] === "") raw.pop();
        root.lines = raw;
    }

    function displayFor(line: string): string {
        const columns = line.split("\t");
        const shown = columns.length > 1 ? columns[1] : line;

        return shown.length > Root.Config.maxCharacters
            ? shown.substring(0, Root.Config.maxCharacters - 1) + "…"
            : shown;
    }

    readonly property var prepared: root.lines.map((line, index) => {
        const display = root.displayFor(line);
        // Matched against what is displayed, so the search agrees with what
        // the user can actually see.
        return root.candidate({
            "name": display,
            "id": "dmenu:" + index,
            "payload": line,
            "value": line
        });
    })

    function candidates(text: string): var {
        return root.prepared;
    }

    function activate(payload: var) {
        if (Root.Config.dmenuOutputPath === "") {
            console.warn("line-launcher: dmenu mode with no output path");
            return;
        }
        // blockWrites means this is on disk before the process exits, which is
        // what lets the wrapper cat it straight after qs returns.
        output.setText(payload + "\n");
    }
}
