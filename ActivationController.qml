import QtQuick

// Confirmation belongs to a specific result. Lock before emitting launch so
// synchronous history updates and keys during the exit animation cannot rerun it.
QtObject {
    id: root

    property var selectedItem: null
    property var armedItem: null
    property bool closing: false
    readonly property bool confirming: root.armedItem !== null

    signal launch(var item)
    signal cancel()

    onSelectedItemChanged: root.armedItem = null

    function activate() {
        if (root.closing) return;
        const item = root.selectedItem;
        if (!item) {
            root.closing = true;
            root.cancel();
            return;
        }
        if (item.confirm && root.armedItem !== item) {
            root.armedItem = item;
            return;
        }
        root.closing = true;
        root.armedItem = null;
        root.launch(item);
    }

    function keyActivity(key: int, modifiers: int) {
        if (key === Qt.Key_Return || key === Qt.Key_Enter
                || (key === Qt.Key_M && (modifiers & Qt.ControlModifier) !== 0)) return;
        if ([Qt.Key_Control, Qt.Key_Shift, Qt.Key_Alt, Qt.Key_Meta,
                Qt.Key_AltGr, Qt.Key_CapsLock, Qt.Key_NumLock,
                Qt.Key_ScrollLock].indexOf(key) >= 0) return;
        root.armedItem = null;
    }
}
