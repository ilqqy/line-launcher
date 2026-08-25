import QtQuick

// One result row: icon on the left, name on the right.
//
// Knows nothing about which provider produced it -- it is handed a name and an
// icon source and draws them.
Item {
    id: root

    property string name: ""
    property string iconSource: ""
    property bool active: false

    implicitHeight: Config.rowHeight

    readonly property real leftPadding: 14
    readonly property real iconGap: 12

    // The legibility halo, traced from the row's whole content -- icon and
    // label together, one effect rather than two.
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

        Item {
            id: iconSlot

            width: Config.iconSize
            height: Config.iconSize
            x: root.leftPadding
            y: Config.snap((root.height - height) / 2)

            // Icons are drawn in their own colours, active or not. Tinting the
            // active one to the accent assumed monochrome symbolic icons;
            // against a full-colour theme like Papirus it flattens the icon
            // into a solid accent blob. The accent belongs to the selection
            // outline alone.
            Image {
                id: iconImage

                anchors.fill: parent
                source: root.iconSource
                visible: root.iconSource !== ""

                // Ask for the size this will actually occupy in device pixels,
                // rounded up to a real theme size. Asking for the logical size
                // gets a smaller pixmap scaled up, which is what made these
                // blurry.
                sourceSize.width: Config.iconPixelSize
                sourceSize.height: Config.iconPixelSize

                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
                mipmap: true
            }

            // Drawn stand-in for an entry whose icon name resolves to nothing
            // in the current theme. Blank space would leave the name hanging
            // off an empty column, so there is always a mark here.
            Rectangle {
                anchors.centerIn: parent
                visible: root.iconSource === ""

                width: Math.round(parent.width * 0.62)
                height: width
                radius: width / 2

                color: "transparent"
                border.width: Config.strokeWidth
                // Follows the label rather than the accent, for the same
                // reason the icon does.
                border.color: root.active ? Theme.foreground : Theme.muted

                Behavior on border.color {
                    ColorAnimation {
                        duration: 140
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }

        Text {
            id: label

            anchors.verticalCenter: parent.verticalCenter
            x: iconSlot.x + iconSlot.width + root.iconGap
            width: root.width - x - root.leftPadding

            text: root.name
            color: root.active ? Theme.foreground : Theme.muted
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
