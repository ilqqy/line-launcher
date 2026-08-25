// Proves that the selection spring stops doing per-frame work once it settles.
//
// The shell's only per-frame cost is SelectionOutline's velocity sampler, and
// it is bound to `spring.running`. This test drives a selection change, waits
// for the spring to finish, then asserts the sample counter has stopped
// rising -- a shell component that repaints forever drains a laptop battery,
// and that is not something to check by eye.
import QtQuick
import Quickshell

ShellRoot {
    id: suite

    property int failures: 0
    property int settledSamples: -1
    property real peakOvershoot: 0

    function check(label: string, condition: bool, detail: string) {
        if (!condition) suite.failures += 1;
        console.log((condition ? "ok   " : "FAIL ") + label + (condition ? "" : "  " + detail));
    }

    Item {
        id: host
        width: 800
        height: 600

        ResultList {
            id: list
            width: host.width
            height: implicitHeight
            results: suite.sampleResults
            currentIndex: 0
        }
    }

    readonly property var sampleResults: {
        const out = [];
        for (let i = 0; i < 12; i++) {
            // ResultList reads nothing but `name` and `icon` off a result,
            // which is the whole point of the provider interface.
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

    // Watches how far past the target the outline travels. The resting place
    // is the projected centre of the target row, not its untransformed
    // position -- the perspective compresses the lane downwards.
    readonly property real targetCentre: list.projectedCentre(list.currentIndex - list.firstVisible)

    FrameAnimation {
        // Test-only observer. It is stopped by the sequence below, and is not
        // part of the shell.
        id: observer
        running: false
        onTriggered: {
            // The move is downwards, so overshoot is travel past the target,
            // never the approach to it.
            const past = list.outlineCentre - suite.targetCentre;
            if (past > suite.peakOvershoot) suite.peakOvershoot = past;
        }
    }

    property int phase: 0

    Timer {
        id: steps
        interval: 60
        repeat: true
        running: true

        onTriggered: {
            suite.phase += 1;

            switch (suite.phase) {
            case 1:
                suite.check("idle at startup: spring not running", !list.settling, "spring was running");
                // One row down: the common case, and what the overshoot
                // band below is tuned against.
                observer.running = true;
                list.currentIndex = 1;
                break;

            case 2:
                suite.check("spring is running while travelling", list.settling, "spring did not start");
                suite.check("velocity is non-zero while travelling",
                    Math.abs(list.outlineVelocity) > 0, "velocity stayed at 0");
                break;

            case 25:
                // ~1.4s after the move, against a ~250ms settle: everything
                // must be at rest.
                observer.running = false;
                suite.check("spring stopped", !list.settling, "spring still running");
                suite.check("velocity reset to zero", list.outlineVelocity === 0,
                    "velocity was " + list.outlineVelocity);
                suite.check("outline landed on the target row",
                    Math.abs(list.outlineCentre - suite.targetCentre) < 1,
                    "off by " + (list.outlineCentre - suite.targetCentre));
                suite.check("overshoot is 3-4px",
                    suite.peakOvershoot >= 3.0 && suite.peakOvershoot <= 4.0,
                    "peak overshoot was " + suite.peakOvershoot.toFixed(2) + "px");
                suite.settledSamples = list.outlineSamples;
                break;

            case 50:
                // ~1.5s of doing nothing at all.
                suite.check("no frames sampled while idle",
                    list.outlineSamples === suite.settledSamples,
                    "sampler ran " + (list.outlineSamples - suite.settledSamples)
                        + " more times while idle");

                console.log("     peak overshoot: " + suite.peakOvershoot.toFixed(2) + "px, "
                    + "frames sampled during travel: " + suite.settledSamples);

                console.log(suite.failures === 0 ? "PASS" : "FAIL (" + suite.failures + ")");
                Qt.exit(suite.failures === 0 ? 0 : 1);
                break;
            }
        }
    }
}
