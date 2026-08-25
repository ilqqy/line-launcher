// Icon resolution.
//
// Two things bite here. Quickshell's icon provider never reports failure -- an
// unknown name yields a blank 100x100 image with status Ready -- so the only
// way to know an icon is missing is to ask hasThemeIcon() before building the
// source. And the provider hands back the largest theme size that is <= the
// requested sourceSize, so asking for the logical size gets a smaller pixmap
// scaled up.
import QtQuick
import Quickshell
import "providers"

ShellRoot {
    id: suite

    property int failures: 0

    function check(label: string, actual: var, expected: var) {
        const ok = String(actual) === String(expected);
        if (!ok) suite.failures += 1;
        console.log((ok ? "ok   " : "FAIL ") + label
            + (ok ? "" : "  expected " + expected + ", got " + actual));
    }

    property ActionsProvider provider: ActionsProvider {}

    // Deliberately asks for the logical size, to show what the loader does
    // with it.
    Image {
        id: naive
        source: Quickshell.iconPath("firefox")
        sourceSize.width: Config.iconSize
        sourceSize.height: Config.iconSize
        visible: false
    }

    Image {
        id: corrected
        source: Quickshell.iconPath("firefox")
        sourceSize.width: Config.iconPixelSize
        sourceSize.height: Config.iconPixelSize
        visible: false
    }

    Timer {
        interval: 900
        running: true
        onTriggered: {
            // --- the fallback chain ---------------------------------------
            suite.check("an empty icon name yields the generic icon or nothing",
                suite.provider.resolveIcon("") === suite.provider.genericIcon(), true);

            suite.check("an unresolvable name never returns that name",
                suite.provider.resolveIcon("definitely-not-an-icon-xyz")
                    .indexOf("definitely-not-an-icon-xyz"), -1);

            suite.check("an unresolvable name falls back or gives up cleanly",
                suite.provider.resolveIcon("definitely-not-an-icon-xyz")
                    === suite.provider.genericIcon(), true);

            // Whatever the chain lands on must itself exist. This is the bug
            // that produced blank icons: application-x-executable is absent
            // from plenty of themes, including the one on this machine.
            const generic = suite.provider.genericIcon();
            if (generic !== "") {
                const name = generic.replace("image://icon/", "").split("?")[0];
                suite.check("the generic fallback actually exists in the theme",
                    Quickshell.hasThemeIcon(name), true);
            } else {
                console.log("ok   no generic icon in this theme; placeholder will be drawn");
            }

            suite.check("absolute paths bypass the icon theme",
                suite.provider.resolveIcon("/usr/share/pixmaps/thing.png"),
                "file:///usr/share/pixmaps/thing.png");

            // --- sizing ----------------------------------------------------
            suite.check("the requested size is a real theme size",
                Config.themeIconSizes.indexOf(Config.iconPixelSize) >= 0, true);

            suite.check("the requested size covers the rendered size",
                Config.iconPixelSize >= Config.iconSize * Config.devicePixelRatio, true);

            if (Quickshell.hasThemeIcon("firefox")) {
                suite.check("asking for the logical size under-delivers",
                    naive.implicitWidth < Config.iconSize, true);
                suite.check("asking for a theme size does not upscale",
                    corrected.implicitWidth >= Config.iconSize, true);
                console.log("     logical request " + Config.iconSize + "px -> "
                    + naive.implicitWidth + "px pixmap; corrected request "
                    + Config.iconPixelSize + "px -> " + corrected.implicitWidth + "px");
            } else {
                console.log("ok   no icon theme on this machine; sizing not exercised");
            }

            console.log(suite.failures === 0 ? "PASS" : "FAIL (" + suite.failures + ")");
            Qt.exit(suite.failures === 0 ? 0 : 1);
        }
    }
}
