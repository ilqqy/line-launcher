import QtQuick
import QtQuick.Effects

// The category chips: pills, "All" first, horizontally scrollable with the
// same edge fade as the results.
//
// The active chip is one accent pill sliding between chips rather than a fill
// switching on and off, so Tab reads as movement along the row.
Item {
    id: root

    // [{ key, label, count }], as launchpad.js chipsFor() builds it.
    property var model: []
    property string activeKey: ""

    signal activated(string key)

    readonly property alias view: list

    readonly property int activeIndex: {
        for (let i = 0; i < root.model.length; i++) {
            if (root.model[i].key === root.activeKey) return i;
        }
        return 0;
    }

    ListView {
        id: list

        anchors.fill: parent
        orientation: ListView.Horizontal
        spacing: Theme.chipSpacing
        leftMargin: Theme.panelPadding
        rightMargin: Theme.panelPadding
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        model: root.model
        currentIndex: root.activeIndex
        highlightFollowsCurrentItem: false

        highlight: Rectangle {
            id: pill

            x: list.currentItem ? list.currentItem.x : 0
            width: list.currentItem ? list.currentItem.width : 0
            height: list.height
            radius: height / 2
            color: Theme.chipActiveFill

            // Placed, not slid, the first time it gets a size.
            Behavior on x {
                enabled: pill.width > 0
                NumberAnimation { duration: Theme.chipDuration; easing.type: Easing.OutCubic }
            }
            Behavior on width {
                enabled: pill.width > 0
                NumberAnimation { duration: Theme.chipDuration; easing.type: Easing.OutCubic }
            }
            Behavior on color {
                ColorAnimation { duration: Theme.chipDuration }
            }
        }

        delegate: Rectangle {
            id: chip

            required property var modelData
            required property int index
            readonly property bool active: chip.index === list.currentIndex

            width: label.implicitWidth + 2 * Theme.chipPaddingX
            height: list.height
            radius: height / 2
            color: chip.active ? "transparent" : (chipMouse.containsMouse ? Theme.chipHoverFill : Theme.chipFill)

            Behavior on color {
                ColorAnimation { duration: Theme.hoverDuration }
            }

            Text {
                id: label

                anchors.centerIn: parent
                text: chip.modelData.label
                textFormat: Text.PlainText
                color: chip.active ? Theme.chipActiveText : Theme.chipText
                font.family: Theme.uiFont
                font.pixelSize: Theme.chipFontSize
                font.weight: Theme.chipFontWeight

                Behavior on color {
                    ColorAnimation { duration: Theme.chipDuration }
                }
            }

            MouseArea {
                id: chipMouse

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.activated(chip.modelData.key)
            }
        }

        onCurrentIndexChanged: root.reveal()

        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: fade
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }
    }

    EdgeFadeMask {
        id: fade

        anchors.fill: list
        vertical: false
        startStrength: list.atXBeginning ? 0 : 1
        endStrength: list.atXEnd ? 0 : 1
    }

    NumberAnimation {
        id: scroller

        target: list
        property: "contentX"
        duration: Theme.scrollDuration
        easing.type: Easing.OutCubic
    }

    // Back to the first chip, without travelling.
    function resetScroll() {
        scroller.stop();
        list.contentX = list.originX - list.leftMargin;
    }

    // Bring the active chip clear of the edge fades.
    function reveal() {
        const item = list.itemAtIndex(root.activeIndex);
        if (!item) {
            list.positionViewAtIndex(root.activeIndex, ListView.Contain);
            return;
        }

        const margin = Theme.fadeSize;
        const minX = list.originX - list.leftMargin;
        const maxX = Math.max(minX, list.originX + list.contentWidth + list.rightMargin - list.width);
        let x = scroller.running ? scroller.to : list.contentX;
        if (item.x - margin < x) x = item.x - margin;
        else if (item.x + item.width + margin > x + list.width) x = item.x + item.width + margin - list.width;
        x = Math.max(minX, Math.min(maxX, x));
        if (Math.abs(x - list.contentX) < 0.5) return;

        scroller.stop();
        scroller.from = list.contentX;
        scroller.to = x;
        scroller.start();
    }
}
