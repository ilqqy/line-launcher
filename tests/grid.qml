// Headless assertions for AppGrid's lazy icon loading: tiles built below the
// fold hold their icon lookup back until their row scrolls into view, and
// keep the icon once it has been requested.
//
// Run through tests/run.sh. A GridView only lays out inside a window, so the
// grid sits in a FloatingWindow on the offscreen platform.
import QtQuick
import Quickshell

ShellRoot {
    id: suite

    property int failures: 0

    function check(label: string, actual: var, expected: var) {
        const ok = String(actual) === String(expected);
        if (!ok) suite.failures += 1;
        console.log((ok ? "ok   " : "FAIL ") + label
            + (ok ? "" : "  expected " + expected + ", got " + actual));
    }

    // Eight rows: the window shows Theme.gridVisibleRows of them, and
    // cacheBuffer builds two more below.
    readonly property var entries: {
        const list = [];
        for (let i = 0; i < 8 * Theme.gridColumns; i++) {
            list.push({
                "name": "App " + i,
                "payload": {"icon": "application-x-executable"}
            });
        }
        return list;
    }

    FloatingWindow {
        implicitWidth: Theme.gridWidth
        implicitHeight: Theme.resultsHeight

        AppGrid {
            id: grid
            anchors.fill: parent
            entries: suite.entries
        }
    }

    // The AppIcon inside the tile at `index`, or null if no tile is built.
    function iconAt(index: int): var {
        const tiles = grid.view.contentItem.children;
        for (let i = 0; i < tiles.length; i++) {
            const tile = tiles[i];
            if (tile.index !== index || tile.iconActive === undefined) continue;
            for (let j = 0; j < tile.children.length; j++) {
                if (tile.children[j].requested !== undefined) return tile.children[j];
            }
        }
        return null;
    }

    readonly property int belowFold: Math.ceil(Theme.gridVisibleRows) * Theme.gridColumns

    property int step: 0

    Timer {
        interval: 300
        repeat: true
        running: true
        onTriggered: {
            if (suite.step === 0) {
                const first = suite.iconAt(0);
                const partial = suite.iconAt(suite.belowFold - 1);
                const hidden = suite.iconAt(suite.belowFold);
                suite.check("first row is built", first !== null, true);
                suite.check("first row requests its icon", first && first.requested, true);
                suite.check("partly visible row requests its icon", partial && partial.requested, true);
                suite.check("row below the fold is built by cacheBuffer", hidden !== null, true);
                suite.check("row below the fold holds its icon back", hidden && hidden.requested, false);
                suite.check("a held-back icon is not reported missing", hidden && hidden.missing, false);
                suite.check("a held-back icon has no source", hidden && hidden.source, "");
                grid.view.contentY = 2 * Theme.cellHeight;
            } else if (suite.step === 1) {
                const shown = suite.iconAt(suite.belowFold);
                suite.check("row scrolled into view requests its icon", shown && shown.requested, true);
                suite.check("its source is resolved", shown && shown.source !== "", true);
                grid.view.contentY = 0;
            } else {
                const kept = suite.iconAt(suite.belowFold);
                suite.check("scrolled back out, the icon stays requested", kept && kept.requested, true);

                console.log(suite.failures === 0
                    ? "PASS"
                    : "FAIL (" + suite.failures + ")");
                Qt.exit(suite.failures === 0 ? 0 : 1);
            }
            suite.step += 1;
        }
    }
}
