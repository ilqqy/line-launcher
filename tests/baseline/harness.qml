    // ------------------------------------------------------ baseline harness
    //
    // Appended by tests/baseline/run.sh in place of shell.qml's window
    // section. Everything above this point is shell.qml verbatim, so rank(),
    // the providers, the druncache and rofi-search.js are the real ones. The
    // only stand-ins are the two ids the logic section reaches for in the
    // window: the input (`frame`) and the window itself.

    QtObject {
        id: frame
        property string text: ""
        function focusInput() {}
    }

    QtObject {
        id: window
        property var screen: null
    }

    FileView {
        id: baselineQueries
        path: Quickshell.env("BASELINE_QUERIES") || ""
        blockLoading: true
        printErrors: true
    }

    FileView {
        id: baselineOut
        path: Quickshell.env("BASELINE_OUT") || ""
        blockWrites: true
        atomicWrites: false
        // The output does not exist yet when the view is built.
        printErrors: false
    }

    function baselineProvider(id: string): var {
        for (let i = 0; i < shell.providers.length; i++) {
            if (shell.providers[i].providerId === id) return shell.providers[i];
        }
        return null;
    }

    function baselineEntry(entry: var): var {
        return {
            "name": entry.name,
            "id": entry.id,
            "provider": entry.source ? entry.source.providerId : null
        };
    }

    function baselineRun() {
        const queries = JSON.parse(baselineQueries.text());
        const drun = shell.baselineProvider("drun");

        const catalog = drun.prepared.map(record => ({
            "id": record.entry.id,
            "name": record.name,
            "categories": record.categories.slice().sort()
        }));
        catalog.sort((a, b) => a.id < b.id ? -1 : (a.id > b.id ? 1 : 0));

        const results = [];
        for (let i = 0; i < queries.length; i++) {
            const query = queries[i];
            frame.text = query.query;
            const ranked = shell.ranked;
            const selected = activation.selectedItem;
            results.push({
                "label": query.label,
                "query": query.query,
                "count": ranked.length,
                "enterLaunches": selected ? selected.id : null,
                "ranked": ranked.map(entry => shell.baselineEntry(entry))
            });
        }
        frame.text = "";

        const out = {
            "historyEntries": Object.keys(shell.drunHistory).length,
            "commandHistoryEntries": shell.baselineProvider("command").history.length,
            "actions": shell.baselineProvider("actions").prepared.length,
            "catalogCount": catalog.length,
            "catalog": catalog,
            "results": results
        };
        baselineOut.setText(JSON.stringify(out, null, 2) + "\n");
        console.log("BASELINE DONE " + results.length + " queries, " + catalog.length + " apps");
        Qt.quit();
    }

    // DesktopEntries scans asynchronously. Wait until the application count
    // has held still for half a second, the druncache has been read, and
    // command history is in, then run every query in one pass.
    Timer {
        id: baselineSettle

        property int lastCount: -1
        property int stableTicks: 0
        property int ticks: 0

        interval: 100
        repeat: true
        running: true

        onTriggered: {
            baselineSettle.ticks += 1;
            const count = shell.baselineProvider("drun").prepared.length;
            if (count > 0 && count === baselineSettle.lastCount) baselineSettle.stableTicks += 1;
            else baselineSettle.stableTicks = 0;
            baselineSettle.lastCount = count;

            const ready = baselineSettle.stableTicks >= 5 && drunCacheFile.loaded;
            if (ready || baselineSettle.ticks > 150) {
                baselineSettle.running = false;
                if (!ready) console.warn("BASELINE settle timeout: apps=" + count
                    + " druncacheLoaded=" + drunCacheFile.loaded);
                shell.baselineRun();
            }
        }
    }
}
