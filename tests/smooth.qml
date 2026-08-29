// Measures how the frame actually moves, one rendered frame at a time.
//
// Structural assertions cannot see choppiness. An animation can be running,
// arrive exactly where it was aimed, and take exactly as long as it said, and
// still look wrong -- because what the eye reads is not where it started and
// ended but how evenly it got there.
//
// This suite is the one that caught the spring. Qt integrates a
// SpringAnimation in coarse steps from a standing start, so its first rendered
// frame teleported a third of the way across and the rest crawled:
//
//     0, 83, 156, 204, 232, 246, 254, 257, 259, 260 ...
//
// Every number the code reported about that animation was correct. It just
// looked like a jump followed by a drift.
//
// So the gap is sampled with a FrameAnimation, which ticks once per rendered
// frame, and judged on:
//
//   first step  how much of the travel lands in frame one. A gentle start is
//               the difference between motion and a teleport.
//   jerk        the largest change in step size between consecutive frames.
//               This is the one that reads as choppy.
//   backwards   any reversal at all, which reads as jitter.
//   held        a frame the gap did not move on, mid-animation, which reads
//               as a stutter.
//
// It needs a real scene graph: under QT_QPA_PLATFORM=offscreen there is no
// render loop, so FrameAnimation never ticks and this would measure nothing.
// run.sh gives it the Xvfb the preview suites use.
import QtQuick
import QtQuick.Window
import Quickshell

ShellRoot {
    id: suite

    property int failures: 0

    function check(label: string, condition: bool, detail: string) {
        if (!condition) suite.failures += 1;
        console.log((condition ? "ok   " : "FAIL ") + label + (condition ? "" : "  " + detail));
    }

    FloatingWindow {
        implicitWidth: 900
        implicitHeight: 300
        visible: true
        color: "#202020"

        SearchFrame {
            id: frame

            width: parent.width
            height: implicitHeight
            y: Math.round((parent.height - implicitHeight) / 2)

            // No completion anywhere in this suite: a ghost would open most of
            // the gap on the first keystroke and then hold, which is the right
            // behaviour but the wrong thing to measure. With the gap driven by
            // the typed run alone, every key moves it by one character and the
            // typing phase is twenty real retargets.
            completion: ""
            revealed: true
        }

        FrameAnimation {
            id: sampler

            running: true
            property var samples: []

            onTriggered: {
                if (suite.recording) sampler.samples.push(frame.drawnGap);
            }
        }
    }

    property bool recording: false

    // ------------------------------------------------------------ analysis

    // The moving part of a recording, with the still frames either side
    // trimmed off, reduced to the numbers above.
    function analyse(samples: var): var {
        let first = 0;
        while (first + 1 < samples.length
            && Math.abs(samples[first + 1] - samples[first]) < 0.001) first += 1;

        let last = samples.length - 1;
        while (last > first && Math.abs(samples[last] - samples[last - 1]) < 0.001) last -= 1;

        const steps = [];
        let held = 0;
        let backwards = 0;
        for (let i = first + 1; i <= last; i++) {
            const delta = samples[i] - samples[i - 1];
            if (delta < -0.001) backwards = Math.max(backwards, -delta);
            if (Math.abs(delta) < 0.001) held += 1;
            steps.push(Math.abs(delta));
        }

        let jerk = 0;
        for (let i = 1; i < steps.length; i++) {
            jerk = Math.max(jerk, Math.abs(steps[i] - steps[i - 1]));
        }

        const sorted = steps.slice().sort((a, b) => a - b);
        return {
            "frames": steps.length,
            "travel": Math.abs(samples[last] - samples[first]),
            "first": steps.length > 0 ? steps[0] : 0,
            "median": sorted.length > 0 ? sorted[Math.floor(sorted.length / 2)] : 0,
            "max": sorted.length > 0 ? sorted[sorted.length - 1] : 0,
            "jerk": jerk,
            "held": held,
            "backwards": backwards
        };
    }

    function report(name: string, m: var) {
        console.log("     " + name + ": " + m.frames + " moving frames over "
            + m.travel.toFixed(0) + "px, first step " + m.first.toFixed(1)
            + "px, median " + m.median.toFixed(1) + "px, max " + m.max.toFixed(1)
            + "px, jerk " + m.jerk.toFixed(1) + "px, " + m.held + " held, "
            + m.backwards.toFixed(2) + "px backwards");
    }

    // ------------------------------------------------------------- phases

    property int phase: 0
    property int typed: 0
    property var openMetrics: null

    Timer {
        id: clock

        interval: 90
        repeat: true
        running: true

        onTriggered: {
            suite.phase += 1;

            switch (suite.phase) {
            case 2:
                suite.check("the effects are running on a real scene graph",
                    sampler.samples.length === 0 && frame.drawnGap === 0,
                    "the frame did not start shut");
                suite.recording = true;
                break;

            case 3:
                // Long enough to run the gap into its ceiling, so the travel
                // is the full frameWidth rather than a few characters of it.
                frame.inputItem.text = "x".repeat(80);
                break;

            case 9:
                suite.recording = false;
                suite.openMetrics = suite.analyse(sampler.samples);
                suite.report("a cold open", suite.openMetrics);
                suite.checkOpen(suite.openMetrics);

                sampler.samples = [];
                frame.inputItem.text = "";
                break;

            case 13:
                suite.recording = true;
                break;

            default:
                // Twenty keystrokes at the timer's own interval.
                if (suite.phase >= 14 && suite.phase <= 33) {
                    suite.typed += 1;
                    frame.inputItem.text = "x".repeat(suite.typed);
                } else if (suite.phase === 38) {
                    suite.recording = false;
                    const typing = suite.analyse(sampler.samples);
                    suite.report("typing", typing);
                    suite.checkTyping(typing, suite.openMetrics);

                    console.log(suite.failures === 0
                        ? "PASS"
                        : "FAIL (" + suite.failures + ")");
                    Qt.exit(suite.failures === 0 ? 0 : 1);
                }
                break;
            }
        }
    }

    // ------------------------------------------------------------- limits

    // Thresholds are set between what the shipped curve measures and what the
    // spring measured, so this suite fails if the spring -- or anything with
    // its shape -- comes back. Measured for OutSine at 200ms against
    // SpringAnimation at 20/0.8, on the same travel:
    //
    //                first step   jerk    typing jerk
    //   OutSine          13% of   4.7px         0.7px
    //   spring           32% of  25.4px         3.7px

    function checkOpen(m: var) {
        suite.check("the open actually animated", m.frames >= 6,
            "only " + m.frames + " frames of motion, which is not enough to judge");
        suite.check("it covered the whole gap", m.travel > Config.frameWidth * 0.9,
            "travelled only " + m.travel.toFixed(0) + "px");

        // The one the spring failed hardest.
        suite.check("it eases in rather than teleporting",
            m.first < m.travel * 0.25,
            "first frame moved " + m.first.toFixed(1) + "px, "
                + (100 * m.first / m.travel).toFixed(0) + "% of the travel");

        suite.check("and keeps an even pace", m.jerk < 12,
            "step size changed by " + m.jerk.toFixed(1) + "px between frames");

        suite.check("without stalling mid-travel", m.held === 0,
            m.held + " frames the gap did not move on");
        suite.check("or ever going backwards", m.backwards < 0.01,
            "reversed by " + m.backwards.toFixed(2) + "px");
    }

    function checkTyping(m: var, open: var) {
        suite.check("typing kept the gap moving", m.frames >= 40,
            "only " + m.frames + " frames of motion over twenty keystrokes");

        // The gap is chasing a target that moves again every keystroke, so
        // this is the number that decides whether typing feels smooth.
        suite.check("and moving evenly", m.jerk < 2.5,
            "step size changed by " + m.jerk.toFixed(1) + "px between frames");
        suite.check("never backwards", m.backwards < 0.01,
            "reversed by " + m.backwards.toFixed(2) + "px");

        // Tracking, not chasing in bursts: an animation that finishes between
        // keystrokes shows up as a large step followed by still frames.
        suite.check("in steps a fraction of a character wide", m.max < 12,
            "largest single frame moved " + m.max.toFixed(1) + "px");
    }
}
