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
//       icon:    string   Image source, or "" for none
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

    // ---------------------------------------------------------------- icons

    // Generic stand-ins, in preference order. Not every theme ships all of
    // these -- application-x-executable is absent from plenty of them -- so
    // each is probed rather than assumed.
    readonly property var iconFallbacks: [
        "application-x-executable",
        "application-default-icon",
        "applications-other",
        "system-run",
        "exec"
    ]

    // Quickshell's icon provider never fails: an unknown name yields a blank
    // 100x100 image with status Ready, so Image.status cannot be used to
    // detect a miss. hasThemeIcon is the only reliable gate, and it has to run
    // before the source is built.
    //
    // Returns "" when nothing resolves, which is ResultItem's cue to draw a
    // placeholder. A missing icon never renders as blank space.
    function resolveIcon(name: string): string {
        if (!name) return root.genericIcon();

        // Some desktop entries name an absolute path rather than a theme icon.
        if (name.startsWith("/")) return "file://" + name;

        if (Quickshell.hasThemeIcon(name)) return Quickshell.iconPath(name);
        return root.genericIcon();
    }

    // hasThemeIcon is the most expensive call in the codebase: it walks the
    // icon theme on disk, and a cold lookup costs several milliseconds.
    // Measured on a 104-application machine, resolving every entry up front
    // cost 704ms -- all of it on the main thread, all of it before the window
    // could paint, and all but a handful of it for rows nobody would see.
    //
    // So `entry.icon` is installed as a getter instead of a value. The lookup
    // happens the first time something reads it -- which is ResultList binding
    // a visible row's iconSource -- and the answer is kept. Startup pays for
    // the rows on screen and nothing else.
    //
    // The result is cached rather than recomputed per read because the getter
    // sits under a binding: `iconSource: row.entry.icon` re-reads on every
    // scroll step, and an uncached getter would put the disk walk back.
    function defineIcon(entry: var, name: string) {
        let resolved = null;

        Object.defineProperty(entry, "icon", {
            enumerable: true,
            configurable: true,
            get: function() {
                if (resolved === null) resolved = root.resolveIcon(name);
                return resolved;
            }
        });
    }

    // "" is a legitimate answer -- no theme, no fallback, draw the
    // placeholder -- so the miss is tracked with its own flag rather than by
    // testing the cache for emptiness and re-probing every time.
    property string genericIconCache: ""
    property bool genericIconResolved: false

    function genericIcon(): string {
        if (root.genericIconResolved) return root.genericIconCache;

        root.genericIconResolved = true;
        for (let i = 0; i < root.iconFallbacks.length; i++) {
            if (Quickshell.hasThemeIcon(root.iconFallbacks[i])) {
                root.genericIconCache = Quickshell.iconPath(root.iconFallbacks[i]);
                break;
            }
        }
        return root.genericIconCache;
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
                // Callers that want theme resolution hand the raw name to
                // defineIcon; anything set here is already a source.
                "icon": fields.icon || "",
                "id": fields.id,
                "source": root,
                "payload": fields.payload,
                "confirm": fields.confirm === true,
                "value": fields.value !== undefined ? fields.value : fields.name
            }
        };
    }
}
