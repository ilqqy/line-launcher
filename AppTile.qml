import QtQuick
import "launchpad.js" as Launchpad

// One grid cell: the icon, and the name centred under it on at most two lines.
// The selection highlight is not drawn here; AppGrid moves a single one
// between cells.
Item {
    id: root

    required property var modelData
    required property int index

    property int selectedIndex: -1
    property bool confirming: false

    readonly property bool selected: root.index === root.selectedIndex
    // An action waiting for its second Enter.
    readonly property bool armed: root.selected && root.confirming

    // `scenePos` lets the panel tell real pointer motion from the hover
    // events Qt synthesises when a window maps, or content scrolls, under a
    // pointer that has not moved.
    signal hovered(int index, point scenePos)
    signal clicked(int index)

    width: Theme.cellWidth
    height: Theme.cellHeight

    AppIcon {
        id: icon

        anchors.horizontalCenter: parent.horizontalCenter
        y: Theme.iconTop
        size: Theme.iconSize
        name: Launchpad.iconFor(root.modelData, Theme.commandIcon)
        label: root.modelData ? root.modelData.name : ""

        scale: mouse.pressed ? Theme.pressedScale : 1
        Behavior on scale {
            NumberAnimation { duration: Theme.pressDuration; easing.type: Easing.OutCubic }
        }
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: icon.y + icon.height + Theme.iconLabelGap
        width: root.width - 2 * Theme.labelSidePadding

        text: root.armed ? qsTr("Press Enter to confirm") : (root.modelData ? root.modelData.name : "")
        textFormat: Text.PlainText
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
        maximumLineCount: Theme.labelLines
        elide: Text.ElideRight

        color: root.armed ? Theme.danger : Theme.textPrimary
        font.family: Theme.uiFont
        font.pixelSize: Theme.labelFontSize
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        anchors.margins: Theme.tileInset
        hoverEnabled: true
        onPositionChanged: mouse => {
            if (!root.selected) root.hovered(root.index, mapToItem(null, mouse.x, mouse.y));
        }
        onClicked: root.clicked(root.index)
    }
}
