import QtQuick

// The input frame: one translucent box with a line extending from each side.
// Hyprland's layer blur sees the box's alpha and blurs only that region; the
// rest of the full-screen layer remains transparent.
//
// Everything here is positioned absolutely off `centreX`. Nothing lives in a
// Layout, so the close animation can move strokes around without ever
// triggering a relayout.
Item {
    id: root

    // ------------------------------------------------------------- outputs

    readonly property alias text: input.text
    readonly property alias inputItem: input

    // Exposed so tests can point at the field's text and prompt separately.
    readonly property alias promptItem: prompt
    readonly property alias queryAura: queryAura
    readonly property alias fillItem: frameBox
    readonly property alias leftWhiskerItem: leftWhisker
    readonly property alias rightWhiskerItem: rightWhisker
    readonly property real typedTextX:
        Math.max(0, (field.width - typedMetrics.advanceWidth) / 2)
    readonly property real typedTextWidth: typedMetrics.advanceWidth

    signal accepted()
    signal cancelled()
    signal moveUp()
    signal moveDown()
    // Emitted for every key press, so the shell can drop out of the confirm
    // state on "any other key".
    signal keyActivity(int key, int modifiers)

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
            duration: 90
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

    readonly property real strokeY: Config.snap(root.centreY - root.stroke / 2)

    implicitHeight: Config.frameHeight

    // The legibility halo under the strokes.
    //
    // One per whisker rather than one over the frame: each is a narrow
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
        anchors.fill: rightWhisker
        target: rightWhisker
    }

    // The whiskers meet the box at its vertical centre.
    Rectangle {
        id: leftWhisker
        width: Config.whiskerLength
        height: root.stroke
        color: Theme.foreground
        x: Config.snap(root.centreX - root.gap / 2 - width
            - root.slide - root.entryOffset)
        y: root.strokeY
    }

    Rectangle {
        id: rightWhisker
        width: Config.whiskerLength
        height: root.stroke
        color: Theme.foreground
        x: Config.snap(root.centreX + root.gap / 2
            + root.slide + root.entryOffset)
        y: root.strokeY
    }

    // --------------------------------------------------------- input field

    readonly property real fieldPadding: 12

    // The solid outline and translucent interior form the exact silhouette in
    // the sketch. The alpha is intentionally above Hyprland's ignore_alpha
    // threshold: it asks the compositor for blur without hiding it behind an
    // opaque panel.
    Rectangle {
        id: frameBox

        x: Config.snap(root.centreX - root.gap / 2)
        y: Config.snap(root.centreY - height / 2)
        width: Math.max(0, root.gap)
        height: Config.frameHeight
        radius: Config.cornerRadius

        color: Qt.alpha(Theme.background, Config.frameFillOpacity)
        border.width: root.stroke
        border.color: Theme.foreground
        visible: width > root.stroke
        z: -3
    }

    // The field's halo. Traced from the typed text and prompt, following the
    // field's own fade on close.
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
    // It traces `input` alone, not the whole field: the prompt is furniture,
    // not something the user typed.
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
        // Typed text is the active input, so give its accent a brighter halo
        // than the selection outline while leaving the prompt muted.
        strength: Math.min(1, Config.auraOpacity * 2.5)
        opacity: field.opacity
        z: -2
    }

    // Deliberately keyed off Config.frameWidth rather than the animated gap:
    // resizing the field mid-collapse would reflow the text. It fades instead.
    Item {
        id: field

        x: frameBox.x + root.fieldPadding
        y: frameBox.y + root.stroke
        width: Math.max(0, frameBox.width - root.fieldPadding * 2)
        height: Math.max(0, frameBox.height - root.stroke * 2)

        opacity: root.collapsing ? 0 : 1
        Behavior on opacity {
            NumberAnimation { duration: 80; easing.type: Easing.InQuad }
        }

        TextInput {
            id: input

            anchors.fill: parent
            verticalAlignment: TextInput.AlignVCenter
            horizontalAlignment: TextInput.AlignHCenter

            color: Theme.queryForeground
            selectionColor: Theme.activeAccent
            selectedTextColor: Theme.queryForeground
            font.pixelSize: Theme.fontSize
            font.family: Theme.fontFamily !== "" ? Theme.fontFamily : font.family
            font.weight: Font.DemiBold

            focus: true
            activeFocusOnPress: true
            selectByMouse: true
            clip: true

            Keys.onPressed: event => {
                event.accepted = root.handleKey(event.key, event.modifiers, event.isAutoRepeat);
            }
        }

        // Prompt / placeholder, shown only while the field is empty.
        Text {
            id: prompt

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            visible: input.text.length === 0 && Config.prompt !== ""
            text: Config.prompt
            textFormat: Text.PlainText
            color: Theme.muted
            font.pixelSize: input.font.pixelSize
            font.family: input.font.family
        }

        // Metrics for locating the centred typed run in rendering tests.
        TextMetrics {
            id: typedMetrics
            font.pixelSize: input.font.pixelSize
            font.family: input.font.family
            font.weight: input.font.weight
            text: input.text
        }

    }

    // ---------------------------------------------------------------- API

    // The whole keymap, in one place and off the event object: a QKeyEvent
    // cannot be constructed from QML, so inline handling could only ever be
    // tested by a real compositor delivering real keys. Takes what the event
    // carries, returns whether the key was consumed.
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
        // with Shift still set, so both spellings move up. Plain Tab moves
        // down.
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

    function focusInput() {
        input.forceActiveFocus();
    }
}
