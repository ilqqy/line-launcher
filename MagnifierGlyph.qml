import QtQuick

// A drawn magnifier, so the field's glyph does not depend on the icon theme
// having one. Lens and handle are proportions of `size`.
Item {
    id: root

    property real size: Theme.searchGlyphSize
    property color color: Theme.glyph
    property real stroke: Math.max(1.5, root.size * 0.1)

    width: root.size
    height: root.size

    Rectangle {
        x: root.size * 0.04
        y: root.size * 0.04
        width: root.size * 0.68
        height: width
        radius: width / 2
        color: "transparent"
        border.width: root.stroke
        border.color: root.color
        antialiasing: true
    }

    Rectangle {
        readonly property real centre: root.size * 0.77

        width: root.stroke * 1.2
        height: root.size * 0.4
        radius: width / 2
        x: centre - width / 2
        y: centre - height / 2
        rotation: -45
        color: root.color
        antialiasing: true
    }
}
