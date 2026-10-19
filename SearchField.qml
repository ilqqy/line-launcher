import QtQuick

// Spotlight's field: a magnifier, a large light-weight query and a clear
// button. No box of its own -- the panel is its frame, and a hairline under it
// separates it from the results.
Item {
    id: root

    readonly property alias text: input.text
    readonly property alias inputItem: input

    property string placeholder: ""
    // Set by the panel: Tab walks the category chips when there are any, and
    // Left/Right walk the grid while it has something in it. Otherwise both
    // keep their old meaning (Tab moves the selection, arrows move the caret).
    property bool tabCyclesCategories: false
    property bool arrowsNavigate: false

    signal accepted()
    signal cancelled()
    signal moveUp()
    signal moveDown()
    signal moveLeft()
    signal moveRight()
    signal pageUp()
    signal pageDown()
    signal nextCategory()
    signal previousCategory()
    // Emitted for every key press, so the shell can drop out of the confirm
    // state on "any other key".
    signal keyActivity(int key, int modifiers)

    implicitHeight: Theme.searchHeight

    MagnifierGlyph {
        id: glyph

        x: Theme.panelPadding
        anchors.verticalCenter: parent.verticalCenter
        size: Theme.searchGlyphSize
        color: Theme.glyph
    }

    TextInput {
        id: input

        anchors.left: glyph.right
        anchors.leftMargin: Theme.searchGap
        anchors.right: clear.left
        anchors.rightMargin: Theme.searchGap
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        verticalAlignment: TextInput.AlignVCenter
        // Room for the caret to sit centred on the boundary before the first
        // glyph instead of on top of it.
        leftPadding: 2

        color: Theme.textPrimary
        selectionColor: Theme.textSelection
        selectedTextColor: Theme.textPrimary
        font.family: Theme.displayFont
        font.pixelSize: Theme.searchFontSize
        font.weight: Theme.searchFontWeight

        focus: true
        activeFocusOnPress: true
        selectByMouse: true
        clip: true

        // An accent caret that holds solid while typing and blinks at rest.
        cursorDelegate: Item {
            id: caret

            width: 2
            visible: input.cursorVisible

            Rectangle {
                x: -1
                width: 2
                height: parent.height
                radius: 1
                color: Theme.caret
            }

            SequentialAnimation {
                id: blink

                loops: Animation.Infinite
                running: caret.visible

                PropertyAction { target: caret; property: "opacity"; value: 1 }
                PauseAnimation { duration: Theme.caretBlink }
                PropertyAction { target: caret; property: "opacity"; value: 0 }
                PauseAnimation { duration: Theme.caretBlink }
            }

            Connections {
                target: input
                function onCursorPositionChanged() { blink.restart(); }
                function onTextChanged() { blink.restart(); }
            }
        }

        Keys.onPressed: event => {
            event.accepted = root.handleKey(event.key, event.modifiers, event.isAutoRepeat);
        }
    }

    Text {
        anchors.fill: input
        leftPadding: input.leftPadding
        verticalAlignment: Text.AlignVCenter
        visible: input.text.length === 0 && input.preeditText.length === 0
        text: root.placeholder
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: Theme.placeholder
        font: input.font
    }

    Item {
        id: clear

        readonly property bool shown: input.text.length > 0

        anchors.right: parent.right
        anchors.rightMargin: Theme.panelPadding
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.clearSize
        height: Theme.clearSize

        opacity: clear.shown ? 1 : 0
        scale: clear.shown ? 1 : 0.7
        visible: clear.opacity > 0.01

        Behavior on opacity {
            NumberAnimation { duration: Theme.hoverDuration; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation { duration: Theme.hoverDuration; easing.type: Easing.OutCubic }
        }

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: clearMouse.containsMouse ? Theme.clearHoverFill : Theme.clearFill

            Behavior on color {
                ColorAnimation { duration: Theme.hoverDuration }
            }
        }

        Repeater {
            model: [45, -45]

            Rectangle {
                required property real modelData

                anchors.centerIn: parent
                width: Math.round(clear.width * 0.46)
                height: 1.6
                radius: 0.8
                rotation: modelData
                color: Theme.clearGlyph
                antialiasing: true
            }
        }

        MouseArea {
            id: clearMouse

            anchors.fill: parent
            anchors.margins: -6
            enabled: clear.shown
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                input.clear();
                input.forceActiveFocus();
            }
        }
    }

    // ---------------------------------------------------------------- API

    // The whole keymap, in one place and off the event object, so it can be
    // driven without a compositor. Takes what the event carries, returns
    // whether the key was consumed.
    function handleKey(key: int, modifiers: int, autoRepeat: bool): bool {
        const ctrl = (modifiers & Qt.ControlModifier) !== 0;
        const shift = (modifiers & Qt.ShiftModifier) !== 0;
        const accepts = key === Qt.Key_Return || key === Qt.Key_Enter || (ctrl && key === Qt.Key_M);
        // Holding Enter must not count as a second confirmation press.
        if (accepts && autoRepeat) return true;
        root.keyActivity(key, modifiers);

        if (key === Qt.Key_Escape) {
            root.cancelled();
            return true;
        }

        if (accepts) {
            root.accepted();
            return true;
        }

        // Shift+Tab reaches an item as Backtab, and on some platforms as Tab
        // with Shift still set, so both spellings go backwards.
        const backtab = key === Qt.Key_Backtab || (key === Qt.Key_Tab && shift);
        if (key === Qt.Key_Tab || backtab) {
            if (root.tabCyclesCategories) {
                if (backtab) root.previousCategory();
                else root.nextCategory();
            } else if (backtab) {
                root.moveUp();
            } else {
                root.moveDown();
            }
            return true;
        }

        if (key === Qt.Key_Up || (ctrl && key === Qt.Key_P)) {
            root.moveUp();
            return true;
        }

        if (key === Qt.Key_Down || (ctrl && key === Qt.Key_N)) {
            root.moveDown();
            return true;
        }

        // Plain Left/Right only: Shift extends the text selection and Ctrl
        // jumps words, as in any field.
        if (root.arrowsNavigate && !shift && !ctrl
                && (key === Qt.Key_Left || key === Qt.Key_Right)) {
            if (key === Qt.Key_Left) root.moveLeft();
            else root.moveRight();
            return true;
        }

        if (key === Qt.Key_PageUp) {
            root.pageUp();
            return true;
        }

        if (key === Qt.Key_PageDown) {
            root.pageDown();
            return true;
        }

        return false;
    }

    function focusInput() {
        input.forceActiveFocus();
    }

    function reset() {
        input.clear();
    }
}
