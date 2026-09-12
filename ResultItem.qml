import QtQuick

// One result row: just the application or action name.
Item {
    id: root

    property string name: ""
    property bool active: false

    implicitHeight: Config.rowHeight

    readonly property real leftPadding: 14

    // Keep contrast predictable even over bright or detailed wallpaper.
    // Outside the traced content so the text halo never blurs the backing.
    Rectangle {
        anchors.fill: parent
        z: -2
        radius: Config.cornerRadius
        color: Qt.alpha(Theme.resultBackdrop, root.active ? 0.82 : 0.72)

        Behavior on color {
            ColorAnimation { duration: 140; easing.type: Easing.OutCubic }
        }
    }

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
        // Tighter and stronger than the decorative frame glow: this behaves
        // like a readable text shadow over a wallpaper, not a broad aura.
        blurRadius: Config.glowRadius * 0.5
        strength: Math.max(Config.glowOpacity, 0.9)
        colour: Theme.resultBackdrop
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
            textFormat: Text.PlainText
            color: root.active ? Theme.resultForeground : Theme.resultMuted
            font.pixelSize: Theme.fontSize
            font.weight: Font.DemiBold
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
