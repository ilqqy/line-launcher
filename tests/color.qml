// Perceptual accent selection.
//
// The formula is checked against the reference pairs published with the
// CIEDE2000 paper (Sharma, Wu & Dalal 2005, Table 1) rather than against
// itself, because a subtly wrong hue-rotation term still returns plausible
// numbers and would silently pick a mediocre accent.
import QtQuick
import Quickshell
import "color.js" as Colour

ShellRoot {
    id: suite

    property int failures: 0

    function check(label: string, actual: var, expected: var) {
        const ok = String(actual) === String(expected);
        if (!ok) suite.failures += 1;
        console.log((ok ? "ok   " : "FAIL ") + label
            + (ok ? "" : "  expected " + expected + ", got " + actual));
    }

    // Lab pair, then the delta the paper gives for it. These are the awkward
    // cases: hue wrap-around, near-neutral chroma where a 0.0002 shift in a*
    // moves the answer, the symmetry requirement, and the discontinuity at 275
    // degrees that the RT term exists to smooth.
    readonly property var referencePairs: [
        [[50, 2.6772, -79.7751], [50, 0, -82.7485], 2.0425],
        [[50, 3.1571, -77.2803], [50, 0, -82.7485], 2.8615],
        [[50, 2.8361, -74.0200], [50, 0, -82.7485], 3.4412],
        [[50, -1.3802, -84.2814], [50, 0, -82.7485], 1.0000],
        [[50, 0, 0], [50, -1, 2], 2.3669],
        [[50, -1, 2], [50, 0, 0], 2.3669],
        [[50, 2.4900, -0.0010], [50, -2.4900, 0.0009], 7.1792],
        [[50, 2.4900, -0.0010], [50, -2.4900, 0.0011], 7.2195],
        [[50, -0.0010, 2.4900], [50, 0.0009, -2.4900], 4.8045],
        [[50, -0.0010, 2.4900], [50, 0.0011, -2.4900], 4.7461],
        [[50, 2.5, 0], [50, 0, -2.5], 4.3065],
        [[50, 2.5, 0], [73, 25, -18], 27.1492],
        [[60.2574, -34.0099, 36.2677], [60.4626, -34.1751, 39.4387], 1.2644],
        [[2.0776, 0.0795, -1.1350], [0.9033, -0.0636, -0.5514], 0.9082]
    ]

    // The palette that prompted this: nearly monochrome, everything within a
    // few percent of the foreground, which is what made a fixed accentKey
    // produce an invisible outline.
    readonly property string narrowForeground: "#c4c5c6"
    readonly property var narrowPalette: ({
        "color1": "#DEB2A6",
        "color2": "#F4C9B6",
        "color3": "#ACC2CC",
        "color4": "#DCD2D5",
        "color5": "#FDECD7",
        "color6": "#D3D9E6"
    })

    function bestKey(palette: var, foreground: string): var {
        let best = {"key": "", "distance": -1};
        for (const key in palette) {
            const distance = Colour.deltaE2000(palette[key], foreground);
            if (distance > best.distance) best = {"key": key, "distance": distance};
        }
        return best;
    }

    // Deferred: Qt.exit() emitted during Component.onCompleted arrives before
    // the engine has connected a receiver, and the process then never exits.
    Timer {
        interval: 0
        repeat: false
        running: true
        onTriggered: suite.run()
    }

    function run() {
        suite.check("reject a four-digit palette colour", Theme.isColor("#1234"), false);
        suite.check("reject a five-digit palette colour", Theme.isColor("#12345"), false);
        suite.check("reject a seven-digit palette colour", Theme.isColor("#1234567"), false);
        suite.check("accept a short RGB colour", Theme.isColor("#abc"), true);
        suite.check("accept an ARGB colour", Theme.isColor("#80123456"), true);
        let worst = 0;
        for (let i = 0; i < suite.referencePairs.length; i++) {
            const pair = suite.referencePairs[i];
            const got = Colour.deltaE2000Lab(pair[0], pair[1]);
            worst = Math.max(worst, Math.abs(got - pair[2]));
        }
        suite.check("CIEDE2000 matches all "
            + suite.referencePairs.length + " reference pairs", worst < 0.0001, true);
        console.log("     worst deviation from the published values: "
            + worst.toExponential(1));

        suite.check("identical colours are zero apart",
            Colour.deltaE2000("#c4c5c6", "#c4c5c6"), 0);
        suite.check("unparseable input is skippable rather than ranked",
            Colour.deltaE2000("not a colour", "#c4c5c6"), -1);
        suite.check("shorthand hex parses",
            Colour.deltaE2000("#fff", "#ffffff"), 0);
        suite.check("Qt's #AARRGGBB parses, alpha ignored",
            Colour.deltaE2000("#ffc4c5c6", "#c4c5c6"), 0);

        // The distance has to be perceptual, not Euclidean. Against this
        // foreground, plain RGB distance ranks color4 above color3, and
        // color4 is the grey that was invisible.
        const chosen = suite.bestKey(suite.narrowPalette, suite.narrowForeground);
        suite.check("auto avoids the near-grey entries", chosen.key !== "color4", true);
        suite.check("auto avoids the other near-grey", chosen.key !== "color6", true);

        let line = "";
        for (const key in suite.narrowPalette) {
            line += key + " " + Colour.deltaE2000(suite.narrowPalette[key],
                suite.narrowForeground).toFixed(1) + "  ";
        }
        console.log("     deltaE from " + suite.narrowForeground + ": " + line);
        console.log("     auto would pick " + chosen.key + " "
            + suite.narrowPalette[chosen.key]);

        // Theme resolves the accent through the same helper; an explicit key
        // in config.json must still win. run.sh configures color6 = #0000ff.
        suite.check("an explicit accentKey overrides auto",
            Theme.resolvedAccentKey, "color6");
        suite.check("and the explicit key is what gets used",
            String(Theme.accent), "#0000ff");

        console.log(suite.failures === 0 ? "PASS" : "FAIL (" + suite.failures + ")");
        Qt.exit(suite.failures === 0 ? 0 : 1);
    }
}
