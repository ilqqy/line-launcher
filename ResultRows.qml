import QtQuick
import QtQuick.Effects
import Quickshell
import "launchpad.js" as Launchpad

// Spotlight-style rows, for results that are text rather than applications:
// piped dmenu lines and ">" commands. Same highlight, fade and scrolling
// behaviour as the grid, one column.
Item {
    id: root

    property var entries: []
    property int selectedIndex: -1
    property bool confirming: false
    property bool showIcons: true

    signal rowHovered(int index, point scenePos)
    signal rowClicked(int index)

    readonly property real step: Theme.rowHeight + Theme.rowSpacing

    ListView {
        id: list

        anchors.fill: parent
        spacing: Theme.rowSpacing
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        cacheBuffer: Theme.rowHeight * 6
        reuseItems: true

        model: ScriptModel {
            values: root.entries
        }

        delegate: Item {
            id: row

            required property var modelData
            required property int index
            readonly property bool selected: row.index === root.selectedIndex
            readonly property bool armed: row.selected && root.confirming

            width: list.width
            height: Theme.rowHeight

            // Not built at all for piped lines, which have no icons to look up.
            Loader {
                id: icon

                active: root.showIcons
                x: Theme.rowPaddingX
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.rowIconSize
                height: Theme.rowIconSize

                sourceComponent: AppIcon {
                    size: Theme.rowIconSize
                    name: Launchpad.iconFor(row.modelData)
                    label: row.modelData ? row.modelData.name : ""
                }
            }

            Text {
                id: name

                anchors.left: root.showIcons ? icon.right : parent.left
                anchors.leftMargin: Theme.rowPaddingX
                anchors.right: hint.visible ? hint.left : parent.right
                anchors.rightMargin: Theme.rowPaddingX
                anchors.verticalCenter: parent.verticalCenter

                text: row.modelData ? row.modelData.name : ""
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: Theme.textPrimary
                font.family: Theme.uiFont
                font.pixelSize: Theme.rowFontSize
            }

            Text {
                id: hint

                visible: row.armed
                anchors.right: parent.right
                anchors.rightMargin: Theme.rowPaddingX
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("Press Enter to confirm")
                textFormat: Text.PlainText
                color: Theme.danger
                font.family: Theme.uiFont
                font.pixelSize: Theme.labelFontSize
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onPositionChanged: mouse => {
                    if (!row.selected) root.rowHovered(row.index, mapToItem(null, mouse.x, mouse.y));
                }
                onClicked: root.rowClicked(row.index)
            }
        }

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
        startStrength: list.atYBeginning ? 0 : 1
        endStrength: list.atYEnd ? 0 : 1
    }

    Rectangle {
        id: highlight

        parent: list.contentItem
        z: -1

        y: Math.max(0, root.selectedIndex) * root.step
        width: list.width
        height: Theme.rowHeight
        radius: Theme.radiusRow
        color: root.confirming ? Theme.dangerFill : Theme.selectionFill
        opacity: root.selectedIndex >= 0 && root.selectedIndex < list.count ? 1 : 0

        Behavior on y {
            enabled: root.glide
            NumberAnimation { duration: root.travel; easing.type: Easing.OutCubic }
        }
        Behavior on color {
            ColorAnimation { duration: Theme.hoverDuration }
        }
    }

    property bool glide: true

    onEntriesChanged: {
        root.glide = false;
        scroller.stop();
        list.contentY = list.originY;
        Qt.callLater(() => root.glide = true);
    }

    property double lastMoveAt: 0
    property int travel: Theme.highlightDuration

    onSelectedIndexChanged: {
        const now = Date.now();
        const gap = now - root.lastMoveAt;
        root.travel = gap < Theme.highlightDuration
            ? Math.max(Theme.minTravel, gap)
            : Theme.highlightDuration;
        root.lastMoveAt = now;
    }

    NumberAnimation {
        id: scroller

        target: list
        property: "contentY"
        duration: Theme.scrollDuration
        easing.type: Easing.OutCubic
    }

    function reveal(index: int) {
        if (index < 0) return;

        const top = index * root.step;
        const bottom = top + Theme.rowHeight;
        const margin = Theme.fadeSize;
        const maxY = Math.max(list.originY, list.originY + list.contentHeight - list.height);

        let y = scroller.running ? scroller.to : list.contentY;
        if (top - margin < y) y = top - margin;
        else if (bottom + margin > y + list.height) y = bottom + margin - list.height;
        y = Math.max(list.originY, Math.min(maxY, y));
        if (Math.abs(y - list.contentY) < 0.5) return;

        scroller.stop();
        scroller.from = list.contentY;
        scroller.to = y;
        scroller.start();
    }
}
