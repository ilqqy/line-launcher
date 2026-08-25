// The lane has two states and they must stay distinct.
//
// While the selection is inside the visible window the lane does not move at
// all: laneY stays 0 and every row keeps its position, and only the outline
// travels. Only once the selection would leave the window does the lane scroll,
// with the selection pinned to the bottom edge.
//
// A continuous laneY = -currentIndex * rowStep passes none of this.
import QtQuick
import Quickshell

ShellRoot {
    id: suite

    property int failures: 0

    function near(label: string, actual: real, expected: real, tolerance: real) {
        const ok = Math.abs(actual - expected) <= tolerance;
        if (!ok) suite.failures += 1;
        console.log((ok ? "ok   " : "FAIL ") + label
            + (ok ? "" : "  expected " + expected.toFixed(3)
                + " +-" + tolerance + ", got " + actual.toFixed(3)));
    }

    function check(label: string, actual: var, expected: var) {
        const ok = String(actual) === String(expected);
        if (!ok) suite.failures += 1;
        console.log((ok ? "ok   " : "FAIL ") + label
            + (ok ? "" : "  expected " + expected + ", got " + actual));
    }

    readonly property var rows: {
        const out = [];
        for (let i = 0; i < 20; i++) {
            out.push({
                "name": "Entry " + i,
                "icon": "",
                "id": "entry-" + i,
                "source": null,
                "payload": i,
                "confirm": false,
                "value": "Entry " + i
            });
        }
        return out;
    }

    Item {
        id: host
        width: 800
        height: 700

        ResultList {
            id: list
            width: host.width
            height: implicitHeight
            results: suite.rows
            currentIndex: 0
        }
    }

    // Row geometry sampled at startup, to compare against later.
    property var baseline: []

    function snapshot(): var {
        const out = [];
        for (let i = 0; i < list.visibleItems; i++) out.push(list.rowBaseY(i));
        return out;
    }

    property int phase: 0

    Timer {
        interval: 250
        repeat: true
        running: true

        onTriggered: {
            suite.phase += 1;
            const n = list.visibleItems;

            if (suite.phase === 1) {
                suite.check("lane window matches the configured size", n, Config.visibleItems);
                suite.baseline = suite.snapshot();
                suite.check("lane starts unscrolled", list.laneY, 0);
                suite.check("firstVisible starts at 0", list.firstVisible, 0);
                return;
            }

            // Phases 2..n: the first n-1 Down presses, landing on the last
            // visible row. None of them may move the lane.
            if (suite.phase <= n) {
                const target = suite.phase - 1;
                list.currentIndex = target;

                suite.check("Down " + target + ": lane has not moved", list.laneY, 0);
                suite.check("Down " + target + ": firstVisible unchanged", list.firstVisible, 0);
                suite.check("Down " + target + ": rows unchanged",
                    JSON.stringify(suite.snapshot()), JSON.stringify(suite.baseline));
                suite.check("Down " + target + ": outline target is that row",
                    list.rowBaseY(target) / list.rowStep, target);
                return;
            }

            if (suite.phase === n + 1) {
                // One more Down: now the selection would leave the window, so
                // the lane must start moving and the selection pins to the edge.
                list.currentIndex = n;
                suite.check("Down " + n + ": firstVisible advanced by one",
                    list.firstVisible, 1);
                suite.check("Down " + n + ": lane target is one row step",
                    list.targetLaneY, -list.rowStep);
                suite.check("Down " + n + ": selection pinned to the bottom slot",
                    list.currentIndex - list.firstVisible, n - 1);

                // The outline's target is the pinned slot, taken straight from
                // the selection and the window -- not from rowBaseY(), which is
                // built on the animated laneY. Read one frame into the slide,
                // it is the same number it will be when the slide ends: the
                // outline holds still and the rows travel under it.
                //
                // This is the regression. With the target measured off the
                // lane, it carried the lane's easing error, the outline drifted
                // with every slide, and under a held key it ended up rows away
                // from the selection it was marking.
                suite.check("mid-slide: outline target is the pinned slot, "
                        + "not the lane's position",
                    list.outlineTarget, n - 1);
                suite.check("mid-slide: the lane is genuinely still moving",
                    list.laneY !== list.targetLaneY, true);
                return;
            }

            if (suite.phase === n + 3) {
                // Lane easing has finished by now.
                suite.check("lane settled on the new offset", list.laneY, -list.rowStep);
                suite.check("rows shifted by exactly one step",
                    list.rowBaseY(1), suite.baseline[0]);
                return;
            }

            if (suite.phase === n + 4) {
                // Back up inside the window: the lane comes back and stops.
                list.currentIndex = 0;
                suite.check("moving back rewinds firstVisible", list.firstVisible, 0);
                return;
            }

            if (suite.phase === n + 6) {
                suite.check("lane back at rest", list.laneY, 0);
                suite.check("rows back to their original positions",
                    JSON.stringify(suite.snapshot()), JSON.stringify(suite.baseline));

                // --- the default lane: straight down ---------------------
                //
                // listPerspective defaults to 0, and at 0 the whole projection
                // has to disappear rather than merely shrink: even steps, rows
                // at their untransformed positions, full width at every slot.
                suite.check("lane is flat by default", list.perspective, 0);
                for (let slot = 0; slot < n; slot++) {
                    suite.near("slot " + slot + ": flat row sits on the plain grid",
                        list.projectedCentre(slot),
                        slot * list.rowStep + list.rowHeight / 2, 0.01);
                    suite.near("slot " + slot + ": flat row keeps its full width",
                        list.projectionFor(slot), 1, 0.0001);

                    // The tilt is what the fan puts on a row away from the
                    // selection; flat means a distant row is drawn exactly
                    // where the outline would go for it.
                    suite.near("slot " + slot + ": flat row is untilted",
                        list.projectedRowCentre(slot, 3),
                        slot * list.rowStep + list.rowHeight / 2, 0.01);
                }

                // --- the fan, for anyone who turns it on -------------------
                list.perspective = 1;

                // The perspective must compress the step downwards, and must
                // do so without touching the untransformed positions above.
                const steps = [];
                for (let i = 1; i < n; i++) {
                    steps.push(list.projectedCentre(i) - list.projectedCentre(i - 1));
                }
                let shrinking = true;
                for (let i = 1; i < steps.length; i++) {
                    if (steps[i] >= steps[i - 1]) shrinking = false;
                }
                suite.check("projected step shrinks with distance", shrinking, true);
                suite.check("top row is not displaced by the projection",
                    list.projectedCentre(0), list.rowHeight / 2);

                console.log("     projected steps: "
                    + steps.map(v => v.toFixed(1)).join(", ")
                    + "  (nominal " + list.rowStep + ")");

                // Where the outline is put, and where the row is actually
                // drawn, are computed two entirely different ways:
                // projectedCentre() is a closed form, rowMatrix() is the
                // matrix the scene graph applies. They have to agree at every
                // slot, and at every tilt -- the tilt turns about the row's
                // own centre, so the centre is a fixed point of it and the
                // angle must make no difference at all.
                //
                // This is the assertion the lane did not have. The two drifted
                // apart by 23px at the fourth slot and nothing said a word.
                for (let slot = 0; slot < n; slot++) {
                    for (const distance of [0, -1, 1, 3]) {
                        suite.near("slot " + slot + ", tilt at distance "
                                + distance + ": row centre is where the outline goes",
                            list.projectedRowCentre(slot, distance),
                            list.projectedCentre(slot), 0.01);
                    }
                }

                // Horizontally the vanishing point is the lane's centre line,
                // so a receding row narrows about it rather than sliding off
                // towards one edge.
                for (let slot = 0; slot < n; slot++) {
                    const matrix = list.rowMatrix(slot, 0, list.laneWidth, list.rowHeight);
                    const left = matrix.times(Qt.vector4d(0, list.rowHeight / 2, 0, 1));
                    const right = matrix.times(
                        Qt.vector4d(list.laneWidth, list.rowHeight / 2, 0, 1));

                    suite.near("slot " + slot + ": row stays centred on the lane",
                        (left.x / left.w + right.x / right.w) / 2,
                        list.laneWidth / 2, 0.01);

                    // And it narrows by exactly the projection the outline
                    // scales itself by, so the two keep the same width.
                    suite.near("slot " + slot + ": row narrows by the projection",
                        right.x / right.w - left.x / left.w,
                        list.laneWidth / list.projectionFor(slot), 0.01);
                }

                console.log(suite.failures === 0 ? "PASS" : "FAIL (" + suite.failures + ")");
                Qt.exit(suite.failures === 0 ? 0 : 1);
            }
        }
    }
}
