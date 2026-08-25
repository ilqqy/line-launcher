import QtQuick
import QtQuick.Effects

// One edge of the accent aura: a soft band of colour that falls off over
// `blurRadius` pixels either side of this item's rectangle.
//
// A RectangularShadow rather than a blurred copy of the outline, for two
// reasons.
//
// The first is cost. This is the one glow that moves: the selection outline
// travels on a spring and stretches in proportion to its own velocity, so its
// geometry changes on every frame of the journey. Anything texture-backed
// would have to re-render that texture, and blur it again, once per frame.
// RectangularShadow is analytic -- the falloff is computed per pixel from the
// rectangle's own geometry -- so there is no texture to invalidate. The aura
// travels and stretches with the outline for free.
//
// The second is that it keeps its core opaque, which a blur of a 2px stroke
// does not. Blurring a thin line spreads a fixed amount of ink over a wide
// band and what is left is faint; at the same nominal radius this reads as an
// aura rather than a smudge. Measured on the same 40x260 outline: the blurred
// copy was barely visible against a light background, this was not.
//
// The outline is a ring, not a filled rectangle, so four of these are laid
// along its edges. A single RectangularShadow filling the outline would be
// solid through the middle -- which is a scrim, and the whole point of the
// transparent background is that there isn't one.
Loader {
    id: root

    property real blurRadius: Config.auraRadius
    property real strength: Config.auraOpacity
    property color colour: "transparent"

    active: Config.glowEnabled && root.blurRadius >= 1 && root.strength > 0

    z: -1

    sourceComponent: RectangularShadow {
        blur: root.blurRadius
        spread: 0
        // Square: these are the straight runs of the outline, and the rounded
        // corners are far smaller than the falloff hides.
        radius: 0
        color: Qt.alpha(root.colour, root.strength)
    }
}
