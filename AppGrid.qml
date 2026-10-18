import QtQuick
import QtQuick.Effects
import Quickshell

// The Launchpad grid: fixed columns, scrolling vertically under an edge fade,
// with one rounded highlight that glides between cells.
//
// It shows `entries` in the order given and reports cells by index; the
// panel maps those back to the shell's ranked list.
Item {
    id: root

    property var entries: []
    property int selectedIndex: -1
    property bool confirming: false

    signal tileHovered(int index, point scenePos)
    signal tileClicked(int index)

    readonly property alias view: grid

    GridView {
        id: grid

        anchors.fill: parent
        cellWidth: Theme.cellWidth
        cellHeight: Theme.cellHeight
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        cacheBuffer: Theme.cellHeight * 2
        reuseItems: true

        // Diffed by identity, so a keystroke that keeps an application in
        // the list keeps its delegate -- and its loaded icon -- too.
        model: ScriptModel {
            values: root.entries
        }

        delegate: AppTile {
            // cacheBuffer builds rows below the fold ahead of a scroll. Their
            // icons wait until the row is on screen: the image loader serves
            // the newest request first, so they would otherwise load ahead of
            // the icons that are actually visible.
            iconActive: {
                const top = Math.floor(index / Theme.gridColumns) * Theme.cellHeight;
                return top < grid.contentY + grid.height && top + Theme.cellHeight > grid.contentY;
            }
            selectedIndex: root.selectedIndex
            confirming: root.confirming
            onHovered: (index, scenePos) => root.tileHovered(index, scenePos)
            onClicked: index => root.tileClicked(index)
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

        anchors.fill: grid
        startStrength: grid.atYBeginning ? 0 : 1
        endStrength: grid.atYEnd ? 0 : 1
    }

    // ----------------------------------------------------------- highlight

    // Lives in the grid's content so it scrolls with the cells.
    Rectangle {
        id: highlight

        parent: grid.contentItem
        z: -1

        readonly property int column: Math.max(0, root.selectedIndex) % Theme.gridColumns
        readonly property int row: Math.floor(Math.max(0, root.selectedIndex) / Theme.gridColumns)

        x: highlight.column * Theme.cellWidth + Theme.tileInset
        y: highlight.row * Theme.cellHeight + Theme.tileInset
        width: Theme.cellWidth - 2 * Theme.tileInset
        height: Theme.cellHeight - 2 * Theme.tileInset
        radius: Theme.radiusTile
        color: root.confirming ? Theme.dangerFill : Theme.selectionFill
        opacity: root.selectedIndex >= 0 && root.selectedIndex < grid.count ? 1 : 0

        Behavior on x {
            enabled: root.glide
            NumberAnimation { duration: root.travel; easing.type: Easing.OutCubic }
        }
        Behavior on y {
            enabled: root.glide
            NumberAnimation { duration: root.travel; easing.type: Easing.OutCubic }
        }
        Behavior on color {
            ColorAnimation { duration: Theme.hoverDuration }
        }
    }

    // A new result set is a new page, not a move: the highlight lands on its
    // cell and the scroll returns to the top without travelling.
    property bool glide: true

    onEntriesChanged: {
        root.glide = false;
        scroller.stop();
        grid.contentY = grid.originY;
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

        target: grid
        property: "contentY"
        duration: Theme.scrollDuration
        easing.type: Easing.OutCubic
    }

    // Scroll just enough to bring a cell clear of the edge fades. Called for
    // keyboard moves only; a hovered cell is already where the pointer is.
    function reveal(index: int) {
        if (index < 0) return;

        const top = Math.floor(index / Theme.gridColumns) * Theme.cellHeight;
        const bottom = top + Theme.cellHeight;
        const margin = Theme.fadeSize;
        const maxY = Math.max(grid.originY, grid.originY + grid.contentHeight - grid.height);

        let y = scroller.running ? scroller.to : grid.contentY;
        if (top - margin < y) y = top - margin;
        else if (bottom + margin > y + grid.height) y = bottom + margin - grid.height;
        y = Math.max(grid.originY, Math.min(maxY, y));
        if (Math.abs(y - grid.contentY) < 0.5) return;

        scroller.stop();
        scroller.from = grid.contentY;
        scroller.to = y;
        scroller.start();
    }
}
