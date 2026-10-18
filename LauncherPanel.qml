import QtQuick
import "launchpad.js" as Launchpad

// The launcher's visible surface: Spotlight's field on top, Launchpad's grid
// underneath, category chips between them.
//
// Presentation only. It is handed the shell's ranked list and selection and
// never reorders either -- with "All" active the grid *is* the ranked list,
// and any other chip only hides entries from it. Everything it wants done
// goes back through signals, so the shell keeps owning the selection,
// activation and closing.
Item {
    id: root

    // ------------------------------------------------------------- inputs

    property var results: []
    // Index into `results`, i.e. the shell's currentIndex. -1 means nothing
    // is selected, which is what a category with no matches asks for.
    property int currentIndex: 0
    property bool confirming: false
    property bool closing: false
    // DrunProvider's candidate records; the chips are derived from these.
    property var applications: []
    // Applications and actions go in the grid; dmenu lines and ">" commands
    // are text and go in rows.
    property bool gridMode: true
    property bool showRowIcons: true
    property string listTitle: ""
    property string placeholder: ""

    // ------------------------------------------------------------ outputs

    readonly property alias text: field.text
    // Exposed so tests can type and press keys without a compositor.
    readonly property alias field: field

    signal selectRequested(int index)
    signal accepted()
    signal cancelled()
    signal keyActivity(int key, int modifiers)

    function focusInput() {
        field.focusInput();
    }

    implicitWidth: Theme.panelWidth
    implicitHeight: Theme.panelHeight

    // --------------------------------------------------------- categories

    readonly property var chips: Launchpad.chipsFor(root.applications)
    property string category: Launchpad.allKey
    readonly property bool filtering: root.gridMode && root.category !== Launchpad.allKey
    readonly property var activeChip: {
        for (let i = 0; i < root.chips.length; i++) {
            if (root.chips[i].key === root.category) return root.chips[i];
        }
        return root.chips[0];
    }

    // ------------------------------------------------------- what is shown

    function computeShown(): var {
        if (!root.filtering) return root.results;
        const key = root.category;
        return root.results.filter(entry => Launchpad.entryIn(entry, key));
    }

    readonly property var shown: root.computeShown()

    // The selection as an index into `shown`, -1 for none.
    readonly property int selected: {
        const entry = root.currentIndex >= 0 ? root.results[root.currentIndex] : undefined;
        if (entry === undefined) return -1;
        return root.filtering ? root.shown.indexOf(entry) : root.currentIndex;
    }

    function select(viewIndex: int) {
        if (root.closing) return;
        const list = root.computeShown();
        if (viewIndex < 0 || viewIndex >= list.length) return;
        root.selectRequested(root.filtering ? root.results.indexOf(list[viewIndex]) : viewIndex);
    }

    // Unfiltered, the first result is the shell's own resting choice (0, even
    // with nothing there yet). Filtered, it is the first entry shown, or no
    // selection at all, so Enter on an empty category behaves like Enter on
    // an empty list.
    function selectFirst() {
        if (root.closing) return;
        if (!root.filtering) {
            root.selectRequested(0);
            return;
        }
        const list = root.computeShown();
        root.selectRequested(list.length > 0 ? root.results.indexOf(list[0]) : -1);
    }

    // The shell puts the selection back on its first result whenever the
    // query changes. Under a category that result may be hidden, so the
    // selection moves on to the first one shown -- once the new list has
    // settled, and before any key that reads the selection.
    property bool reselectPending: false

    onResultsChanged: {
        if (!root.filtering) return;
        root.reselectPending = true;
        Qt.callLater(root.flushReselect);
    }

    function flushReselect() {
        if (!root.reselectPending) return;
        root.reselectPending = false;
        root.selectFirst();
    }

    // Category changes count from the first one the user makes; the initial
    // value settling during construction is not a change.
    property bool built: false
    Component.onCompleted: root.built = true

    onCategoryChanged: {
        if (!root.built) return;
        root.reselectPending = false;
        root.selectFirst();
    }

    function cycleCategory(step: int) {
        if (root.chips.length < 2) return;
        let index = root.chips.indexOf(root.activeChip);
        index = (index + step + root.chips.length) % root.chips.length;
        root.category = root.chips[index].key;
    }

    // ---------------------------------------------------------- navigation

    // dx moves along the reading order, dy by whole rows. Up from the top row
    // stays put; down into a short last row lands on its last cell.
    function navigate(dx: int, dy: int) {
        root.flushReselect();
        if (root.closing) return;

        const count = root.shown.length;
        if (count === 0) return;

        const current = root.selected;
        let target;
        if (current < 0) {
            target = 0;
        } else if (!root.gridMode) {
            target = Math.max(0, Math.min(count - 1, current + dy));
        } else if (dy !== 0) {
            const columns = Theme.gridColumns;
            const lastRow = Math.floor((count - 1) / columns);
            const row = Math.floor(current / columns);
            const targetRow = Math.max(0, Math.min(lastRow, row + dy));
            target = Math.min(count - 1, targetRow * columns + current % columns);
        } else {
            target = Math.max(0, Math.min(count - 1, current + dx));
        }

        if (target === current) return;
        root.select(target);
        if (root.gridMode) grid.reveal(target);
        else rows.reveal(target);
    }

    function accept() {
        root.flushReselect();
        root.accepted();
    }

    // Hover selects only when the pointer itself moved. Qt also reports hover
    // when the panel opens under a resting pointer and when the grid scrolls
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

    GlassPanel {
        anchors.fill: parent
    }

    // Keeps clicks on the glass from reaching the dismiss area behind it.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
    }

    SearchField {
        id: field

        width: parent.width
        height: Theme.searchHeight
        placeholder: root.placeholder
        tabCyclesCategories: root.gridMode && root.chips.length > 1
        arrowsNavigate: root.gridMode && root.shown.length > 0

        onAccepted: root.accept()
        onCancelled: root.cancelled()
        onKeyActivity: (key, modifiers) => root.keyActivity(key, modifiers)
        onMoveUp: root.navigate(0, -1)
        onMoveDown: root.navigate(0, 1)
        onMoveLeft: root.navigate(-1, 0)
        onMoveRight: root.navigate(1, 0)
        onPageUp: root.navigate(0, -(root.gridMode ? Theme.pageRows : Theme.listPageRows))
        onPageDown: root.navigate(0, root.gridMode ? Theme.pageRows : Theme.listPageRows)
        onNextCategory: root.cycleCategory(1)
        onPreviousCategory: root.cycleCategory(-1)
    }

    Rectangle {
        y: Theme.searchHeight
        width: parent.width
        height: 1
        color: Theme.divider
    }

    CategoryBar {
        y: Theme.chipsY
        width: parent.width
        height: Theme.chipHeight
        visible: root.gridMode

        model: root.chips
        activeKey: root.category
        onActivated: key => root.category = key
    }

    Text {
        x: Theme.panelPadding
        y: Theme.chipsY
        width: parent.width - 2 * Theme.panelPadding
        height: Theme.chipHeight
        visible: !root.gridMode
        verticalAlignment: Text.AlignVCenter

        text: root.listTitle
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: Theme.textSecondary
        font.family: Theme.uiFont
        font.pixelSize: Theme.sectionFontSize
        font.weight: Theme.sectionFontWeight
    }

    AppGrid {
        id: grid

        x: Theme.panelPadding
        y: Theme.resultsY
        width: Theme.gridWidth
        height: Theme.resultsHeight
        visible: root.gridMode

        entries: root.gridMode ? root.shown : []
        selectedIndex: root.selected
        confirming: root.confirming

        onTileHovered: (index, scenePos) => root.hover(index, scenePos)
        onTileClicked: index => {
            root.select(index);
            root.accept();
        }
    }

    ResultRows {
        id: rows

        x: Theme.listInset
        y: Theme.resultsY
        width: parent.width - 2 * Theme.listInset
        height: Theme.resultsHeight
        visible: !root.gridMode

        entries: root.gridMode ? [] : root.shown
        selectedIndex: root.selected
        confirming: root.confirming
        showIcons: root.showRowIcons

        onRowHovered: (index, scenePos) => root.hover(index, scenePos)
        onRowClicked: index => {
            root.select(index);
            root.accept();
        }
    }

    EmptyState {
        x: 0
        y: Theme.resultsY
        width: parent.width
        height: Theme.resultsHeight

        readonly property string query: root.text.trim()
        readonly property string scope: root.filtering ? root.activeChip.label : ""

        shown: root.shown.length === 0
        title: {
            if (query !== "") return qsTr("No Results");
            if (root.filtering) return qsTr("No Recent Apps in %1").arg(scope);
            if (!root.gridMode) return qsTr("Nothing to Show");
            return qsTr("Start Typing to Search");
        }
        subtitle: {
            if (query !== "") {
                return root.filtering
                    ? qsTr("Nothing in %1 matches “%2”").arg(scope).arg(query)
                    : qsTr("Nothing matches “%1”").arg(query);
            }
            if (root.filtering) return qsTr("Type to search %1").arg(scope);
            return root.gridMode ? qsTr("Apps you open will show up here") : "";
        }
    }
}
