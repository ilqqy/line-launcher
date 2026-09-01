import QtQuick

// One result row: just the application or action name.
Item {
    id: root

    property string name: ""
    property bool active: false

    implicitHeight: Config.rowHeight

    readonly property real leftPadding: 14

    // The legibility halo, traced from the label.
    //
    // It is a child of the row, so it sits inside the row's opacity and inside
    // its perspective transform. A row that has faded out down the lane takes
    // its glow with it; nothing glows through its own transparency.
    //
    // It is also *outside* the content it traces, which is what keeps the
    // travelling selection cheap: the row's opacity and its tilt both change
    // on every frame while the outline is moving, but both live on this item,
    // not on `content`, so the traced texture stays valid and is only
    // re-composited, never re-rendered.
    Glow {
        anchors.fill: content
        target: content
    }

    Item {
        id: content

        anchors.fill: parent

        Text {
            id: label

            anchors.verticalCenter: parent.verticalCenter
            x: root.leftPadding
            width: root.width - x - root.leftPadding

            text: root.name
            color: root.active ? Theme.foreground : Theme.resultMuted
            font.pixelSize: Theme.fontSize
            font.family: Theme.fontFamily !== "" ? Theme.fontFamily : font.family
            elide: Text.ElideRight

            Behavior on color {
                ColorAnimation {
                    duration: 140
                    easing.type: Easing.OutCubic
                }
            }
        }
    }
}
