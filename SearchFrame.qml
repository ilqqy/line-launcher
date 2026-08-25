import QtQuick

// The input frame: two whiskers, the field between them, and the ghost
// completion.
//
// Everything here is positioned absolutely off `centreX`. Nothing lives in a
// Layout, so the close animation can move strokes around without ever
// triggering a relayout.
Item {
    id: root

    // ------------------------------------------------------------- outputs

    readonly property alias text: input.text
    readonly property alias inputItem: input

    // Exposed so tests can point at the three pieces of text the field draws
    // and check each one separately.
    readonly property alias promptItem: prompt
    readonly property alias ghostItem: ghost
    readonly property alias queryAura: queryAura

    // Full name of the current top result. When the typed text is a prefix of
    // it, the remainder is drawn as ghost text. Set by the shell; when the
    // match is fuzzy but not a prefix this will not start with `text` and no
    // ghost is drawn.
    property string completion: ""

    // Provider prefix currently in force, e.g. ">". Result names never include
    // it, so the ghost compares against the query rather than the raw field.
    property string prefix: ""

    readonly property string query: root.text.startsWith(root.prefix)
        ? root.text.substring(root.prefix.length)
        : root.text

    readonly property bool ghostVisible: Config.ghostEnabled
        && root.query.length > 0
        && root.completion.length > root.query.length
        && root.completion.toLowerCase().startsWith(root.query.toLowerCase())

    readonly property string ghostText: root.ghostVisible
        ? root.completion.substring(root.query.length)
        : ""

    signal accepted()
    signal cancelled()
    signal moveUp()
    signal moveDown()
    // Nothing emits this since Tab became a move key. The ghost is still drawn
    // and acceptCompletion() still works; it just has no key on it, so this is
    // kept as the hook for whichever key takes the job next.
    signal completionRequested()
    // Emitted for every key press, so the shell can drop out of the confirm
    // state on "any other key".
    signal keyActivity(int key)

    // ----------------------------------------------------- entry animation

    // Raised by the shell once the window is actually on screen. The monitor
    // is not known at component completion, so the window spends its first
    // frames hidden; starting the entrance there would play it to nobody.
    property bool revealed: false

    // 1 is off-screen, 0 is home. Deliberately not `slide`: a close landing
    // mid-entrance would then be two animations fighting over one property.
    property real entry: root.revealed ? 0 : 1

    Behavior on entry {
        NumberAnimation {
            // Slower than the 160ms close and eased the other way round: the
            // whiskers arrive fast and settle, rather than leaving slowly.
            duration: 320
            easing.type: Easing.OutCubic
        }
    }

    // The distance each side covers on the way in: a tenth of the way out
    // towards the screen edge, so the frame gathers itself rather than flying
    // in from off-screen. Short travel over a long duration -- the strokes
    // drift into place rather than snapping.
    readonly property real entryDistance: root.width / 2 * 0.1

    // Both strokes on a side move by this together, so the hook stays attached
    // to the end of its whisker for the whole travel.
    readonly property real entryOffset: root.entry * root.entryDistance

    // ------------------------------------------------------ close animation

    // Driven by the shell. `collapsing` is the Enter animation; the Esc
    // animation is a plain fade handled one level up, so the two read
    // differently.
    property bool collapsing: false

    readonly property real stroke: Config.strokeWidth
    readonly property real gap: Config.frameWidth * root.gapScale

    property real gapScale: 1
    property real slide: 0

    states: State {
        name: "collapsed"
        when: root.collapsing
        PropertyChanges {
            root.gapScale: 0
            root.slide: root.width
        }
    }

    transitions: Transition {
        NumberAnimation {
            properties: "gapScale"
            duration: 160
            easing.type: Easing.InCubic
        }
        NumberAnimation {
            properties: "slide"
            duration: 160
            easing.type: Easing.InQuad
        }
    }

    // -------------------------------------------------------------- layout

    readonly property real centreX: root.width / 2
    readonly property real centreY: root.height / 2

    readonly property real leftHookX: Config.snap(root.centreX - root.gap / 2 - root.stroke)
    readonly property real rightHookX: Config.snap(root.centreX + root.gap / 2)
    readonly property real strokeY: Config.snap(root.centreY - root.stroke / 2)
    readonly property real hookY: Config.snap(root.centreY - Config.hookLength / 2)

    implicitHeight: Math.max(Config.hookLength, input.implicitHeight)

    // The legibility halo under the strokes.
    //
    // One per stroke rather than one over the frame: each is a 50x2 or 2x16
    // rectangle whose colour changes only when the palette reloads, so each
    // traced texture is rendered once and then only moved. Tracing the frame
    // as a whole would mean a texture as wide as the screen -- the frame is a
    // full-width item with a few hundred pixels of content in the middle of
    // it -- and it would be re-rendered every time any one stroke slid.
    Glow {
        anchors.fill: leftWhisker
        target: leftWhisker
    }

    Glow {
        anchors.fill: leftHook
        target: leftHook
    }

    Glow {
        anchors.fill: rightHook
        target: rightHook
    }

    Glow {
        anchors.fill: rightWhisker
        target: rightWhisker
    }

    // The strokes themselves only ever move on open and on close: each side --
    // whisker and hook together -- gathers inwards on entry and leaves the
    // same way.
    Rectangle {
        id: leftWhisker
        width: Config.whiskerLength
        height: root.stroke
        color: Theme.foreground
        x: root.leftHookX - width - root.slide - root.entryOffset
        y: root.strokeY
    }

    Rectangle {
        id: leftHook
        width: root.stroke
        height: Config.hookLength
        color: Theme.foreground
        x: root.leftHookX - root.entryOffset
        y: root.hookY
    }

    Rectangle {
        id: rightHook
        width: root.stroke
        height: Config.hookLength
        color: Theme.foreground
        x: root.rightHookX + root.entryOffset
        y: root.hookY
    }

    Rectangle {
        id: rightWhisker
        width: Config.whiskerLength
        height: root.stroke
        color: Theme.foreground
        x: root.rightHookX + root.stroke + root.slide + root.entryOffset
        y: root.strokeY
    }

    // --------------------------------------------------------- input field

    readonly property real fieldPadding: 12

    // The field's halo. Traced from the whole field -- typed text, prompt and
    // ghost -- so all three get the same treatment, and following the field's
    // own fade on close.
    //
    // A sibling of the field rather than a child of it: an effect that traced
    // its own parent would be tracing itself.
    //
    // The field is not hidden behind it. MultiEffect's documented use is to
    // stand in for its source, which means making the source invisible, and an
    // invisible TextInput takes neither focus nor mouse clicks: no caret, no
    // click-to-position, no selection. So the halo goes behind a field that is
    // still a real, live, natively-rendered TextInput.
    Glow {
        anchors.fill: field
        target: field
        opacity: field.opacity
    }

    // The accent aura, on the typed query.
    //
    // The same halo the selection outline wears, in the same colour and at the
    // same radius, so the two things the user is steering -- what they typed
    // and what it has landed on -- light up together.
    //
    // It traces `input` alone, not the whole field: the ghost is a suggestion
    // and the prompt is furniture, and neither is something the user typed.
    // Drawing it from out here rather than inside the field also keeps it out
    // of the legibility halo's source, which would otherwise trace this and
    // wrap the aura in a second, background-coloured one. `input` fills the
    // field exactly, so the field's rectangle is its rectangle.
    //
    // Behind the legibility halo, which is tighter: the dark rim does the
    // reading, the accent spreads past it.
    Glow {
        id: queryAura

        anchors.fill: field
        target: input
        colour: Theme.activeAccent
        blurRadius: Config.auraRadius
        strength: Config.auraOpacity
        opacity: field.opacity
        z: -2
    }

    // Deliberately keyed off Config.frameWidth rather than the animated gap:
    // resizing the field mid-collapse would reflow the text. It fades instead.
    Item {
        id: field

        x: Config.snap(root.centreX - Config.frameWidth / 2) + root.fieldPadding
        width: Config.frameWidth - root.fieldPadding * 2
        height: input.implicitHeight
        y: Config.snap(root.centreY - height / 2)

        opacity: root.collapsing ? 0 : 1
        Behavior on opacity {
            NumberAnimation { duration: 80; easing.type: Easing.InQuad }
        }

        TextInput {
            id: input

            anchors.fill: parent
            verticalAlignment: TextInput.AlignVCenter
            horizontalAlignment: TextInput.AlignLeft

            color: Theme.foreground
            selectionColor: Theme.activeAccent
            selectedTextColor: Theme.foreground
            font.pixelSize: Theme.fontSize
            font.family: Theme.fontFamily !== "" ? Theme.fontFamily : font.family

            focus: true
            activeFocusOnPress: true
            selectByMouse: true
            clip: true

            // Ghost text must never enter this property. Writing the
            // completion into `text` would move the caret to the end of the
            // suggestion and make Backspace delete characters the user never
            // typed.
            Keys.onPressed: event => {
                event.accepted = root.handleKey(event.key, event.modifiers);
            }
        }

        // Prompt / placeholder, shown only while the field is empty.
        Text {
            id: prompt

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            visible: input.text.length === 0 && Config.prompt !== ""
            text: Config.prompt
            color: Theme.muted
            font: input.font
        }

        // Ghost completion. A separate Text, positioned from the metrics of
        // the real field rather than living inside it.
        TextMetrics {
            id: typedMetrics
            font: input.font
            text: input.text
        }

        Text {
            id: ghost
            x: typedMetrics.advanceWidth
            anchors.verticalCenter: parent.verticalCenter
            visible: root.ghostVisible
            text: root.ghostText
            color: Theme.muted
            font: input.font
            // The ghost is decoration: it must never intercept clicks or
            // widen the field.
            width: Math.max(0, parent.width - x)
            elide: Text.ElideRight
        }
    }

    // ---------------------------------------------------------------- API

    // The whole keymap, in one place and off the event object: a QKeyEvent
    // cannot be constructed from QML, so inline handling could only ever be
    // tested by a real compositor delivering real keys. Takes what the event
    // carries, returns whether the key was consumed.
    function handleKey(key: int, modifiers: int): bool {
        root.keyActivity(key);

        const ctrl = (modifiers & Qt.ControlModifier) !== 0;
        const shift = (modifiers & Qt.ShiftModifier) !== 0;

        if (key === Qt.Key_Escape) {
            root.cancelled();
            return true;
        }

        if (key === Qt.Key_Return || key === Qt.Key_Enter || (ctrl && key === Qt.Key_M)) {
            root.accepted();
            return true;
        }

        // Shift+Tab reaches an item as Backtab, and on some platforms as Tab
        // with Shift still set, so both spellings move up. Plain Tab is the
        // down key -- it used to accept the ghost completion, and nothing
        // takes that job now.
        if (key === Qt.Key_Up || (ctrl && key === Qt.Key_P)
                || key === Qt.Key_Backtab || (key === Qt.Key_Tab && shift)) {
            root.moveUp();
            return true;
        }

        if (key === Qt.Key_Down || (ctrl && key === Qt.Key_N) || key === Qt.Key_Tab) {
            root.moveDown();
            return true;
        }

        return false;
    }

    function acceptCompletion() {
        if (!root.ghostVisible) return;
        input.text = root.prefix + root.completion;
        input.cursorPosition = input.text.length;
    }

    function focusInput() {
        input.forceActiveFocus();
    }
}
