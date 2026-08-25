import QtQuick
import QtQuick.Effects

// The legibility glow: a soft halo in the shape of whatever it is pointed at,
// drawn behind it in the palette's background colour.
//
// Not a panel and not a scrim. The halo is the *shape of the content*, so a
// glyph or a 2px stroke sits in its own small pool of the background colour
// and survives a pale wallpaper, while everything between the glyphs stays
// transparent.
//
// The content is never hidden or replaced. This draws a blurred copy of it
// underneath; the real item still renders itself, natively, on top. That
// matters for more than sharpness. MultiEffect's documented use is to stand in
// for its source, which means hiding the source -- and an invisible TextInput
// takes neither keyboard focus nor mouse clicks, so the search field could not
// be routed through one.
//
// `brightness: 1.0` ahead of `colorization: 1.0` is what makes the halo a
// single flat colour rather than a blurred smear of the content's own. That is
// not cosmetic: without it a full-colour Papirus icon would glow in its own
// colours, which is the blue-Steam-smear problem again, one layer down.
// Measured: white, dark grey and red sources all produce an identical halo.
//
// With the glow switched off the Loader never constructs the MultiEffect, so
// there is no layer, no texture and no shader anywhere in the scene.
Loader {
    id: root

    // The item to trace, normally a sibling: `anchors.fill: root.target`.
    property Item target: null

    property real blurRadius: Config.glowRadius
    property real strength: Config.glowOpacity
    property color colour: Theme.background

    active: Config.glowEnabled
        && root.target !== null
        && root.blurRadius >= 1
        && root.strength > 0

    // Always behind the thing it traces.
    z: -1

    sourceComponent: MultiEffect {
        source: root.target

        blurEnabled: true
        blur: 1.0
        // blurMax is both the pixel reach of blur == 1.0 and the price: it
        // decides how many downsampled levels get blurred. Keeping it at the
        // radius actually wanted, rather than the default 32, is the whole
        // cost control here.
        blurMax: Math.max(1, Math.round(root.blurRadius))

        brightness: 1.0
        colorization: 1.0
        colorizationColor: root.colour
        opacity: root.strength

        // The halo has to be allowed to spill outside the bounds of the item
        // it traces, or it would be cut off square at the edge.
        autoPaddingEnabled: true
    }
}
