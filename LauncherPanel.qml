import QtQuick
import QtQuick.Effects

// The launcher's visible surface, laid out as a command palette: the search
// bar on top and the results as one list underneath.
//
// It opens collapsed to the search bar alone and expands downward to reveal
// the results once there is a query. Only `container`'s height animates; the
// item itself, the list and the window under it keep their size, so nothing
// is re-laid out or reallocated per frame -- the container's clip does the
// reveal. The shell masks the window's input to `container`, so the space
// below a collapsed bar passes clicks through.
//
// Presentation only. It is handed the shell's ranked list and selection and
// shows them as they are. Everything it wants done goes back through
// signals, so the shell keeps owning the selection, activation and closing.
Item {
    id: root

    // ------------------------------------------------------------- inputs

    property var results: []
    // Index into `results`, i.e. the shell's currentIndex. -1 means nothing
    // is selected.
    property int currentIndex: 0
    property bool confirming: false
    property bool closing: false
    // Ordinary search over applications, actions and commands. False for
    // dmenu lines and ">" commands, which are titled with `listTitle`.
    property bool appMode: true
    property bool showRowIcons: true
    property string listTitle: ""
    property string placeholder: ""

    // ------------------------------------------------------------ outputs

    readonly property alias text: field.text
    // Exposed so tests can type and press keys without a compositor.
    readonly property alias field: field
    // Exposed so tests can scroll and read back the reset.
    readonly property alias rows: rows
    // The visible panel; the window's input region.
    readonly property alias container: container

    // Results show while there is a query. Piped menus and ">" commands are
    // lists in their own right and always show.
    readonly property bool expanded: !root.appMode || root.text.trim().length > 0

    signal selectRequested(int index)
    signal accepted()
    signal cancelled()
    signal keyActivity(int key, int modifiers)

    function focusInput() {
        field.focusInput();
    }

    // Back to how a fresh launch looks: empty query, the list at its start,
    // and no remembered pointer position. The resident launcher calls this on
    // every show; the shell resets its own selection.
    function reset() {
        // Lands collapsed on the spot: a resident launcher resets while
        // hidden, and must not replay the collapse on its next show.
        root.animate = false;
        field.reset();
        root.lastPointer = Qt.point(-1, -1);
        rows.resetScroll();
        Qt.callLater(() => root.animate = true);
    }

    property bool animate: true

    // Collapsing puts the list back at its top with the first result
    // selected, so the next reveal starts clean.
    onExpandedChanged: {
        if (root.expanded) return;
        rows.resetScroll();
        if (!root.closing) root.selectRequested(0);
    }

    implicitWidth: Theme.panelWidth
    implicitHeight: Theme.panelHeight

    // The selection, -1 for none. Hidden results are never selected.
    readonly property int selected: root.expanded && root.currentIndex >= 0 && root.currentIndex < root.results.length
        ? root.currentIndex
        : -1

    function select(index: int) {
        if (root.closing || !root.expanded) return;
        if (index < 0 || index >= root.results.length) return;
        root.selectRequested(index);
    }

    // ---------------------------------------------------------- navigation

    // Moves the selection by `dy` rows, stopping at either end.
    function navigate(dy: int) {
        if (root.closing || !root.expanded) return;

        const count = root.results.length;
        if (count === 0) return;

        const current = root.selected;
        const target = current < 0 ? 0 : Math.max(0, Math.min(count - 1, current + dy));
        if (target === current) return;
        root.select(target);
        rows.reveal(target);
    }

    // Enter on a collapsed bar does nothing: there is nothing shown to run.
    function accept() {
        if (!root.expanded) return;
        root.accepted();
    }

    // Hover selects only when the pointer itself moved. Qt also reports hover
    // when the panel opens under a resting pointer and when the list scrolls
    // beneath one; those arrive at the scene position already recorded, and
    // must not take the selection away from the keyboard.
    property point lastPointer: Qt.point(-1, -1)

    function hover(viewIndex: int, scenePos: point) {
        const moved = root.lastPointer.x >= 0
            && (Math.abs(scenePos.x - root.lastPointer.x) > 1 || Math.abs(scenePos.y - root.lastPointer.y) > 1);
        root.lastPointer = scenePos;
        if (moved) root.select(viewIndex);
    }

    // ------------------------------------------------------------- surface

    // How tall the revealed part is: the results' own height, up to the
    // list's full height, or room for the empty-state message.
    readonly property int revealHeight: {
        const count = root.results.length;
        if (count === 0) return Theme.emptyHeight;
        const content = 2 * Theme.listPaddingY + Theme.sectionHeight + count * rows.step;
        return Math.min(Theme.resultsHeight, content);
    }

    // Shader-drawn, so following the container's height costs no layer
    // reallocation. It also lies under the fill; at the panel's opacity
    // that adds about 2% darkening there, which does not read as a band.
    RectangularShadow {
        x: container.x
        y: container.y + Theme.shadowOffsetY
        width: container.width
        height: container.height
        radius: Theme.radiusPanel
        blur: Theme.shadowBlur
        color: Theme.shadowColor
    }

    Rectangle {
        id: container

        anchors.top: parent.top
        width: parent.width
        height: root.expanded ? Theme.resultsY + root.revealHeight : Theme.searchHeight
        radius: Theme.radiusPanel
        color: Theme.panelFill
        border.width: 1
        border.color: Theme.panelBorder
        clip: true

        Behavior on height {
            enabled: root.animate
            NumberAnimation { duration: Theme.expandDuration; easing.type: Easing.OutCubic }
        }

        SearchField {
            id: field

            width: parent.width
            height: Theme.searchHeight
            placeholder: root.placeholder

            onAccepted: root.accept()
            onCancelled: root.cancelled()
            onKeyActivity: (key, modifiers) => root.keyActivity(key, modifiers)
            onMoveUp: root.navigate(-1)
            onMoveDown: root.navigate(1)
            onPageUp: root.navigate(-Theme.listPageRows)
            onPageDown: root.navigate(Theme.listPageRows)
        }

        // The divider, header and rows sit below the bar, so the clip keeps
        // them out of a collapsed panel; the fade softens the reveal.
        Item {
            id: revealed

            y: Theme.searchHeight
            width: parent.width
            height: Theme.resultsHeight + 1

            opacity: root.expanded ? 1 : 0
            visible: opacity > 0

            Behavior on opacity {
                enabled: root.animate
                NumberAnimation { duration: Theme.revealFadeDuration; easing.type: Easing.OutQuad }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.divider
            }

            // A fixed height, whatever the container's: resizing a ListView
            // re-lays out and creates delegates on every frame.
            ResultRows {
                id: rows

                x: Theme.listInset
                y: 1
                width: parent.width - 2 * Theme.listInset
                height: Theme.resultsHeight

                entries: root.results
                selectedIndex: root.selected
                confirming: root.confirming
                showIcons: root.showRowIcons
                title: {
                    if (!root.appMode) return root.listTitle;
                    return root.text.trim() === "" ? qsTr("Suggestions") : qsTr("Results");
                }

                onRowHovered: (index, scenePos) => root.hover(index, scenePos)
                onRowClicked: index => {
                    root.select(index);
                    root.accept();
                }
            }

            EmptyState {
                y: 1
                width: parent.width
                height: Theme.emptyHeight

                readonly property string query: root.text.trim()

                shown: root.results.length === 0
                title: query !== "" ? qsTr("No Results") : qsTr("Nothing to Show")
                subtitle: query !== "" ? qsTr("Nothing matches “%1”").arg(query) : ""
            }
        }
    }
}
