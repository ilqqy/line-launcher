// Headless assertions for LauncherPanel.reset(), which the resident launcher
// runs on every show: whatever the last session left behind -- a query, a
// category, scrolled lists, a remembered pointer -- is gone.
//
// Run through tests/run.sh. The views only lay out inside a window, so the
// panel sits in a FloatingWindow on the offscreen platform.
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

    readonly property var categories: [
        "Development", "Education", "Game", "Graphics", "Network", "AudioVideo",
        "Office", "Science", "Settings", "System", "Utility"
    ]

    // Enough results to scroll both the grid and the rows, and every main
    // category, so the chip bar overflows and scrolls too.
    readonly property var results: {
        const list = [];
        for (let i = 0; i < 60; i++) {
            list.push({
                "name": "App " + i,
                "payload": {"icon": "", "categories": [suite.categories[i % suite.categories.length]]}
            });
        }
        return list;
    }

    readonly property var applications: suite.results.map(entry => ({
        "categories": entry.payload.categories
    }))

    FloatingWindow {
        implicitWidth: Theme.panelWidth
        implicitHeight: Theme.panelHeight

        LauncherPanel {
            id: panel
            anchors.fill: parent
            results: suite.results
            applications: suite.applications
        }
    }

    property int step: 0

    Timer {
        interval: 300
        repeat: true
        running: true
        onTriggered: {
            if (suite.step === 0) {
                // Leave a used-looking panel behind.
                panel.field.inputItem.insert(0, "abc");
                panel.category = "development";
                panel.grid.view.contentY = 2 * Theme.cellHeight;
                panel.categoryBar.view.contentX = 150;
                panel.lastPointer = Qt.point(10, 10);
                suite.check("query was typed", panel.text, "abc");
                suite.check("grid was scrolled", panel.grid.view.contentY > 0, true);
                suite.check("chips were scrolled", panel.categoryBar.view.contentX > 0, true);
            } else if (suite.step === 1) {
                panel.reset();
                suite.check("reset clears the query", panel.text, "");
                suite.check("reset returns to All", panel.category, "all");
                suite.check("reset scrolls the grid to the top",
                    panel.grid.view.contentY, panel.grid.view.originY);
                suite.check("reset scrolls the chips to the start",
                    panel.categoryBar.view.contentX,
                    panel.categoryBar.view.originX - panel.categoryBar.view.leftMargin);
                suite.check("reset forgets the pointer", panel.lastPointer.x, -1);
                suite.check("no reselection is left pending", panel.reselectPending, false);

                panel.gridMode = false;
            } else if (suite.step === 2) {
                panel.rows.view.contentY = 3 * panel.rows.step;
                suite.check("rows were scrolled", panel.rows.view.contentY > 0, true);
                panel.reset();
                suite.check("reset scrolls the rows to the top",
                    panel.rows.view.contentY, panel.rows.view.originY);

                console.log(suite.failures === 0
                    ? "PASS"
                    : "FAIL (" + suite.failures + ")");
                Qt.exit(suite.failures === 0 ? 0 : 1);
            }
            suite.step += 1;
        }
    }
}
