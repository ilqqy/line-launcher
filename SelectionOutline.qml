import QtQuick

// The selection outline: a 2px rounded rectangle that travels between rows on
// a spring and stretches vertically in proportion to its own velocity.
//
// Nothing here drives layout. The rows read `centreY` to place themselves, but
// this item is positioned absolutely and its height change is purely visual.
Rectangle {
    id: root

    // Where the selection wants to be, in lane slots. Set by ResultList; the
    // spring below does the travelling. Slots rather than pixels so the
    // outline stays glued to its row while the lane is sliding underneath it.
    property real targetPosition: 0

    property color strokeColour: Theme.activeAccent
    property bool collapsing: false

    // Sampled velocity in pixels per second, zero whenever the spring is idle.
    property real velocity: 0

    // Number of frames sampled since startup. This is the shell's entire
    // per-frame budget, so tests/spring.qml can assert it stops rising once
    // the outline settles rather than anyone judging it by eye.
    property int sampleCount: 0

    readonly property real baseHeight: Config.rowHeight
    readonly property real maxStretch: 9
    readonly property real stretchPerVelocity: 0.016

    readonly property real stretch: Math.min(root.maxStretch,
        Math.abs(root.velocity) * root.stretchPerVelocity)

    // The spring drives this. ResultList projects it into `centreY` and
    // `heightScale`, so the outline sits exactly where the row it is landing
    // on has been projected to.
    property real position: root.targetPosition

    // Set by ResultList from `position`.
    property real centreY: 0
    property real heightScale: 1

    Behavior on position {
        SpringAnimation {
            id: spring

            // Tuned by measurement, not by eye: at damping 0.75 the
            // overshoot is a fixed fraction of the distance travelled, and
            // stiffness 38 puts a one-row step ~3.6px past its projected
            // resting place, settling in ~250ms. tests/spring.qml asserts it.
            spring: 38
            damping: 0.75
            mass: 1.0
            // `position` is in row slots, not pixels: a fifth of a pixel.
            epsilon: 0.004
        }
    }

    // On the Enter close the outline compresses into a horizontal line rather
    // than travelling anywhere.
    height: root.collapsing
        ? Config.strokeWidth
        : Config.snap(root.baseHeight * root.heightScale + root.stretch)

    Behavior on height {
        enabled: root.collapsing
        NumberAnimation {
            duration: 160
            easing.type: Easing.InCubic
        }
    }

    y: Config.snap(root.centreY - height / 2)

    color: "transparent"
    border.width: Config.strokeWidth
    border.color: root.strokeColour
    radius: Config.cornerRadius

    Behavior on border.color {
        ColorAnimation {
            duration: 140
            easing.type: Easing.OutCubic
        }
    }

    // ------------------------------------------------------------ accent aura

    // Four soft bands laid along the outline's own edges, in the outline's own
    // colour. Children of the outline, so they are the same element as far as
    // travel is concerned: same slot, same spring, no separate animation that
    // could lag or trail. The colour is read off `border.color` rather than
    // `strokeColour` so the aura crossfades into the confirm red on exactly
    // the curve the stroke does.
    //
    // The accent lives here and nowhere else in the shell.
    component AuraEdge: EdgeGlow {
        colour: root.border.color
    }

    AuraEdge {
        x: 0
        y: 0
        width: root.width
        height: Config.strokeWidth
    }

    AuraEdge {
        x: 0
        y: root.height - Config.strokeWidth
        width: root.width
        height: Config.strokeWidth
    }

    AuraEdge {
        x: 0
        y: 0
        width: Config.strokeWidth
        height: root.height
    }

    AuraEdge {
        x: root.width - Config.strokeWidth
        y: 0
        width: Config.strokeWidth
        height: root.height
    }

    // Exposed for tests: whether the aura is actually in the scene.
    readonly property bool auraActive: Config.glowEnabled
        && Config.auraRadius >= 1
        && Config.auraOpacity > 0

    // ------------------------------------------------------ velocity sampling

    // The only per-frame work in the shell, and it runs strictly while the
    // spring is running. `spring.running` goes false the moment the animation
    // settles within epsilon, which stops this and ends all repainting.
    // tests/spring.qml asserts that with a frame counter.
    FrameAnimation {
        id: velocitySampler

        property real lastCentre: 0

        running: spring.running
        onTriggered: {
            const dt = Math.max(velocitySampler.frameTime, 1 / 480);
            root.velocity = (root.centreY - velocitySampler.lastCentre) / dt;
            velocitySampler.lastCentre = root.centreY;
            root.sampleCount += 1;
        }

        onRunningChanged: {
            velocitySampler.lastCentre = root.centreY;
            if (!velocitySampler.running) root.velocity = 0;
        }
    }

    // Exposed so tests and the list can tell whether anything is still moving.
    readonly property alias settling: spring.running
}
