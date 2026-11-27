import QtQuick

// The search bar: one large query on the panel itself, no box of its own --
// the panel is its frame, and a hairline under it separates it from the
// results.
Item {
    id: root

    readonly property alias text: input.text
    readonly property alias inputItem: input

    property string placeholder: ""

    signal accepted()
    signal cancelled()
    signal moveUp()
    signal moveDown()
    signal pageUp()
    signal pageDown()
    // Emitted for every key press, so the shell can drop out of the confirm
    // state on "any other key".
    signal keyActivity(int key, int modifiers)

    implicitHeight: Theme.searchHeight

    TextInput {
        id: input

        anchors.left: parent.left
        anchors.leftMargin: Theme.listInset + Theme.rowPaddingX
        anchors.right: parent.right
        anchors.rightMargin: Theme.listInset + Theme.rowPaddingX
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        verticalAlignment: TextInput.AlignVCenter
        // Room for the caret to sit centred on the boundary before the first
        // glyph instead of on top of it.
        leftPadding: 2

        color: Theme.textPrimary
        selectionColor: Theme.textSelection
        selectedTextColor: Theme.textPrimary
        font.family: Theme.uiFont
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
            if (backtab) {
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
