// Proves the full-screen surface is pixel-exactly empty outside the gap.
//
// The launcher is one layer surface the size of the screen with a few hundred
// pixels of content in the middle of it. Hyprland will blur that surface for
// free, but only `layerrule = ignorezero` keeps it from blurring the whole
// screen -- and ignorezero means what it says: a region is skipped when its
// alpha is *zero*, not when it is nearly zero. One stray Rectangle at alpha
// 1/255, one debug fill, one halo spreading over a transparent region, and
// the entire desktop goes soft behind an otherwise invisible window.
//
// That is not something structural assertions can see. An item can be sized,
// coloured and anchored correctly and still put alpha on the glass. So this
// suite grabs the rendered surface -- through the real scene graph, under
// Xvfb, where the effects are not silent no-ops -- and hands run.sh the
// rectangles to measure:
//
//   BOX     everything outside this must be alpha 0 exactly, in both states
//   GAP     must be covered end to end, or the blur has holes in it
//   FILL    a glyph-free patch of the gap, which must read frameFillOpacity
//
// Capture both a query with results and the empty fixed-width input frame.
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

    readonly property string outDir: Quickshell.env("LINE_LAUNCHER_ALPHA_DIR") || ""

    readonly property var sampleResults: [
        {"name": "Volume Control", "icon": ""},
        {"name": "Firefox", "icon": ""},
        {"name": "Steam", "icon": ""}
    ]

    // How far past the drawn content the box is pushed before the outside is
    // measured. Every halo in the scene is bounded by its own blur reach, and
    // the widest is the accent aura, so three times that is well past all of
    // them -- and still leaves most of the surface as the thing being proved.
    readonly property real margin: Config.auraRadius * 3

    FloatingWindow {
        id: win

        // Deliberately far larger than the content. The claim is about the
        // empty majority of a full-screen surface, so there has to be an empty
        // majority to measure.
        implicitWidth: 1200
        implicitHeight: 760
        color: "#404040"
        visible: true

        // What shell.qml puts inside its PanelWindow, laid out the same way:
        // a full-surface item, the frame pinned to the middle of it, the list
        // hanging underneath. Nothing paints a background -- that is the
        // point.
        Item {
            id: surface

            anchors.fill: parent

            SearchFrame {
                id: frame

                width: parent.width
                height: implicitHeight
                y: Config.snap((parent.height - implicitHeight) / 2)

                revealed: true
            }

            ResultList {
                id: list

                width: parent.width
                height: implicitHeight
                anchors.top: frame.bottom
                anchors.topMargin: Config.frameToListGap

                results: frame.text.length > 0 ? suite.sampleResults : []
                currentIndex: 0

                visible: count > 0
            }
        }
    }

    // ------------------------------------------------------------- regions

    // The bounding box of everything that is allowed to paint, in surface
    // coordinates, plus the margin. Measured off the live items rather than
    // recomputed, so it follows the layout instead of asserting it twice.
    function reportBox(state: string) {
        const left = frame.leftWhiskerItem.mapToItem(surface, 0, 0).x;
        const right = frame.rightWhiskerItem.mapToItem(
            surface, frame.rightWhiskerItem.width, 0).x;

        const top = frame.mapToItem(surface, 0, 0).y;
        const bottom = list.visible
            ? list.mapToItem(surface, 0, list.height).y
            : frame.mapToItem(surface, 0, frame.height).y;

        console.log("     ZONE " + state + " box "
            + Math.floor(left - suite.margin) + " "
            + Math.floor(top - suite.margin) + " "
            + Math.ceil(right + suite.margin) + " "
            + Math.ceil(bottom + suite.margin));
    }

    // The weakest alpha in the interior must still cover frameFillOpacity.
    // Glyphs and halos may add coverage, but no pixel should leave a hole.
    function reportGap() {
        // Rounded corners intentionally leave transparent pixels outside the
        // silhouette; measure the rectangular interior they surround.
        const inset = Math.ceil(frame.fillItem.radius);
        const topLeft = frame.fillItem.mapToItem(surface, inset, inset);
        console.log("     ZONE open gap " + Math.round(topLeft.x) + " "
            + Math.round(topLeft.y) + " " + Math.round(frame.fillItem.width - inset * 2)
            + " " + Math.round(frame.fillItem.height - inset * 2) + " "
            + Config.frameFillOpacity);
    }

    function grab(name: string, done: var) {
        if (suite.outDir === "") {
            done();
            return;
        }
        surface.grabToImage(function (result) {
            result.saveToFile(suite.outDir + "/alpha-" + name + ".png");
            done();
        });
    }

    property int phase: 0

    Timer {
        interval: 250
        repeat: true
        running: true

        onTriggered: {
            suite.phase += 1;

            switch (suite.phase) {
            case 2:
                suite.check("the effects are running on a real scene graph",
                    surface.GraphicsInfo.api !== GraphicsInfo.Software,
                    "software renderer: every ShaderEffect is a no-op here, so "
                        + "a halo painting alpha it should not would go unseen");

                // Enough of a query to exercise the typed field.
                frame.inputItem.text = "vo";
                break;

            case 4:
                suite.check("the query keeps the fixed frame width", frame.gap === Config.frameWidth,
                    "typing unexpectedly resized the frame");
                suite.check("and brings the list with it", list.visible,
                    "the gap opened without the list");
                suite.check("the fill is drawn", frame.fillItem.visible,
                    "an open gap with nothing in it blurs nothing");
                suite.check("at the configured opacity",
                    Math.abs(frame.fillItem.color.a - Config.frameFillOpacity) < 0.005,
                    "fill alpha " + frame.fillItem.color.a.toFixed(3)
                        + " vs frameFillOpacity " + Config.frameFillOpacity);

                suite.reportBox("open");
                suite.reportGap();
                suite.grab("open", function () {});
                break;

            case 6:
                frame.inputItem.text = "";
                break;

            case 8:
                suite.check("clearing the field preserves the frame", frame.gap === Config.frameWidth,
                    "the empty input frame should stay visible");
                suite.check("and takes the list away", !list.visible,
                    "the list outlived the gap");
                suite.check("the empty frame remains filled",
                    frame.fillItem.visible,
                    "the prompt lost its frame");

                suite.reportBox("closed");
                suite.grab("closed", function () {});
                break;

            case 10:
                console.log(suite.failures === 0 ? "PASS" : "FAIL (" + suite.failures + ")");
                Qt.exit(suite.failures === 0 ? 0 : 1);
                break;
            }
        }
    }
}
