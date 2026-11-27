// Headless assertions for ResultRows: rows built below the fold hold their
// icon lookup back until they scroll into view, and keep the icon once it has
// been requested; keyboard reveal brings a row (and, for the first, the
// section header) into view.
//
// Run through tests/run.sh. A ListView only lays out inside a window, so the
// list sits in a FloatingWindow on the offscreen platform.
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

    // Far more rows than the window shows or cacheBuffer builds.
    readonly property var entries: {
        const list = [];
        for (let i = 0; i < 40; i++) {
            list.push({
                "name": "App " + i,
                "source": {"providerId": "drun"},
                "payload": {"icon": "application-x-executable"}
            });
        }
        return list;
    }

    FloatingWindow {
        implicitWidth: Theme.panelWidth
        implicitHeight: Theme.resultsHeight

        ResultRows {
            id: rows
            anchors.fill: parent
            entries: suite.entries
            title: "Suggestions"
        }
    }

    // The row delegate at `index`, or null if none is built.
    function rowAt(index: int): var {
        const items = rows.view.contentItem.children;
        for (let i = 0; i < items.length; i++) {
            if (items[i].index === index && items[i].iconActive !== undefined) return items[i];
        }
        return null;
    }

    // The AppIcon in the row at `index`, or null if no row is built.
    function iconAt(index: int): var {
        const row = suite.rowAt(index);
        return row ? row.iconItem : null;
    }

    // The first row that starts below the visible part of the list.
    readonly property int belowFold: Math.ceil((rows.view.height - Theme.sectionHeight) / rows.step)

    property int step: 0

    Timer {
        interval: 300
        repeat: true
        running: true
        onTriggered: {
            if (suite.step === 0) {
                suite.check("the list starts at its header",
                    rows.view.contentY, -Theme.sectionHeight);
                const row = suite.rowAt(0);
                suite.check("a row shows its name", row && row.modelData.name, "App 0");
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
                rows.view.contentY = 4 * rows.step;
            } else if (suite.step === 1) {
                const shown = suite.iconAt(suite.belowFold);
                suite.check("row scrolled into view requests its icon", shown && shown.requested, true);
                suite.check("its source is resolved", shown && shown.source !== "", true);
                rows.reveal(0);
            } else {
                const kept = suite.iconAt(suite.belowFold);
                suite.check("scrolled back out, the icon stays requested", kept && kept.requested, true);
                suite.check("revealing the first row brings the header back",
                    rows.view.contentY, rows.view.originY);

                console.log(suite.failures === 0
                    ? "PASS"
                    : "FAIL (" + suite.failures + ")");
                Qt.exit(suite.failures === 0 ? 0 : 1);
            }
            suite.step += 1;
        }
    }
}
