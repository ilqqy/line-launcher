import QtQuick

// The result lane.
//
// Two distinct states, not one continuous scroll:
//
//   1. While the selection is inside the visible window, `laneY` is 0 and the
//      rows do not move at all. Only the outline travels.
//   2. Once the selection would leave that window, `firstVisible` advances,
//      `laneY` slides by whole row steps, and the selection pins to the edge.
//
// Row positions therefore never depend on the selection -- tests/lane.qml
// asserts laneY stays 0 across the first visibleItems-1 moves. The perspective
// is anchored to the top of the visible window for the same reason: anchoring
// it to the active row would drag every distant row around as the selection
// moved, which is not what "the lane stays put" means.
//
// This file is provider-agnostic: it reads `name` and `icon` off result
// objects and nothing else.
Item {
    id: root

    property var results: []
    property int currentIndex: 0
    property bool confirming: false
    property bool collapsing: false
    property color accent: Theme.activeAccent

    readonly property int count: root.results.length
    readonly property int visibleItems: Config.visibleItems

    readonly property real rowStep: Config.rowStep
    readonly property real rowHeight: Config.rowHeight

    clip: false

    // ------------------------------------------------------------ scrolling

    // Index of the row in the top slot. Derived from currentIndex, never the
    // other way round.
    property int firstVisible: 0

    readonly property real targetLaneY: -root.firstVisible * root.rowStep

    // The lane's scroll offset, and the only thing that moves the rows.
    // Plain easing, not a spring: this drives row positions.
    property real laneY: root.targetLaneY

    readonly property int slideDuration: 150

    Behavior on laneY {
        NumberAnimation {
            // Shortened, never switched off: see the held-key note below.
            duration: root.chasing ? root.chaseDuration : root.slideDuration
            easing.type: Easing.OutCubic
        }
    }

    // ----------------------------------------------------------- held keys

    // A held key repeats every ~33ms, and the lane's slide takes 150ms, so
    // under auto-repeat each move restarts a journey the last one never
    // finished and the shortfall accumulates. Measured before this existed,
    // holding a key put the outline 1.9 rows behind the selection going down
    // and 4.1 rows off going up -- the lane sliding somewhere the selection
    // was not, and the selection itself pushed out of the visible window.
    //
    // The travel is shortened rather than switched off. Cutting the animation
    // outright does fix the drift, but then the rows teleport a step at a time
    // and the names snap from slot to slot. Instead both the lane and the
    // outline are given the repeat's own interval to cover one step: each move
    // lands about when the next arrives, so nothing accumulates and the lane
    // still slides continuously under the names.
    //
    // Everything returns to the full 150ms slide on the first move that
    // arrives after a gap -- which is the move the user is actually watching,
    // rather than one frame of a blur.
    property double lastMoveAt: 0
    property bool chasing: false

    // How long one step gets while the key is held: the repeat's own interval,
    // so a step finishes as the next one starts and no residue carries over.
    // Anything longer leaves a fraction of every step unfinished and the
    // fractions add up -- at a 50ms floor against a 33ms repeat the outline
    // still ended up 1.4 rows out.
    //
    // Floored at two frames rather than at nothing: that is the shortest
    // travel that is still travel, and it keeps a very fast repeat rate from
    // turning back into the teleport this replaced. Capped at the resting
    // slide, so this only ever shortens.
    readonly property int minTravel: 33

    property int chaseDuration: root.slideDuration

    function noteMove() {
        const now = Date.now();
        const gap = now - root.lastMoveAt;

        root.chasing = gap < root.slideDuration;
        if (root.chasing) {
            root.chaseDuration =
                Math.max(root.minTravel, Math.min(root.slideDuration, gap));
        }

        root.lastMoveAt = now;
    }

    function ensureVisible() {
        if (root.currentIndex < root.firstVisible) {
            root.firstVisible = root.currentIndex;
        } else if (root.currentIndex > root.firstVisible + root.visibleItems - 1) {
            root.firstVisible = root.currentIndex - root.visibleItems + 1;
        }
    }

    onCurrentIndexChanged: {
        root.noteMove();
        root.ensureVisible();
    }

    onResultsChanged: {
        // A new query is not a held key: the selection returns to the top on
        // the full slide however fast the typing was.
        root.chasing = false;
        root.lastMoveAt = 0;
        root.firstVisible = 0;
        root.ensureVisible();
    }

    // Untransformed position of a row, in lane coordinates. A pure function of
    // the index and the scroll offset.
    function rowBaseY(index: int): real {
        return root.laneY + index * root.rowStep;
    }

    // ---------------------------------------------------------- perspective

    // How much of the projection to apply, 0 to 1. At 0 the lane is a straight
    // dropdown: no tilt, no recede, and every function below collapses to the
    // flat case -- projectionFor returns 1, projectedCentre becomes the plain
    // row grid, and rowMatrix comes out an identity. Everything derives from
    // this one number rather than being switched on separately, so the flat
    // lane and the fan cannot disagree about where a row sits.
    // Writable, unlike the rest of the geometry: tests/lane.qml drives both the
    // flat lane and the full fan through it in one run.
    property real perspective: Config.listPerspective

    readonly property real anglePerStep: 22 * root.perspective
    readonly property real maxAngle: 55
    readonly property real perspectiveDepth: 800

    // How far each row below the window top is pushed away from the viewer.
    // The vertical step shrinking with distance falls out of the projection of
    // that depth; it is not applied to the positions directly.
    readonly property real depthPerStep: 60 * root.perspective

    function depthFor(slot: real): real {
        return -root.depthPerStep * Math.max(0, slot);
    }

    // The perspective divisor for a row that far down the lane.
    function projectionFor(slot: real): real {
        return 1 - root.depthFor(slot) / root.perspectiveDepth;
    }

    // Where a row's centre actually lands once projected.
    function projectedCentre(slot: real): real {
        return (slot * root.rowStep + root.rowHeight / 2) / root.projectionFor(slot);
    }

    implicitHeight: root.projectedCentre(root.visibleItems - 1)
        + root.rowHeight / (2 * root.projectionFor(root.visibleItems - 1))

    // How faint the last row in the window is. The ramp runs from full strength
    // at the top slot down to this at the bottom one.
    readonly property real tailOpacity: 0.45

    // Rows fade with how far down the lane they sit, not with how far they are
    // from the selection. Keying it to the selection meant the whole list
    // breathed every time the highlight moved -- rows brightening and dimming
    // under a selection that was itself already marked, by the outline, in the
    // accent colour. The lane now looks the same wherever the selection is.
    //
    // Takes a slot, so it is a property of the row's place in the window and
    // fractional while the lane slides.
    function opacityFor(slot: real): real {
        // Above the top of the window: on its way out.
        if (slot < 0) return Math.max(0, 1 + slot);

        const span = Math.max(1, root.visibleItems - 1);
        if (slot <= span) return 1 - (1 - root.tailOpacity) * (slot / span);

        // The spare slot below the window, so a row scrolling in rises from
        // nothing rather than appearing at the tail strength.
        return Math.max(0, root.tailOpacity * (1 - (slot - span)));
    }

    // True perspective, not a scale. The row is tilted about its own centre by
    // an angle proportional to its distance from the active row, pushed back
    // down the lane, and then projected -- so the w component depends on z and
    // the step between rows converges.
    //
    // The projection is taken about the top of the visible window: that is the
    // vanishing point, horizontally the centre of the lane and vertically the
    // window top. Anchoring it to the active row instead would drag every
    // distant row around as the selection moved, which is not what "the lane
    // stays put" means.
    //
    // The anchor has to bracket the perspective, not follow it. A perspective
    // matrix divides about the origin of the space it is applied in, so
    // projecting about A means T(A) * P * T(-A). Written the other way round
    // -- P * T(A) -- the translation commutes straight through the z shift and
    // cancels, the projection happens about each row's own top-left corner
    // instead, and rows shrink towards their own left edge rather than
    // converging on anything. That also puts them somewhere projectedCentre()
    // does not predict: measured, the gap between where a row was drawn and
    // where the outline was placed for it grew from 3px at the first slot to
    // 23px at the fourth.
    function rowMatrix(slot: real, distance: real, itemWidth: real, itemHeight: real): var {
        const angle = Math.max(-root.maxAngle,
            Math.min(root.maxAngle, -distance * root.anglePerStep));

        const centreX = itemWidth / 2;
        const centreY = itemHeight / 2;

        // The vanishing point, in this row's local coordinates.
        const anchorX = centreX;
        const anchorY = -slot * root.rowStep;

        const anchor = Qt.matrix4x4();
        anchor.translate(Qt.vector3d(anchorX, anchorY, 0));

        const perspective = Qt.matrix4x4();
        perspective.m43 = -1 / root.perspectiveDepth;

        const local = Qt.matrix4x4();
        // Read bottom-up: tilt about the row's own centre, recede down the
        // lane, then bring the vanishing point to the origin for the divide.
        local.translate(Qt.vector3d(-anchorX, -anchorY, 0));
        local.translate(Qt.vector3d(0, 0, root.depthFor(slot)));
        local.translate(Qt.vector3d(centreX, centreY, 0));
        local.rotate(angle, Qt.vector3d(1, 0, 0));
        local.translate(Qt.vector3d(-centreX, -centreY, 0));

        const composed = anchor.times(perspective).times(local);

        // Flatten the result's z row.
        //
        // The renderer clips in a shallow depth range around z = 0, and the
        // recede above leaves every row below the first sitting at z = -60,
        // -120, -180 and so on -- well outside it. Measured, on both llvmpipe
        // and the real GPU: with depthPerStep at 60 only the top row survives;
        // dropping it to 5 brings every row back. Nothing else about the lane
        // is wrong, the rows are simply thrown away before they are drawn.
        //
        // Zeroing this row does not touch the projection. m43 acts on the
        // *input* z, so the w component -- the entire perspective divide, tilt
        // included -- is carried by the fourth row and survives untouched.
        // The third row only decides what depth the renderer files the result
        // under, and in a 2D scene that is nothing anyone needs.
        composed.m31 = 0;
        composed.m32 = 0;
        composed.m33 = 0;
        composed.m34 = 0;

        return composed;
    }

    // Where a row's centre actually lands, measured off the matrix rather than
    // asserted alongside it. tests/lane.qml checks the two against each other
    // at every visible slot, because they disagreeing silently is exactly what
    // went wrong before.
    function projectedRowCentre(slot: real, distance: real): real {
        const matrix = root.rowMatrix(slot, distance, root.laneWidth, root.rowHeight);
        const centre = matrix.times(Qt.vector4d(root.laneWidth / 2, root.rowHeight / 2, 0, 1));
        return slot * root.rowStep + centre.y / centre.w;
    }

    // ---------------------------------------------------------------- rows

    // One slot more than is nominally visible, so a row scrolling in from
    // below fades up rather than appearing at full strength.
    readonly property int renderSlots: root.visibleItems + 1

    readonly property real laneWidth: Config.frameWidth
    readonly property real laneX: Config.snap((root.width - root.laneWidth) / 2)

    Repeater {
        model: root.renderSlots

        delegate: ResultItem {
            id: row

            required property int index

            readonly property int absoluteIndex: root.firstVisible + row.index
            readonly property bool present: row.absoluteIndex >= 0 && row.absoluteIndex < root.count
            readonly property var entry: row.present ? root.results[row.absoluteIndex] : null

            // Position in the lane, and distance from the travelling
            // selection. The first drives geometry, the second only the tilt.
            readonly property real slot: root.rowBaseY(row.absoluteIndex) / root.rowStep
            readonly property real distance: row.slot - outline.position

            width: root.laneWidth
            height: root.rowHeight
            x: root.laneX
            y: Config.snap(root.rowBaseY(row.absoluteIndex))

            visible: row.present && row.opacity > 0.01
            opacity: root.collapsing ? 0 : root.opacityFor(row.slot)

            name: row.entry ? row.entry.name : ""
            iconSource: row.entry ? row.entry.icon : ""
            active: row.absoluteIndex === root.currentIndex

            transform: Matrix4x4 {
                matrix: root.rowMatrix(row.slot, row.distance, row.width, row.height)
            }

            Behavior on opacity {
                enabled: root.collapsing
                NumberAnimation {
                    duration: 160
                    easing.type: Easing.InQuad
                }
            }
        }
    }

    // ------------------------------------------------------------- outline

    SelectionOutline {
        id: outline

        // The outline is never transformed. It is drawn where the row it sits
        // on has been projected to, which means taking the projection by hand
        // -- and in both axes. Rows converge on the lane's centre line as they
        // recede, so an outline that kept its full width would stand proud of
        // the row it is meant to be hugging by the fourth slot.
        readonly property real projection: root.projectionFor(outline.position)

        width: root.laneWidth / outline.projection
        x: Config.snap(root.laneX + (root.laneWidth - outline.width) / 2)

        // The selection's slot in the visible window, and nothing else.
        //
        // This used to be measured off rowBaseY(), which is built on the
        // animated `laneY` -- so it came out as the window slot plus whatever
        // the lane's easing had not caught up on yet, and the outline drifted
        // along with that error every time the lane slid. Under a held key the
        // error never resolved and the highlight ended up rows away from the
        // selection.
        //
        // Both terms here change only when something really happens. Moving
        // inside the window changes currentIndex, and the outline travels one
        // row. Scrolling changes both by one, which cancels: the selection is
        // pinned to the edge, so the outline holds still and the rows slide
        // underneath it -- which is what "the lane stays put" meant all along.
        targetPosition: root.currentIndex - root.firstVisible

        // The same clock the rows move on, held keys included.
        travelDuration: root.chasing ? root.chaseDuration : root.slideDuration

        // Projected to match whichever row it is sitting on.
        centreY: root.projectedCentre(outline.position)
        heightScale: 1 / outline.projection

        strokeColour: root.confirming ? Theme.danger : root.accent
        collapsing: root.collapsing
        visible: root.count > 0
        opacity: root.collapsing ? 0 : 1

        Behavior on opacity {
            enabled: root.collapsing
            NumberAnimation {
                duration: 160
                easing.type: Easing.InQuad
            }
        }
    }

    // Exposed for tests: the outline is the shell's only per-frame work, and
    // tests/spring.qml asserts it comes to a complete stop.
    readonly property alias settling: outline.settling
    readonly property alias outlineCentre: outline.centreY
    readonly property alias outlinePosition: outline.position
    readonly property alias outlineTarget: outline.targetPosition
    readonly property alias outlineVelocity: outline.velocity
    readonly property alias outlineSamples: outline.sampleCount
    readonly property alias auraActive: outline.auraActive

    // ------------------------------------------------------------- counter

    // The counter's halo. It sits outside the frame, over bare wallpaper, with
    // nothing else near it -- so it is the first thing to disappear on a pale
    // background and the clearest case for the glow.
    Glow {
        anchors.fill: counter
        target: counter
        visible: counter.visible
    }

    Text {
        id: counter

        x: Config.snap(outline.x + outline.width + 12)
        y: Config.snap(outline.centreY - height / 2)

        visible: root.count > 0 && !root.collapsing

        // The counter is where the confirm state announces itself, in place of
        // the position readout.
        text: root.confirming
            ? qsTr("confirm")
            : (root.currentIndex + 1) + "/" + root.count

        color: root.confirming ? Theme.danger : Theme.muted
        font.pixelSize: Math.max(9, Theme.fontSize - 1)
        font.family: Theme.fontFamily !== "" ? Theme.fontFamily : font.family

        Behavior on color {
            ColorAnimation {
                duration: 140
                easing.type: Easing.OutCubic
            }
        }
    }
}
