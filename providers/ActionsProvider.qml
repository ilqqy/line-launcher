import QtQuick
import Quickshell
import "root:/" as Root

// User-defined actions from config.json, populated by the Nix option
// programs.line-launcher.actions. Ships with none.
//
// These go through the same matcher and the same ranked list as applications
// -- no section, no tab.
Provider {
    id: root

    providerId: "actions"

    readonly property var prepared: {
        const actions = Root.Config.actions;
        const out = [];

        for (let i = 0; i < actions.length; i++) {
            const action = actions[i];
            if (!action || !action.name || !action.exec) continue;

            const record = root.candidate({
                "name": action.name,
                // Matched on like a desktop entry's Exec line, so "poweroff"
                // finds an action named "Power off".
                "exec": action.exec,
                "id": "action:" + action.name,
                "confirm": action.confirm === true,
                "payload": action
            });

            root.defineIcon(record.entry, action.icon);
            out.push(record);
        }

        return out;
    }

    function candidates(text: string): var {
        return root.prepared;
    }

    function activate(payload: var) {
        root.runShell(payload.exec, payload.terminal === true);
    }
}
