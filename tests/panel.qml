// Headless assertions for LauncherPanel: it opens collapsed to the search
// bar, expands to fit the results once there is a query, collapses back when
// the query is cleared, and keeps keys away from hidden results; and reset(),
// which the resident launcher runs on every show, drops whatever the last
// session left behind -- a query, a scrolled list, a remembered pointer.
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

    // Enough results to scroll the list.
    readonly property var results: {
        const list = [];
        for (let i = 0; i < 60; i++)
            list.push({"name": "App " + i, "payload": {"icon": ""}});
        return list;
    }

    FloatingWindow {
        implicitWidth: Theme.panelWidth
        implicitHeight: Theme.panelHeight

        LauncherPanel {
            id: panel
            anchors.fill: parent
            results: suite.results
            onSelectRequested: index => panel.currentIndex = index
            onAccepted: suite.accepts += 1
        }
    }

    property int accepts: 0

    readonly property int expandedHeight: Theme.resultsY + Theme.resultsHeight

    property int step: 0

    Timer {
        interval: 300
        repeat: true
        running: true
        onTriggered: {
            if (suite.step === 0) {
                // Collapsed: only the bar, and keys do not reach the hidden list.
                suite.check("opens collapsed", panel.expanded, false);
                suite.check("collapsed to the search bar",
                    panel.container.height, Theme.searchHeight);
                suite.check("the list is hidden", panel.rows.visible, false);
                suite.check("nothing is selected while collapsed", panel.selected, -1);
                panel.field.handleKey(Qt.Key_Down, Qt.NoModifier, false);
                panel.field.handleKey(Qt.Key_Tab, Qt.NoModifier, false);
                suite.check("Down and Tab do nothing while collapsed", panel.currentIndex, 0);
                panel.field.handleKey(Qt.Key_Return, Qt.NoModifier, false);
                suite.check("Enter does nothing while collapsed", suite.accepts, 0);

                // Leave a used-looking panel behind.
                panel.field.inputItem.insert(0, "abc");
                suite.check("a query expands", panel.expanded, true);
                panel.lastPointer = Qt.point(10, 10);
            } else if (suite.step === 1) {
                suite.check("expanded to the full list height",
                    panel.container.height, suite.expandedHeight);
                suite.check("the list is shown", panel.rows.visible, true);
                suite.check("the list keeps its full height", panel.rows.height, Theme.resultsHeight);

                // One list for everything: Tab and the arrows walk it.
                panel.field.handleKey(Qt.Key_Tab, Qt.NoModifier, false);
                suite.check("Tab selects the next result", panel.currentIndex, 1);
                panel.field.handleKey(Qt.Key_Down, Qt.NoModifier, false);
                suite.check("Down selects the next result", panel.currentIndex, 2);
                panel.field.handleKey(Qt.Key_Backtab, Qt.ShiftModifier, false);
                suite.check("Shift+Tab selects the previous result", panel.currentIndex, 1);
                panel.field.handleKey(Qt.Key_PageDown, Qt.NoModifier, false);
                suite.check("PageDown moves a page", panel.currentIndex, 1 + Theme.listPageRows);
                panel.field.handleKey(Qt.Key_Return, Qt.NoModifier, false);
                suite.check("Enter accepts while expanded", suite.accepts, 1);

                // Clearing the query collapses and starts the list over.
                panel.field.inputItem.clear();
                suite.check("clearing the query collapses", panel.expanded, false);
                suite.check("collapsing selects the first result", panel.currentIndex, 0);
                suite.check("collapsing scrolls the list to the top",
                    panel.rows.view.contentY, panel.rows.view.originY);
                suite.check("whitespace alone stays collapsed",
                    (panel.field.inputItem.insert(0, "  "), panel.expanded), false);
                panel.field.inputItem.clear();
            } else if (suite.step === 2) {
                suite.check("collapsed back to the search bar",
                    panel.container.height, Theme.searchHeight);

                // A query, then reset: collapsed at once, not animated.
                panel.field.inputItem.insert(0, "abc");
                panel.rows.view.contentY = 3 * panel.rows.step;
                panel.lastPointer = Qt.point(10, 10);
            } else if (suite.step === 3) {
                panel.reset();
                suite.check("reset clears the query", panel.text, "");
                suite.check("reset collapses without animating",
                    panel.container.height, Theme.searchHeight);
                suite.check("reset scrolls the list to the top",
                    panel.rows.view.contentY, panel.rows.view.originY);
                suite.check("reset forgets the pointer", panel.lastPointer.x, -1);

                // The panel grows only as far as the results need.
                panel.field.inputItem.insert(0, "abc");
                panel.results = suite.results.slice(0, 3);
            } else if (suite.step === 4) {
                suite.check("three results take three rows",
                    panel.container.height,
                    Theme.resultsY + 2 * Theme.listPaddingY + Theme.sectionHeight + 3 * Theme.rowHeight);
                panel.results = [];
            } else if (suite.step === 5) {
                suite.check("no results leave room for the message",
                    panel.container.height, Theme.resultsY + Theme.emptyHeight);

                // Piped menus and ">" commands show their list with no query.
                panel.results = suite.results;
                panel.field.inputItem.clear();
                panel.appMode = false;
                suite.check("a menu is shown without a query", panel.expanded, true);
            } else if (suite.step === 6) {
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
