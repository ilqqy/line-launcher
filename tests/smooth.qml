// Sample the current entrance and launch-collapse animations on a real GPU
// backend. Typing no longer changes frame width.
import QtQuick
import QtQuick.Window
import Quickshell

ShellRoot {
    id: suite
    property int failures: 0
    property int phase: 0
    property var samples: []
    property bool recording: false

    function check(label: string, condition: bool) {
        if (!condition) suite.failures++;
        console.log((condition ? "ok   " : "FAIL ") + label);
    }

    FloatingWindow {
        implicitWidth: 900
        implicitHeight: 300
        visible: true
        SearchFrame {
            id: frame
            width: parent.width
            height: implicitHeight
            y: 100
        }
        FrameAnimation {
            running: suite.recording
            onTriggered: suite.samples.push(frame.collapsing
                ? Config.frameWidth - frame.gap
                : frame.entryDistance - frame.entryOffset)
        }
    }

    function checkMotion(label: string, distance: real) {
        const values = suite.samples;
        let moving = 0;
        let backwards = false;
        for (let i = 1; i < values.length; i++) {
            if (values[i] - values[i - 1] > 0.01) moving++;
            if (values[i] < values[i - 1] - 0.01) backwards = true;
        }
        suite.check(label + " spans multiple rendered frames", moving >= 2);
        suite.check(label + " reaches its destination",
            values.length > 0 && Math.abs(values[values.length - 1] - distance) < 0.1);
        suite.check(label + " never reverses", !backwards);
    }

    Timer {
        interval: 250
        running: true
        repeat: true
        onTriggered: {
            suite.phase++;
            switch (suite.phase) {
            case 2:
                suite.check("animations use a real scene graph",
                    frame.GraphicsInfo.api !== GraphicsInfo.Software);
                suite.samples = [0];
                suite.recording = true;
                frame.revealed = true;
                break;
            case 4:
                suite.recording = false;
                suite.checkMotion("entrance", frame.entryDistance);
                frame.inputItem.text = "x".repeat(80);
                suite.check("typing leaves the frame width stable", frame.gap === Config.frameWidth);
                suite.samples = [0];
                suite.recording = true;
                frame.collapsing = true;
                break;
            case 6:
                suite.recording = false;
                suite.checkMotion("launch collapse", Config.frameWidth);
                suite.check("collapsed frame stops painting its fill", !frame.fillItem.visible);
                console.log(suite.failures === 0 ? "PASS" : "FAIL");
                Qt.exit(suite.failures === 0 ? 0 : 1);
                break;
            }
        }
    }
}
