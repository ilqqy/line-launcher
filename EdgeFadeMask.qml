import QtQuick

// The alpha mask that fades a scrolling view out at its edges. A MultiEffect
// on the view points at it (maskThresholdMin 0.5, maskSpreadAtMin 1.0 maps
// the mask's alpha straight onto a smooth ramp).
//
// Each edge fades only while there is content beyond it: the strengths are
// driven from the view's scroll state, and animate so the fade eases in as
// scrolling starts rather than snapping on.
Item {
    id: root

    property bool vertical: true
    property real fadeSize: Theme.fadeSize
    // 0 = edge fully visible, 1 = faded to nothing at the very edge.
    property real startStrength: 0
    property real endStrength: 0

    Behavior on startStrength {
        NumberAnimation { duration: Theme.fadeDuration; easing.type: Easing.OutCubic }
    }
    Behavior on endStrength {
        NumberAnimation { duration: Theme.fadeDuration; easing.type: Easing.OutCubic }
    }

    visible: false
    layer.enabled: true

    readonly property real span: root.vertical ? root.height : root.width
    readonly property real fade: Math.min(root.fadeSize, root.span / 2)

    Rectangle {
        width: root.vertical ? root.width : root.fade
        height: root.vertical ? root.fade : root.height
        gradient: Gradient {
            orientation: root.vertical ? Gradient.Vertical : Gradient.Horizontal
            GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 1 - root.startStrength) }
            GradientStop { position: 1; color: "black" }
        }
    }

    Rectangle {
        x: root.vertical ? 0 : root.fade
        y: root.vertical ? root.fade : 0
        width: root.vertical ? root.width : root.width - 2 * root.fade
        height: root.vertical ? root.height - 2 * root.fade : root.height
        color: "black"
    }

    Rectangle {
        x: root.vertical ? 0 : root.width - root.fade
        y: root.vertical ? root.height - root.fade : 0
        width: root.vertical ? root.width : root.fade
        height: root.vertical ? root.fade : root.height
        gradient: Gradient {
            orientation: root.vertical ? Gradient.Vertical : Gradient.Horizontal
            GradientStop { position: 0; color: "black" }
            GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 1 - root.endStrength) }
        }
    }
}
