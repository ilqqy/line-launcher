import QtQuick
import QtQuick.Effects

// The panel surface: translucent fill for Hyprland's layer blur to show
// through, a 1px inner border, and a soft shadow.
//
// The shadow is cut out under the panel. The fill is translucent, so a shadow
// drawn whole behind it would show through as a darker band along the panel's
// edges where the blur falls off; masking it to the outside keeps the glass
// one even tint.
Item {
    id: root

    readonly property real shadowReach: Theme.shadowBlur + Theme.shadowOffsetY

    Item {
        id: shadowSource

        anchors.fill: parent
        anchors.margins: -root.shadowReach
        visible: false
        layer.enabled: true

        RectangularShadow {
            x: root.shadowReach
            y: root.shadowReach + Theme.shadowOffsetY
            width: root.width
            height: root.height
            radius: Theme.radiusPanel
            blur: Theme.shadowBlur
            color: Theme.shadowColor
        }
    }

    Item {
        id: cutout

        anchors.fill: shadowSource
        visible: false
        layer.enabled: true

        Rectangle {
            x: root.shadowReach
            y: root.shadowReach
            width: root.width
            height: root.height
            radius: Theme.radiusPanel
            color: "black"
        }
    }

    MultiEffect {
        anchors.fill: shadowSource
        source: shadowSource
        maskEnabled: true
        maskInverted: true
        maskSource: cutout
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusPanel
        color: Theme.panelFill
        border.width: 1
        border.color: Theme.panelBorder
    }
}
