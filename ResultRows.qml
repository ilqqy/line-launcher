import QtQuick
import Quickshell
import "entries.js" as Entries

// The results list: a section header, then one row per result -- icon and
// name -- with a single rounded highlight that glides between rows. It shows `entries` in the order given and reports rows by index.
Item {
    id: root

    property var entries: []
    property int selectedIndex: -1
    property bool confirming: false
    property bool showIcons: true
    property string title: ""

    signal rowHovered(int index, point scenePos)
    signal rowClicked(int index)

    readonly property real step: Theme.rowHeight + Theme.rowSpacing

    readonly property alias view: list

    ListView {
        id: list

        anchors.fill: parent
        anchors.topMargin: Theme.listPaddingY
        anchors.bottomMargin: Theme.listPaddingY
        spacing: Theme.rowSpacing
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        cacheBuffer: Theme.rowHeight * 6
        reuseItems: true

        // Diffed by identity, so a keystroke that keeps a result in the list
        // keeps its delegate -- and its loaded icon -- too.
        model: ScriptModel {
            values: root.entries
        }

        // Scrolls with the rows. A ListView places its header before the
        // first item, so rows still start at y = 0 and originY is negative.
        header: Item {
            width: list.width
            height: root.entries.length > 0 && root.title !== "" ? Theme.sectionHeight : 0

            Text {
                x: Theme.rowPaddingX
                width: parent.width - 2 * Theme.rowPaddingX
                height: parent.height
                visible: parent.height > 0
                verticalAlignment: Text.AlignVCenter

                text: root.title
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: Theme.textSecondary
                font.family: Theme.uiFont
                font.pixelSize: Theme.sectionFontSize
                font.weight: Theme.sectionFontWeight
            }
        }

        delegate: Item {
            id: row

            required property var modelData
            required property int index
            readonly property bool selected: row.index === root.selectedIndex
            readonly property bool armed: row.selected && root.confirming

            // cacheBuffer builds rows below the fold ahead of a scroll. Their
            // icons wait until the row is on screen: the image loader serves
            // the newest request first, so they would otherwise load ahead of
            // the icons that are actually visible.
            readonly property bool iconActive: {
                const top = row.index * root.step;
                return top < list.contentY + list.height && top + Theme.rowHeight > list.contentY;
            }
            // Exposed for tests.
            readonly property var iconItem: icon.item

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
                    active: row.iconActive
                    name: Entries.iconFor(row.modelData, Theme.commandIcon)
                    label: row.modelData ? row.modelData.name : ""
                }
            }

            Text {
                anchors.left: root.showIcons ? icon.right : parent.left
                anchors.leftMargin: root.showIcons ? Theme.rowIconGap : Theme.rowPaddingX
                anchors.right: accessory.visible ? accessory.left : parent.right
                anchors.rightMargin: Theme.rowPaddingX + (accessory.visible ? Theme.searchGap : 0)
                anchors.verticalCenter: parent.verticalCenter

                text: row.modelData ? row.modelData.name : ""
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: row.armed ? Theme.danger : Theme.textPrimary
                font.family: Theme.uiFont
                font.pixelSize: Theme.rowFontSize
            }

            Text {
                id: accessory

                visible: text !== ""
                anchors.right: parent.right
                anchors.rightMargin: Theme.rowPaddingX + 2
                anchors.verticalCenter: parent.verticalCenter

                // Only an action waiting for its second Enter says anything here.
                text: row.armed ? qsTr("Press Enter to confirm") : ""
                textFormat: Text.PlainText
                color: Theme.danger
                font.family: Theme.uiFont
                font.pixelSize: Theme.accessoryFontSize
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
    }

    // ----------------------------------------------------------- highlight

    // Lives in the list's content so it scrolls with the rows.
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

    // A new result set is a new page, not a move: the highlight lands on its
    // row and the scroll returns to the top without travelling.
    property bool glide: true

    onEntriesChanged: root.resetScroll()

    function resetScroll() {
        root.glide = false;
        scroller.stop();
        list.contentY = list.originY;
        Qt.callLater(() => root.glide = true);
    }

    // Under key auto-repeat each move arrives before the last glide ends.
    // Give each step the repeat's own interval so the highlight keeps up
    // instead of trailing further behind with every step.
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

    // --------------------------------------------------------------- scroll

    NumberAnimation {
        id: scroller

        target: list
        property: "contentY"
        duration: Theme.scrollDuration
        easing.type: Easing.OutCubic
    }

    // Scroll just enough to bring a row fully into view; the first row brings
    // the header with it. Called for keyboard moves only; a hovered row is
    // already where the pointer is.
    function reveal(index: int) {
        if (index < 0) return;

        const top = index === 0 ? list.originY : index * root.step;
        const bottom = index * root.step + Theme.rowHeight;
        const maxY = Math.max(list.originY, list.originY + list.contentHeight - list.height);

        let y = scroller.running ? scroller.to : list.contentY;
        if (top < y) y = top;
        else if (bottom > y + list.height) y = bottom - list.height;
        y = Math.max(list.originY, Math.min(maxY, y));
        if (Math.abs(y - list.contentY) < 0.5) return;

        scroller.stop();
        scroller.from = list.contentY;
        scroller.to = y;
        scroller.start();
    }
}
