// Renders the launcher over a pale background and measures what it costs.
//
// This suite is the only one that needs a real scene graph. Every other test
// runs under QT_QPA_PLATFORM=offscreen, and that platform reports no OpenGL
// capability, so Qt Quick falls back to the software renderer -- measured:
// GraphicsInfo.api came back Software and shaderType Unknown. Under the
// software renderer every ShaderEffect draws nothing at all, which means both
// MultiEffect and RectangularShadow are silently no-ops there. A glow test
// under offscreen would pass without ever having drawn a glow.
//
// So run.sh starts an Xvfb when it can find one and runs this against it,
// where the api comes back OpenGL and the effects are real. Two things are
// checked:
//
//   1. a PNG is grabbed for eyeballing, over a background chosen to be the
//      worst case -- pale, and pale in patches, so any part of the UI that
//      needs the halo shows it;
//   2. the frame counter. The shell's rule is that it stops repainting once
//      everything settles, and adding two blur effects is exactly the kind of
//      change that quietly breaks it.
import QtQuick
import QtQuick.Window
import Quickshell

ShellRoot {
    id: suite

    property int failures: 0
    property int frames: 0
    property int firstPaint: 0
    property int idleFrames: 0
    property int travelFrames: 0

    function check(label: string, condition: bool, detail: string) {
        if (!condition) suite.failures += 1;
        console.log((condition ? "ok   " : "FAIL ") + label + (condition ? "" : "  " + detail));
    }

    readonly property string outFile: Quickshell.env("LINE_LAUNCHER_PREVIEW_OUT") || ""

    readonly property var sampleResults: [
        {"name": "Firefox", "icon": ""},
        {"name": "Volume Control", "icon": ""},
        {"name": "Steam", "icon": ""},
        {"name": "LACT", "icon": ""},
        {"name": "Text Editor", "icon": ""},
        {"name": "Files", "icon": ""}
    ]

    FloatingWindow {
        id: win

        implicitWidth: 720
        // Tall enough for the whole lane plus room for the halos to spill
        // into, whatever visibleItems happens to be.
        implicitHeight: Math.ceil(content.height) + 160
        color: "#e8e4dd"
        visible: true

        // Stand-in for a pale wallpaper: light overall, and unevenly light, so
        // the glow is judged against both a bright field and a washed one
        // rather than a single flat tone.
        Item {
            id: backdrop
            anchors.fill: parent

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#fdfbf7" }
                    GradientStop { position: 0.55; color: "#ddd6ca" }
                    GradientStop { position: 1.0; color: "#f2ece2" }
                }
            }

            Rectangle {
                x: 40
                y: 150
                width: 260
                height: 200
                radius: 120
                color: "#fffdf8"
                opacity: 0.85
            }

            Rectangle {
                x: 430
                y: 60
                width: 240
                height: 260
                radius: 40
                color: "#cfc6b6"
                opacity: 0.7
            }

            Item {
                id: content

                anchors.centerIn: parent
                width: parent.width
                height: frame.implicitHeight + Config.frameToListGap + list.implicitHeight
                    + Config.frameToListGap + promptFrame.implicitHeight

                SearchFrame {
                    id: frame

                    width: parent.width
                    height: implicitHeight
                    anchors.top: parent.top
                    Component.onCompleted: frame.inputItem.text = "Volume"
                }

                // A second frame, left empty, so the prompt gets rendered and
                // checked too. The prompt only shows while the field is
                // empty, and the field the query is typed into cannot be in
                // both states for one grab.
                SearchFrame {
                    id: promptFrame

                    width: parent.width
                    height: implicitHeight
                    anchors.top: list.bottom
                    anchors.topMargin: Config.frameToListGap
                }

                ResultList {
                    id: list

                    width: parent.width
                    height: implicitHeight
                    anchors.top: frame.bottom
                    anchors.topMargin: Config.frameToListGap

                    results: suite.sampleResults
                    currentIndex: 1
                }
            }

            Connections {
                target: backdrop.Window.window
                function onFrameSwapped() { suite.frames += 1; }
            }
        }
    }

    // Where the rows and the outline actually ended up, asked of Qt rather
    // than recomputed here: mapToItem walks the real transform chain, so this
    // is the geometry the scene graph used, not the geometry the lane's own
    // formula predicts. The two agreeing is the whole point.
    function checkGeometry() {
        let checked = 0;

        for (let i = 0; i < list.children.length; i++) {
            const row = list.children[i];
            if (row.slot === undefined || !row.visible) continue;

            const centre = row.mapToItem(list, row.width / 2, row.height / 2);
            const expected = list.projectedCentre(row.slot);

            suite.check("slot " + row.slot + ": drawn row centre matches the outline's",
                Math.abs(centre.y - expected) < 0.5,
                "row centre landed at " + centre.y.toFixed(2)
                    + ", the outline goes to " + expected.toFixed(2));
            checked += 1;
        }

        suite.check("every visible slot was checked", checked >= 3,
            "only " + checked + " rows were visible to check");

        // And the selected row specifically: the outline is a separate,
        // untransformed item, so this is the one that shows up as content
        // sitting low inside its own box.
        for (let i = 0; i < list.children.length; i++) {
            const row = list.children[i];
            if (row.slot === undefined || !row.active) continue;

            const centre = row.mapToItem(list, row.width / 2, row.height / 2);
            suite.check("the selected row's content is centred in the outline",
                Math.abs(centre.y - list.outlineCentre) < 0.5,
                "content centre " + centre.y.toFixed(2)
                    + " vs outline centre " + list.outlineCentre.toFixed(2));
        }
    }

    // Rectangles for run.sh to compare between the two renders. Taken off the
    // live items so they survive any layout change.
    // One region for run.sh to compare between the two renders, and how it
    // should have changed. "darker" is the legibility halo; "warmer" is the
    // accent aura, which is a colour rather than a shade -- the preview
    // palette's accent is warm and its background is cool, so red rising
    // against blue is the accent arriving and nothing else.
    function rect(name: string, item: Item, x: real, width: real, metric: string) {
        const topLeft = item.mapToItem(backdrop, x, 0);
        console.log("     RECT " + name + " " + Math.round(topLeft.x) + " "
            + Math.round(topLeft.y) + " " + Math.round(width) + " "
            + Math.round(item.height) + " " + metric);
    }

    function reportRects() {
        // The typed text and prompt in the field, separately.
        const typedX = frame.typedTextX;
        const typedWidth = frame.typedTextWidth;
        suite.rect("typed-text", frame.inputItem, typedX, typedWidth, "darker");
        suite.rect("prompt", promptFrame.promptItem, 0,
            promptFrame.promptItem.contentWidth, "darker");

        // The accent aura is only on the typed run; the prompt is furniture.
        suite.rect("typed-query-accent", frame.inputItem, typedX, typedWidth, "warmer");

        for (let i = 0; i < list.children.length; i++) {
            const row = list.children[i];
            if (row.slot === undefined || !row.active) continue;

            suite.rect("selected-row", row, 0, row.width, "darker");
        }
    }

    property int phase: 0
    property int mark: 0

    Timer {
        interval: 200
        repeat: true
        running: true

        onTriggered: {
            suite.phase += 1;

            switch (suite.phase) {
            case 4:
                console.log("     scene graph api=" + backdrop.GraphicsInfo.api
                    + " (1=Software, 3=OpenGL)");
                suite.check("the effects are running on a real scene graph",
                    backdrop.GraphicsInfo.api !== GraphicsInfo.Software,
                    "software renderer: ShaderEffect draws nothing, so this "
                        + "suite would prove nothing");

                if (suite.outFile !== "") {
                    backdrop.grabToImage(function (result) {
                        result.saveToFile(suite.outFile);
                        console.log("     preview written to " + suite.outFile);
                    });
                }
                break;

            case 6:
                suite.checkGeometry();
                suite.reportRects();
                break;

            case 8:
                // Everything has settled and the grab is done.
                suite.firstPaint = suite.frames;
                suite.mark = suite.frames;
                break;

            case 18:
                // ~2s of an idle launcher, both glows in the scene.
                suite.idleFrames = suite.frames - suite.mark;
                suite.check("an idle launcher swaps no frames",
                    suite.idleFrames === 0,
                    "swapped " + suite.idleFrames + " frames over 2s while idle");

                // Now the case the aura was built for: the outline travels
                // three rows, stretching as it goes, with the aura glued to it.
                suite.mark = suite.frames;
                list.currentIndex = 4;
                break;

            case 26:
                suite.travelFrames = suite.frames - suite.mark;
                suite.check("the travel actually animated",
                    suite.travelFrames > 5,
                    "only " + suite.travelFrames + " frames for a three-row move");
                suite.check("the outline landed", !list.settling, "spring still running");
                suite.mark = suite.frames;
                break;

            case 36:
                // ~2s after the outline landed. This is the one that matters:
                // a glow that forced a repaint would show up here, not during
                // the travel.
                const after = suite.frames - suite.mark;
                suite.check("and stops repainting once it lands",
                    after === 0, "swapped " + after + " frames over 2s after landing");

                console.log("     frames: " + suite.firstPaint + " to first paint, "
                    + suite.idleFrames + " over 2s idle, "
                    + suite.travelFrames + " during a three-row travel, "
                    + after + " over 2s after it landed");

                console.log("     glow=" + Config.glowEnabled
                    + " glowRadius=" + Config.glowRadius.toFixed(1)
                    + " glowOpacity=" + Config.glowOpacity
                    + " auraRadius=" + Config.auraRadius.toFixed(1)
                    + " auraOpacity=" + Config.auraOpacity
                    + " aura=" + list.auraActive);

                console.log(suite.failures === 0 ? "PASS" : "FAIL (" + suite.failures + ")");
                Qt.exit(suite.failures === 0 ? 0 : 1);
                break;
            }
        }
    }
}
