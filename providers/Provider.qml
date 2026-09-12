import QtQuick
import Quickshell
import "root:/" as Root

// The one interface every result source implements.
//
// Providers do not score. They hand the core *candidate records* in the shape
// rofi-search.js expects, and the core runs a single RofiSearch.search() over
// the union of them -- so one scorer really does rank everything, and drun and
// actions land in one list rather than two.
//
// A candidate record is:
//
//   {
//     name, genericName, exec, categories, keywords, comment
//         -- the fields rofi matches against
//     entry: {
//       name:    string   displayed, and what the ghost completion reads
//       id:      string   stable identity; also the rofi history key
//       source:  Provider the provider that produced it
//       payload: var      opaque, handed straight back to source.activate()
//       confirm: bool     optional; the core asks for a second Enter
//       value:   string   optional; what dmenu mode prints instead of `name`
//     }
//   }
//
// The core never inspects `source` beyond calling `activate` on it and reading
// its declared capabilities, so it cannot tell which provider a result came
// from. Adding a source means one file here plus one line in the `providers`
// list in shell.qml; ResultList, ResultItem and SelectionOutline never learn
// about it.
QtObject {
    id: root

    // Children (a FileView, say) go here: QtObject has no default property of
    // its own, so providers that own state would otherwise have nowhere to
    // put it.
    default property list<QtObject> contents

    // Stable identity, only used in logs.
    property string providerId: ""

    // A single character that routes input to this provider exclusively.
    // Empty means the provider takes part in the unprefixed list.
    property string prefix: ""

    // A prefixed provider can also opt into the ordinary combined search.
    // Its prefix still switches to that provider exclusively when typed.
    property bool participatesWithoutPrefix: false

    // Lower values are shown first when multiple providers participate in a
    // combined search. Matching still determines the order within a provider.
    // This keeps an exact copy of the typed shell command from hiding a real
    // application whose name is only a prefix match.
    property int resultPriority: 0

    // Command text uses literal matching and keeps the provider's own order.
    property bool literalMatching: false
    property bool preserveOrder: false

    // Set false to drop out of ranking entirely -- dmenu mode switches the
    // application providers off this way.
    property bool available: true

    // A provider may claim its own accent while its prefix is active. A fully
    // transparent colour means "no claim, use the global accent".
    property color accent: "transparent"

    // Whether launches from this provider belong in the shared rofi drun
    // history. Command history is the provider's own business and dmenu keys
    // are line positions, so both opt out.
    property bool usesDrunHistory: true

    // How to order results when the query is empty: "history" applies rofi's
    // history-then-alphabetical sort, "asIs" keeps the order the provider
    // returned them in.
    property string orderWhenEmpty: "history"

    // Called with the query text, already stripped of the prefix. Returns
    // candidate records; the core matches, ranks and truncates.
    function candidates(text: string): var {
        return [];
    }

    // Run the result. The core has already recorded the history hit.
    function activate(payload: var) {
    }

    // ------------------------------------------------------ launch helpers

    // Config.terminal, then $TERMINAL. Empty when neither is set, in which
    // case terminal entries are run bare rather than not at all.
    function terminalArgv(): var {
        const configured = Root.Config.terminal || Quickshell.env("TERMINAL") || "";
        return configured.split(/\s+/).filter(part => part.length > 0);
    }

    function run(argv: var, inTerminal: bool) {
        if (!argv || argv.length === 0) return;

        let final = argv;
        if (inTerminal) {
            const term = root.terminalArgv();
            if (term.length === 0) {
                console.warn("line-launcher: no terminal configured; running \""
                    + argv.join(" ") + "\" without one");
            } else {
                final = term.concat(argv);
            }
        }

        Quickshell.execDetached(final);
    }

    function runShell(command: string, inTerminal: bool) {
        if (!command || command.trim() === "") return;
        root.run(["sh", "-c", command], inTerminal);
    }

    // ------------------------------------------------------------- helpers

    // Builds a candidate record for sources that have nothing but a name --
    // actions, shell commands, piped lines. DrunProvider goes through
    // RofiSearch.prepareApplication instead, so that applications match on
    // exactly the fields rofi matches on.
    function candidate(fields: var): var {
        return {
            "name": fields.name,
            "genericName": fields.genericName || "",
            "exec": fields.exec || "",
            "categories": fields.categories || [],
            "keywords": fields.keywords || [],
            "comment": fields.comment || "",
            "entry": {
                "name": fields.name,
                "id": fields.id,
                "source": root,
                "payload": fields.payload,
                "confirm": fields.confirm === true,
                "order": fields.order || 0,
                "value": fields.value !== undefined ? fields.value : fields.name
            }
        };
    }
}
