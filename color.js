.pragma library

// Perceptual colour distance.
//
// Used to choose an accent that is actually distinguishable from the
// foreground. A palette can be nearly monochrome -- every entry a slightly
// different warm grey -- and naive RGB distance happily calls two greys far
// apart because it weights a green channel step the same as a blue one. Lab
// plus CIEDE2000 is what perceptual comparison actually needs, and it is
// twenty lines of arithmetic, so there is no reason to approximate it.
//
// Reference: Sharma, Wu & Dalal, "The CIEDE2000 Color-Difference Formula"
// (2005), which is also the formula CIE 142-2001 specifies.

function parseHex(value) {
    if (typeof value !== "string") return null;

    var text = value.trim();
    if (text.charAt(0) !== "#") return null;
    text = text.slice(1);

    if (!/^[0-9a-fA-F]+$/.test(text)) return null;

    if (text.length === 3) {
        return [
            parseInt(text.charAt(0) + text.charAt(0), 16),
            parseInt(text.charAt(1) + text.charAt(1), 16),
            parseInt(text.charAt(2) + text.charAt(2), 16)
        ];
    }

    // Qt writes eight-digit colours as #AARRGGBB, so the leading pair is
    // alpha and is dropped -- opacity is not part of a hue comparison.
    if (text.length === 8) text = text.slice(2);

    if (text.length !== 6) return null;

    return [
        parseInt(text.slice(0, 2), 16),
        parseInt(text.slice(2, 4), 16),
        parseInt(text.slice(4, 6), 16)
    ];
}

function linearize(channel) {
    var c = channel / 255;
    return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
}

function pivot(t) {
    return t > 0.008856451679035631 ? Math.cbrt(t) : (7.787037037037035 * t + 16 / 116);
}

// sRGB (D65) -> CIE XYZ -> CIE L*a*b*
function toLab(rgb) {
    var r = linearize(rgb[0]);
    var g = linearize(rgb[1]);
    var b = linearize(rgb[2]);

    var x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) * 100;
    var y = (0.2126729 * r + 0.7151522 * g + 0.0721750 * b) * 100;
    var z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) * 100;

    // D65 reference white.
    var fx = pivot(x / 95.047);
    var fy = pivot(y / 100.0);
    var fz = pivot(z / 108.883);

    return [116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)];
}

function rad(degrees) {
    return degrees * Math.PI / 180;
}

function hueDegrees(b, a) {
    if (a === 0 && b === 0) return 0;
    var angle = Math.atan2(b, a) * 180 / Math.PI;
    return angle >= 0 ? angle : angle + 360;
}

function deltaE2000Lab(lab1, lab2) {
    var L1 = lab1[0], a1 = lab1[1], b1 = lab1[2];
    var L2 = lab2[0], a2 = lab2[1], b2 = lab2[2];

    var C1 = Math.sqrt(a1 * a1 + b1 * b1);
    var C2 = Math.sqrt(a2 * a2 + b2 * b2);
    var Cbar = (C1 + C2) / 2;
    var Cbar7 = Math.pow(Cbar, 7);
    var pow25_7 = 6103515625; // 25^7

    var G = 0.5 * (1 - Math.sqrt(Cbar7 / (Cbar7 + pow25_7)));

    var a1p = (1 + G) * a1;
    var a2p = (1 + G) * a2;
    var C1p = Math.sqrt(a1p * a1p + b1 * b1);
    var C2p = Math.sqrt(a2p * a2p + b2 * b2);
    var h1p = hueDegrees(b1, a1p);
    var h2p = hueDegrees(b2, a2p);

    var dLp = L2 - L1;
    var dCp = C2p - C1p;

    var dhp = 0;
    if (C1p * C2p !== 0) {
        dhp = h2p - h1p;
        if (dhp > 180) dhp -= 360;
        else if (dhp < -180) dhp += 360;
    }
    var dHp = 2 * Math.sqrt(C1p * C2p) * Math.sin(rad(dhp / 2));

    var Lbarp = (L1 + L2) / 2;
    var Cbarp = (C1p + C2p) / 2;

    var hbarp;
    if (C1p * C2p === 0) {
        hbarp = h1p + h2p;
    } else if (Math.abs(h1p - h2p) <= 180) {
        hbarp = (h1p + h2p) / 2;
    } else if (h1p + h2p < 360) {
        hbarp = (h1p + h2p + 360) / 2;
    } else {
        hbarp = (h1p + h2p - 360) / 2;
    }

    var T = 1
        - 0.17 * Math.cos(rad(hbarp - 30))
        + 0.24 * Math.cos(rad(2 * hbarp))
        + 0.32 * Math.cos(rad(3 * hbarp + 6))
        - 0.20 * Math.cos(rad(4 * hbarp - 63));

    var dTheta = 30 * Math.exp(-Math.pow((hbarp - 275) / 25, 2));
    var Cbarp7 = Math.pow(Cbarp, 7);
    var RC = 2 * Math.sqrt(Cbarp7 / (Cbarp7 + pow25_7));

    var SL = 1 + (0.015 * Math.pow(Lbarp - 50, 2)) / Math.sqrt(20 + Math.pow(Lbarp - 50, 2));
    var SC = 1 + 0.045 * Cbarp;
    var SH = 1 + 0.015 * Cbarp * T;
    var RT = -Math.sin(rad(2 * dTheta)) * RC;

    var termL = dLp / SL;
    var termC = dCp / SC;
    var termH = dHp / SH;

    return Math.sqrt(termL * termL + termC * termC + termH * termH + RT * termC * termH);
}

// Returns -1 when either colour cannot be parsed, so callers can skip rather
// than rank a nonsense value first.
function deltaE2000(first, second) {
    var a = parseHex(first);
    var b = parseHex(second);
    if (a === null || b === null) return -1;
    return deltaE2000Lab(toLab(a), toLab(b));
}
