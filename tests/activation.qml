import QtQuick
import Quickshell

ShellRoot {
    id: suite
    property int failures: 0
    property int launches: 0
    property int cancellations: 0

    function check(label: string, actual: var, expected: var) {
        const ok = actual === expected;
        if (!ok) suite.failures++;
        console.log((ok ? "ok   " : "FAIL ") + label);
    }

    ActivationController {
        id: controller
        onLaunch: item => suite.launches++
        onCancel: suite.cancellations++
    }

    Item {
        SearchFrame {
            id: frame
            onAccepted: controller.activate()
            onKeyActivity: (key, modifiers) => controller.keyActivity(key, modifiers)
        }
    }

    Timer {
        interval: 100
        running: true
        onTriggered: {
            controller.selectedItem = {name: "Reboot", confirm: true};
            frame.handleKey(Qt.Key_Return, Qt.NoModifier, false);
            suite.check("first Enter arms without launching", suite.launches, 0);
            suite.check("confirmation is visible", controller.confirming, true);
            frame.handleKey(Qt.Key_Return, Qt.NoModifier, true);
            suite.check("holding Enter cannot confirm", suite.launches, 0);
            frame.handleKey(Qt.Key_Control, Qt.ControlModifier, false);
            suite.check("modifiers retain confirmation", controller.confirming, true);
            frame.handleKey(Qt.Key_M, Qt.ControlModifier, false);
            suite.check("Ctrl+m can confirm an armed action", suite.launches, 1);
            frame.handleKey(Qt.Key_Return, Qt.NoModifier, false);
            suite.check("closing prevents duplicate execution", suite.launches, 1);

            controller.closing = false;
            controller.activate();
            controller.selectedItem = {name: "Power off", confirm: true};
            suite.check("replacing the result clears confirmation", controller.confirming, false);
            controller.activate();
            suite.check("replacement needs its own confirmation", suite.launches, 1);
            frame.handleKey(Qt.Key_A, Qt.NoModifier, false);
            suite.check("typing cancels confirmation", controller.confirming, false);
            frame.handleKey(Qt.Key_M, Qt.ControlModifier, false);
            frame.handleKey(Qt.Key_M, Qt.ControlModifier, false);
            suite.check("two Ctrl+m presses launch", suite.launches, 2);

            controller.closing = false;
            controller.selectedItem = null;
            controller.activate();
            controller.activate();
            suite.check("empty selection cancels once", suite.cancellations, 1);
            console.log(suite.failures === 0 ? "PASS" : "FAIL");
            Qt.exit(suite.failures === 0 ? 0 : 1);
        }
    }
}
