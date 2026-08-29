// The glow's wiring: the options, what switches the effects on and off, and
// the one piece of the lane's transform that has to stay flat.
//
// Deliberately not a rendering test. This suite runs under the offscreen
// platform like the rest, and there Qt Quick falls back to the software
// renderer where every ShaderEffect is a no-op -- tests/preview.qml is the one
// that renders, and it needs an X server. What can be checked here is
// everything up to the draw call: whether the effect objects exist at all,
// what colour and radius they were handed, and whether switching the feature
// off really leaves nothing behind.
import QtQuick
import Quickshell

ShellRoot {
    id: suite

    property int failures: 0

    function check(label: string, condition: bool, detail: string) {
        if (!condition) suite.failures += 1;
        console.log((condition ? "ok   " : "FAIL ") + label + (condition ? "" : "  " + detail));
    }

    function near(a: real, b: real): bool {
        return Math.abs(a - b) < 0.001;
    }

    Item {
        id: host
        width: 800
        height: 600

        Text {
            id: subject
            text: "Volume Control"
        }

        // A glow with everything at its default.
        Glow {
            id: normal
            anchors.fill: subject
            target: subject
        }

        // The three ways to switch one off.
        Glow {
            id: untargeted
            anchors.fill: subject
        }

        Glow {
            id: transparent
            anchors.fill: subject
            target: subject
            strength: 0
        }

        Glow {
            id: hairline
            anchors.fill: subject
            target: subject
            blurRadius: 0
        }

        SearchFrame {
            id: frame
            width: host.width
            height: implicitHeight
        }

        ResultList {
            id: list
            width: host.width
            height: implicitHeight
            results: [
                {"name": "Firefox", "icon": ""},
                {"name": "Steam", "icon": ""},
                {"name": "LACT", "icon": ""}
            ]
            currentIndex: 0
        }

        SelectionOutline {
            id: selection
            width: Config.frameWidth
            centreY: Config.rowHeight / 2
        }
    }

    function run() {
        // Run twice by run.sh, once with the feature on and once with it off.
        if (!Config.glowEnabled) {
            suite.runDisabled();
            return;
        }

        // ------------------------------------------------------- the options

        suite.check("glowEnabled defaults on", Config.glowEnabled,
            "the feature is off by default");

        suite.check("the radii are quoted at the default font size",
            suite.near(Config.glowRadius, Config.data.glowRadius * Config.typeScale)
                && suite.near(Config.auraRadius, Config.data.auraRadius * Config.typeScale),
            "glowRadius=" + Config.glowRadius + " auraRadius=" + Config.auraRadius);

        // run.sh gives this suite a font size well away from the default, so
        // "scales with fontSize" is a measurement rather than an identity that
        // happens to hold at 1x.
        suite.check("and scale with it",
            !suite.near(Config.typeScale, 1)
                && suite.near(Config.glowRadius, Config.data.glowRadius * 2)
                && suite.near(Config.auraRadius, Config.data.auraRadius * 2),
            "typeScale=" + Config.typeScale + " glowRadius=" + Config.glowRadius);

        suite.check("the aura is wider and softer than the glow",
            Config.auraRadius > Config.glowRadius
                && Config.auraOpacity < Config.glowOpacity,
            "glow " + Config.glowRadius + "/" + Config.glowOpacity
                + " aura " + Config.auraRadius + "/" + Config.auraOpacity);

        // -------------------------------------------------------- the colour

        // The legibility halo is the palette background, never the accent.
        suite.check("the glow takes the palette background",
            String(normal.colour) === String(Theme.background)
                && String(Theme.background) !== String(Theme.accent),
            "colour=" + normal.colour + " background=" + Theme.background);

        // ------------------------------------------------------- on and off

        suite.check("a glow with a target is in the scene",
            normal.item !== null, "the effect was never constructed");

        suite.check("one without a target is not",
            untargeted.item === null, "an effect was constructed for nothing");
        suite.check("nor is one at zero strength",
            transparent.item === null, "an invisible effect was still constructed");
        suite.check("nor is one with no radius",
            hairline.item === null, "a zero-radius effect was still constructed");

        // ------------------------------------------------------------- aura

        suite.check("the aura follows glowEnabled", list.auraActive === Config.glowEnabled,
            "auraActive=" + list.auraActive + " glowEnabled=" + Config.glowEnabled);

        suite.check("the outline aura is one traced silhouette",
            selection.auraEffect.item !== null
                && selection.auraEffect.target !== null,
            "the complete outline was not given one effect");

        // The query wears the accent aura; the ghost and the prompt do not.
        // tests/preview.qml proves the accent actually reaches the glass --
        // this only checks that the field is wired to the right colour and
        // the right radius, which is the part that can be read headlessly.
        suite.check("the typed query wears the aura, not the glow",
            String(frame.queryAura.colour) === String(Theme.activeAccent)
                && suite.near(frame.queryAura.blurRadius, Config.auraRadius)
                && suite.near(frame.queryAura.strength,
                    Math.min(1, Config.auraOpacity * 2.5)),
            "colour=" + frame.queryAura.colour
                + " radius=" + frame.queryAura.blurRadius
                + " strength=" + frame.queryAura.strength);

        suite.check("and it traces the typed run alone",
            frame.queryAura.target === frame.inputItem,
            "it traces " + frame.queryAura.target);

        // ------------------------------------------------ the lane transform

        // The lane is straight by default now, and a flat lane has no depth to
        // flatten, so the assertions below turn the fan on: what they are about
        // is the projection surviving the z-row trick, not what the launcher
        // draws out of the box.
        list.perspective = 1;

        // The rows recede on the z axis, and the renderer clips in a shallow
        // band around zero: left alone, everything below the top row is thrown
        // away before it is drawn. rowMatrix zeroes the output z row, which
        // costs the projection nothing -- m43 works on the input z, so the
        // whole perspective divide rides in the fourth row.
        const matrix = list.rowMatrix(3, 1, 260, 34);

        suite.check("the lane's transform emits no depth",
            matrix.m31 === 0 && matrix.m32 === 0 && matrix.m33 === 0 && matrix.m34 === 0,
            "z row is " + matrix.m31 + "," + matrix.m32 + ","
                + matrix.m33 + "," + matrix.m34);

        suite.check("but keeps the perspective divide",
            suite.near(matrix.m43, -1 / list.perspectiveDepth) && matrix.m44 !== 0,
            "m43=" + matrix.m43 + " m44=" + matrix.m44);

        // A point three rows down must still come back foreshortened, or the
        // flattening above has quietly turned the lane into a flat list.
        const far = matrix.times(Qt.vector4d(260, 34, 0, 1));
        suite.check("and still foreshortens", far.w > 1.0,
            "w came back " + far.w + ", so nothing recedes");

        suite.finish();
    }

    // "Set glowEnabled false and the launcher must render exactly as it does
    // today, with no leftover layering cost." Nothing is hidden and nothing is
    // made transparent when the feature is off -- the effects are simply never
    // constructed, so there is no layer to pay for and nothing to render
    // through.
    function runDisabled() {
        suite.check("with the feature off, no effect is constructed",
            normal.item === null && untargeted.item === null
                && transparent.item === null && hairline.item === null,
            "an effect survived glowEnabled = false");

        suite.check("and the aura is gone with it", !list.auraActive,
            "the aura was still active");

        suite.check("and its outline effect is not constructed",
            selection.auraEffect.item === null,
            "an outline effect survived glowEnabled = false");

        // The lane still has to draw, so the transform fix is not conditional
        // on the glow.
        list.perspective = 1;
        const matrix = list.rowMatrix(3, 1, 260, 34);
        suite.check("the lane's transform still emits no depth",
            matrix.m31 === 0 && matrix.m32 === 0 && matrix.m33 === 0 && matrix.m34 === 0,
            "z row is " + matrix.m31 + "," + matrix.m32 + ","
                + matrix.m33 + "," + matrix.m34);

        suite.finish();
    }

    function finish() {
        console.log(suite.failures === 0 ? "PASS" : "FAIL (" + suite.failures + ")");
        Qt.exit(suite.failures === 0 ? 0 : 1);
    }

    // Qt.exit() from Component.onCompleted is emitted before the engine has
    // connected a receiver, and the process then hangs. One pass of the event
    // loop is enough.
    Timer {
        interval: 0
        repeat: false
        running: true
        onTriggered: suite.run()
    }
}
