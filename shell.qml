import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "providers"
import "rofi-search.js" as RofiSearch

ShellRoot {
    id: shell

    // ------------------------------------------------------------- providers

    // The only place in the codebase that names the concrete sources. Adding a
    // provider is a new file under providers/ plus one line here; ResultList,
    // ResultItem, SelectionOutline and the ranking below never learn about it.
    readonly property list<Provider> providers: [
        DrunProvider {
            available: !Config.dmenuMode
        },
        ActionsProvider {
            available: !Config.dmenuMode
        },
        CommandProvider {
            available: !Config.dmenuMode
        },
        DmenuProvider {}
    ]

    readonly property string rawText: frame.text

    // The provider whose prefix the query opens with, if any.
    readonly property var activeProvider: {
        if (shell.rawText.length === 0) return null;
        for (let i = 0; i < shell.providers.length; i++) {
            const provider = shell.providers[i];
            if (!provider.available || provider.prefix === "") continue;
            if (shell.rawText.startsWith(provider.prefix)) return provider;
        }
        return null;
    }

    readonly property string activePrefix: shell.activeProvider ? shell.activeProvider.prefix : ""
    readonly property string queryText: shell.rawText.substring(shell.activePrefix.length)

    // A provider may claim its own accent while its prefix is active; Theme
    // animates the transition.
    Binding {
        target: Theme
        property: "accentOverride"
        value: shell.activeProvider ? shell.activeProvider.accent : "transparent"
    }

    // --------------------------------------------------------------- ranking

    readonly property var ranked: shell.rank()

    // One matcher over the union of every active provider's candidates, so
    // applications and actions land in a single ranked list rather than two.
    // The matching, the field ranking and the history tie-break are all
    // rofi-search.js -- this function only decides what goes in.
    function rank(): var {
        const active = shell.activeProvider;
        const text = shell.queryText;

        let records = [];
        for (let i = 0; i < shell.providers.length; i++) {
            const provider = shell.providers[i];
            if (!provider.available) continue;

            // With a prefix active, only that provider runs; otherwise only
            // the unprefixed ones do.
            if (active !== null ? provider !== active : provider.prefix !== "") continue;

            records = records.concat(provider.candidates(text));
        }

        if (text.trim().length === 0) {
            // rofi's search() matches nothing on an empty pattern, so the
            // resting order has to be chosen here.
            //
            // For applications and actions that order is frecency and nothing
            // else. rofi falls back to alphabetical once history runs out, but
            // alphabetical is not a meaningful resting state -- it just parks
            // the selection on whatever sorts first. So the untouched tail is
            // dropped: with an empty history the list is empty, and the frame
            // stands alone until the user types.
            //
            // Piped menus and command history keep the order they came in;
            // their order is the caller's, not a ranking.
            const mode = active !== null ? active.orderWhenEmpty : "history";
            if (mode !== "history") return records.map(record => record.entry);

            const known = records.filter(record =>
                RofiSearch.historySortIndex(record, shell.drunHistory) !== null);
            return RofiSearch.sortApplicationsLikeRofi(known, shell.drunHistory)
                .map(record => record.entry);
        }

        return RofiSearch.search(text, records, {
            "matchingMethod": Config.matchingMethod,
            "normalizeMatch": Config.normalizeMatch,
            "sort": Config.sortMatches,
            "sortingMethod": Config.sortingMethod,
            "matchFieldsSpec": Config.matchFields,
            "drunHistory": shell.drunHistory,
            "useDrunHistory": true,
            "preferNameMatch": Config.preferNameMatch
        });
    }

    // currentIndex is authoritative. The lane's scroll position is derived
    // from it inside ResultList, never the reverse.
    property int currentIndex: 0
    property bool confirming: false

    onRawTextChanged: {
        // Changing the query always resets the selection; the outline travels
        // back to the top on the same spring.
        shell.currentIndex = 0;
        shell.confirming = false;
    }

    onRankedChanged: {
        if (shell.currentIndex >= shell.ranked.length) {
            shell.currentIndex = Math.max(0, shell.ranked.length - 1);
        }
    }

    function move(delta: int) {
        const count = shell.ranked.length;
        if (count === 0) return;
        shell.currentIndex = Math.max(0, Math.min(count - 1, shell.currentIndex + delta));
    }

    // -------------------------------------------------------- launch history

    // rofi's rofi3.druncache, byte-for-byte: "{score} {desktop_id}" lines,
    // capped at 25 entries, rebased so the least recent sits at 0. Keeping the
    // format means Config.drunCache can point at rofi's own cache file and the
    // two share history.
    property int drunHistoryGeneration: 0

    readonly property var drunHistory: {
        shell.drunHistoryGeneration;
        if (!drunCacheFile.loaded) return ({});
        return RofiSearch.parseDrunHistory(drunCacheFile.text());
    }

    FileView {
        id: drunCacheFile

        path: Config.drunCachePath
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        printErrors: false

        onLoaded: shell.drunHistoryGeneration += 1
        onLoadFailed: shell.drunHistoryGeneration += 1
    }

    function recordLaunch(item: var) {
        // Command history is the command provider's own file, and dmenu keys
        // are line positions that mean nothing across runs.
        if (!item.source.usesDrunHistory) return;
        if (!item.id) return;

        const current = drunCacheFile.loaded ? drunCacheFile.text() : "";
        drunCacheFile.setText(RofiSearch.recordDrunLaunch(current, item.id));
        shell.drunHistoryGeneration += 1;
    }

    // ------------------------------------------------------------- activate

    function activate() {
        const item = shell.ranked[shell.currentIndex];
        if (!item) {
            shell.close(shell.closeFade);
            return;
        }

        if (item.confirm && !shell.confirming) {
            // First Enter arms the action; the frame does not collapse.
            shell.confirming = true;
            return;
        }

        shell.recordLaunch(item);
        item.source.activate(item.payload);
        shell.close(shell.closeCollapse);
    }

    readonly property var modifierKeys: [
        Qt.Key_Control, Qt.Key_Shift, Qt.Key_Alt, Qt.Key_Meta,
        Qt.Key_AltGr, Qt.Key_CapsLock, Qt.Key_NumLock, Qt.Key_ScrollLock
    ]

    function onKeyActivity(key: int) {
        if (!shell.confirming) return;
        if (key === Qt.Key_Return || key === Qt.Key_Enter) return;
        if (shell.modifierKeys.indexOf(key) >= 0) return;
        // Any other key cancels and restores the normal state.
        shell.confirming = false;
    }

    // -------------------------------------------------------- close handling

    readonly property int closeNone: 0
    readonly property int closeCollapse: 1
    readonly property int closeFade: 2

    property int closing: shell.closeNone

    function close(mode: int) {
        if (shell.closing !== shell.closeNone) return;
        shell.closing = mode;
        exitTimer.interval = mode === shell.closeCollapse ? 160 : 120;
        exitTimer.start();
    }

    Timer {
        id: exitTimer
        repeat: false
        onTriggered: Qt.quit()
    }

    // -------------------------------------------------- monitor resolution

    // The launcher belongs on the monitor the user is looking at. Hyprland's
    // IPC is not up yet at component completion -- it lands a frame or two
    // later -- so the window stays hidden until either the monitor is known or
    // a short deadline passes. Outside Hyprland the deadline is skipped and
    // Quickshell's default screen is used unchanged.
    property bool screenResolved: false

    readonly property bool hyprlandAvailable: (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || "") !== ""

    function resolveScreen() {
        if (shell.screenResolved) return;

        const monitor = Hyprland.focusedMonitor;
        if (monitor !== null) {
            const screens = Quickshell.screens;
            for (let i = 0; i < screens.length; i++) {
                const candidate = screens[i];
                const mapped = Hyprland.monitorFor(candidate);
                if (mapped === monitor || (mapped !== null && mapped.name === monitor.name)) {
                    window.screen = candidate;
                    break;
                }
            }
        }

        // Nothing matched, or no IPC at all: window.screen is left untouched,
        // which is Quickshell's default screen.
        shell.screenResolved = true;
    }

    Connections {
        target: Hyprland
        enabled: !shell.screenResolved

        function onFocusedMonitorChanged() {
            shell.resolveScreen();
        }
    }

    Timer {
        id: screenDeadline
        // Only a safety net: the Connections above normally fire first.
        interval: 150
        running: shell.hyprlandAvailable && !shell.screenResolved
        onTriggered: shell.resolveScreen()
    }

    Component.onCompleted: {
        if (!shell.hyprlandAvailable) shell.resolveScreen();
        else if (Hyprland.focusedMonitor !== null) shell.resolveScreen();
    }

    // ----------------------------------------------------------------- window

    PanelWindow {
        id: window

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "line-launcher"

        // Anchoring all four sides gives a full-screen surface. The visible
        // content is a few hundred pixels wide in the middle of it, so the
        // whiskers have the whole half-screen to slide into on close, and
        // nothing needs clipping.
        exclusionMode: ExclusionMode.Ignore
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        color: "transparent"
        visible: shell.screenResolved

        onVisibleChanged: if (window.visible) frame.focusInput()

        Component.onCompleted: Config.devicePixelRatio = Screen.devicePixelRatio

        Connections {
            target: Screen
            function onDevicePixelRatioChanged() {
                Config.devicePixelRatio = Screen.devicePixelRatio;
            }
        }

        Item {
            id: content

            anchors.centerIn: parent
            width: parent.width
            height: frame.implicitHeight + Config.frameToListGap + list.implicitHeight

            clip: false
            opacity: shell.closing === shell.closeNone ? 1 : 0

            Behavior on opacity {
                NumberAnimation {
                    // Esc fades a little faster than the Enter collapse so the
                    // two do not read as the same gesture.
                    duration: shell.closing === shell.closeCollapse ? 160 : 110
                    easing.type: Easing.InQuad
                }
            }

            SearchFrame {
                id: frame

                width: parent.width
                height: implicitHeight
                anchors.top: parent.top

                prefix: shell.activePrefix
                completion: shell.ranked.length > 0 ? shell.ranked[0].name : ""
                collapsing: shell.closing === shell.closeCollapse

                onAccepted: shell.activate()
                onCancelled: shell.close(shell.closeFade)
                onCompletionRequested: frame.acceptCompletion()
                onMoveUp: shell.move(-1)
                onMoveDown: shell.move(1)
                onKeyActivity: key => shell.onKeyActivity(key)
            }

            ResultList {
                id: list

                width: parent.width
                height: implicitHeight
                anchors.top: frame.bottom
                anchors.topMargin: Config.frameToListGap

                results: shell.ranked
                currentIndex: shell.currentIndex
                confirming: shell.confirming
                collapsing: shell.closing === shell.closeCollapse
                accent: Theme.activeAccent
            }
        }
    }
}
