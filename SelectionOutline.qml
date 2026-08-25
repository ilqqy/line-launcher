import QtQuick

// The selection outline: a 2px rounded rectangle that travels between rows on
// the same animation the lane slides on, stretching vertically in proportion
// to its own velocity.
//
// Nothing here drives layout. The rows read `centreY` to place themselves, but
// this item is positioned absolutely and its height change is purely visual.
Item {
    id: root

    // Where the selection wants to be, as a slot in the visible window. Set by
    // ResultList; the animation below does the travelling. A window slot, not a
    // pixel and not a lane position: while the lane scrolls the selection is
    // pinned to the edge, so this does not change and the outline holds still
    // while the rows slide underneath it.
    property real targetPosition: 0

    property color strokeColour: Theme.activeAccent
    property bool collapsing: false

    // Sampled velocity in pixels per second, zero whenever the outline is idle.
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

    // The travel animation drives this. ResultList projects it into `centreY` and
    // `heightScale`, so the outline sits exactly where the row it is landing
    // on has been projected to.
    property real position: root.targetPosition

    // Set by ResultList from `position`.
    property real centreY: 0
    property real heightScale: 1

    // How long the outline takes to cross one row. Set by ResultList to the
    // same duration the lane slides on.
    property int travelDuration: 150

    // This used to be a spring, and the spring is what put the outline off its
    // row. Two reasons, both structural rather than a matter of tuning:
    //
    //   1. It overshoots by design -- ~10% of the travel past the row before
    //      it comes back -- so the outline is never on the row it marks until
    //      it settles.
    //   2. It was chasing a target measured against the animated `laneY`, so
    //      it inherited the lane's easing error on top of its own lag. Under a
    //      held key that compounded: measured at 1.9 rows down and 4.1 rows
    //      up, with the selection pushed clean out of the window. The target
    //      is a plain window slot now, which is the real fix; this animation
    //      only ever has one row to cross.
    //
    // Stiffening it does not help -- Qt integrates a SpringAnimation per frame
    // and it diverges above about 90, which sent the position to 1e11 px.
    //
    // So the outline now travels on exactly the animation the lane travels on:
    // same duration, same curve, one clock. It cannot disagree with the rows
    // about where a row is, because it is no longer computing that separately,
    // and it always lands on the row rather than past it.
    Behavior on position {
        NumberAnimation {
            id: travel

            duration: root.travelDuration
            easing.type: Easing.OutCubic
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

    // ------------------------------------------------------------ accent aura

    // Trace the complete ring once. The former four-edge implementation put
    // two independent shadows over every corner, so their alpha accumulated
    // there and made four conspicuous bright spots. One silhouette gives the
    // straight runs and rounded corners the same falloff.
    Glow {
        id: aura

        anchors.fill: outline
        target: outline
        blurRadius: Config.auraRadius
        strength: Config.auraOpacity
        colour: outline.border.color
    }

    Rectangle {
        id: outline

        anchors.fill: parent
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
    }

    // Exposed for tests: whether the aura is actually in the scene.
    readonly property bool auraActive: Config.glowEnabled
        && Config.auraRadius >= 1
        && Config.auraOpacity > 0
    readonly property alias auraEffect: aura

    // ------------------------------------------------------ velocity sampling

    // The only per-frame work in the shell, and it runs strictly while the
    // outline is travelling. `travel.running` goes false the moment it arrives,
    // which stops this and ends all repainting.
    // tests/spring.qml asserts that with a frame counter.
    FrameAnimation {
        id: velocitySampler

        property real lastCentre: 0

        running: travel.running
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
    readonly property alias settling: travel.running
}
