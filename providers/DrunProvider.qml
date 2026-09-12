import QtQuick
import Quickshell
import "../rofi-search.js" as RofiSearch
import "root:/" as Root

// Applications, from Quickshell's own DesktopEntries index. No .desktop
// parsing happens here.
Provider {
    id: root

    providerId: "drun"

    // This binding is load-bearing, not decorative: DesktopEntries only starts
    // its scan once something binds to `applications`. Reading it imperatively
    // at startup returns an empty model, however long you wait.
    readonly property var applications: DesktopEntries.applications

    Connections {
        target: DesktopEntries
        function onApplicationsChanged() {
            root.reloadCounter += 1;
        }
    }

    property int reloadCounter: 0

    readonly property var entries: {
        root.reloadCounter;
        const all = Array.from(root.applications.values);
        const seen = new Set();
        return all.filter(entry => {
            if (entry.noDisplay || seen.has(entry.id)) return false;
            seen.add(entry.id);
            return true;
        });
    }

    // prepareApplication pulls out exactly the fields rofi's drun-match-fields
    // covers: name, generic, exec, categories, keywords, comment.
    readonly property var prepared: root.entries.map(entry => {
        const record = RofiSearch.prepareApplication(entry);

        // rofi keys its history on the desktop id, so the id is kept verbatim
        // -- pointing Config.drunCache at ~/.cache/rofi3.druncache shares
        // launch history with rofi itself.
        record.entry = {
            "name": entry.name,
            "id": entry.id,
            "source": root,
            "payload": entry,
            "confirm": false,
            "value": entry.name
        };

        return record;
    })

    function candidates(text: string): var {
        return root.prepared;
    }

    function activate(payload: var) {
        if (payload.runInTerminal) {
            // execute() does not know about Config.terminal, so terminal
            // entries take the explicit path.
            const command = payload.command;
            if (!command || command.length === 0) {
                console.warn("line-launcher: desktop entry has no command:", payload.id);
                return;
            }
            root.run(Array.from(command), true);
            return;
        }

        payload.execute();
    }
}
