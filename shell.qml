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

            // With a prefix active, only that provider runs. Otherwise use
            // ordinary unprefixed providers plus sources such as shell
            // commands that explicitly join the combined search.
            if (active !== null
                    ? provider !== active
                    : (provider.prefix !== "" && !provider.participatesWithoutPrefix)) continue;

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
            const mode = RofiSearch.emptyOrderMode(active, Config.dmenuMode);
            if (mode !== "history") return records.map(record => record.entry);

            const known = records.filter(record =>
                RofiSearch.historySortIndex(record, shell.drunHistory) !== null);
            return RofiSearch.sortApplicationsLikeRofi(known, shell.drunHistory)
                .map(record => record.entry);
        }

        const options = {
            "matchingMethod": Config.matchingMethod,
            "normalizeMatch": Config.normalizeMatch,
            "sort": Config.sortMatches,
            "sortingMethod": Config.sortingMethod,
            "matchFieldsSpec": Config.matchFields,
            "drunHistory": shell.drunHistory,
            "useDrunHistory": true,
            "preferNameMatch": Config.preferNameMatch
        };
        return active === null && !Config.dmenuMode
            ? RofiSearch.searchWithKeyboardFallback(text, records, options)
            : RofiSearch.search(text, records, options);
    }

    // currentIndex is authoritative. The lane's scroll position is derived
    // from it inside ResultList, never the reverse.
    property int currentIndex: 0
    readonly property bool confirming: activation.confirming

    onRawTextChanged: {
        // Changing the query always resets the selection; the outline travels
        // back to the top on the same spring.
        shell.currentIndex = 0;
        activation.armedItem = null;
    }

    onRankedChanged: {
        if (shell.currentIndex >= shell.ranked.length) {
            shell.currentIndex = Math.max(0, shell.ranked.length - 1);
        }
    }

    function move(delta: int) {
        if (shell.closing !== shell.closeNone) return;
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
        // A resident launcher outlives any one read: rofi, or another
        // line-launcher process, may record launches in the meantime.
        watchChanges: Config.resident

        // `text()` still returns the previous contents when fileChanged
        // fires; reload() re-reads and emits loaded with the new bytes.
        onFileChanged: drunCacheFile.reload()
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

    ActivationController {
        id: activation
        selectedItem: shell.ranked[shell.currentIndex] || null
        onCancel: shell.close(shell.closeFade)
        onLaunch: item => {
            shell.recordLaunch(item);
            item.source.activate(item.payload);
            shell.close(shell.closeCollapse);
        }
    }

    // -------------------------------------------------------- open handling

    // False until the window is on screen, and again once a resident launcher
    // has hidden it. Everything the entrance animates rests at its off state
    // while this is false, so the animation starts from the first visible
    // frame rather than running while the surface is still hidden waiting on
    // the monitor.
    property bool entered: false

    // -------------------------------------------------------- close handling

    readonly property int closeNone: 0
    readonly property int closeCollapse: 1
    readonly property int closeFade: 2

    property int closing: shell.closeNone

    function close(mode: int) {
        if (shell.closing !== shell.closeNone) return;
        activation.closing = true;
        activation.armedItem = null;
        shell.closing = mode;
        exitTimer.interval = mode === shell.closeCollapse ? 160 : 120;
        exitTimer.start();
    }

    Timer {
        id: exitTimer
        repeat: false
        onTriggered: shell.finishClose()
    }

    function finishClose() {
        if (!Config.resident) {
            Qt.quit();
            return;
        }
        shell.shown = false;
        shell.entered = false;
        shell.resetSession();
    }

    // ------------------------------------------------------- resident mode

    // A one-shot launcher is shown from the start and quits when it closes.
    // The resident instance (launcher.sh --daemon) starts hidden, hides when
    // it closes, and is shown again over IPC by launcher.sh --toggle.
    property bool shown: !Config.resident

    IpcHandler {
        id: ipc

        target: "launcher"
        // Piped menus run as separate one-off processes and never answer.
        enabled: Config.resident

        function toggle(): void {
            shell.toggle();
        }
        function show(): void {
            shell.show();
        }
        function hide(): void {
            shell.hide();
        }
    }

    function toggle() {
        if (shell.shown && shell.closing === shell.closeNone) shell.close(shell.closeFade);
        else shell.show();
    }

    function hide() {
        if (shell.shown) shell.close(shell.closeFade);
    }

    function show() {
        if (shell.shown) {
            // Reopened during the exit animation: cancel it, and the entrance
            // runs back from wherever the exit had reached. The window stays
            // mapped, so the monitor is not re-resolved.
            if (shell.closing === shell.closeNone) return;
            exitTimer.stop();
            shell.resetSession();
            return;
        }

        shell.resetSession();
        // The user may have moved to another monitor since the last show.
        // Hyprland's IPC is long connected by now, so this normally resolves
        // on the spot; screenDeadline covers the rest.
        shell.screenResolved = false;
        if (!shell.hyprlandAvailable || Hyprland.focusedMonitor !== null) shell.resolveScreen();
        shell.shown = true;
    }

    // Every show starts like a fresh launch: empty query, "All", top of the
    // lists, first result selected, nothing armed for confirmation.
    function resetSession() {
        frame.reset();
        shell.currentIndex = 0;
        activation.armedItem = null;
        activation.closing = false;
        shell.closing = shell.closeNone;
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
        WlrLayershell.namespace: Config.namespace

        // Anchoring all four sides gives a full-screen surface: the panel
        // sits in the middle of it, the open/close scale never clips, and a
        // click anywhere outside the panel lands here and dismisses it.
        exclusionMode: ExclusionMode.Ignore
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        color: "transparent"
        visible: shell.screenResolved && shell.shown

        onVisibleChanged: {
            if (!window.visible) return;
            frame.focusInput();
            shell.entered = true;
        }

        Component.onCompleted: {
            Config.devicePixelRatio = Screen.devicePixelRatio;
            // onVisibleChanged does not fire for a window that was already
            // visible when it was built -- which is the case whenever the
            // screen resolved before this component completed.
            if (window.visible) shell.entered = true;
        }

        Connections {
            target: Screen
            function onDevicePixelRatioChanged() {
                Config.devicePixelRatio = Screen.devicePixelRatio;
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: shell.close(shell.closeFade)
        }

        // Open is a fade and a small scale-up; close is the same run
        // backwards, quick enough to finish before the shell's exit timer.
        Item {
            id: stage

            // The first frames that draw the panel are the expensive ones:
            // effect shaders compile and layers render for the first time. At
            // opacity 0 the scene graph skips the panel entirely, so that cost
            // would land mid-fade and the eased curve would skip ahead. The
            // panel is drawn at an invisible 1% for a few frames first, and
            // the fade starts once they are behind it. 1% of the fill is far
            // below the blur's ignore_alpha, so nothing shows meanwhile.
            property bool primed: false
            property int primeFrames: 0

            // A resident launcher enters again on every show, onto a newly
            // mapped surface; it primes again with it.
            Connections {
                target: shell
                function onEnteredChanged() {
                    if (shell.entered) return;
                    stage.primed = false;
                    stage.primeFrames = 0;
                }
            }

            FrameAnimation {
                running: shell.entered && !stage.primed
                onTriggered: {
                    stage.primeFrames += 1;
                    if (stage.primeFrames >= 3) stage.primed = true;
                }
            }

            width: frame.implicitWidth
            height: frame.implicitHeight
            x: Math.round((parent.width - width) / 2)
            y: Math.round((parent.height - height) * Theme.panelVerticalBias)

            // Closed is the base state; priming is an instant 1% within it.
            opacity: shell.entered && !stage.primed ? 0.01 : 0
            scale: Theme.closedScale

            // A state with a transition each way, rather than Behaviors, so
            // each direction always gets its own curve: a Behavior reads its
            // easing before a binding on `open` has updated it. Interrupting
            // either direction runs the other from wherever it had reached.
            states: State {
                name: "open"
                when: shell.closing === shell.closeNone && shell.entered && stage.primed
                PropertyChanges {
                    stage.opacity: 1
                    stage.scale: 1
                }
            }

            transitions: [
                Transition {
                    to: "open"
                    NumberAnimation {
                        properties: "opacity,scale"
                        duration: Theme.openDuration
                        easing.type: Easing.OutCubic
                    }
                },
                Transition {
                    from: "open"
                    NumberAnimation {
                        properties: "opacity,scale"
                        duration: Theme.closeDuration
                        easing.type: Easing.InCubic
                    }
                }
            ]

            LauncherPanel {
                id: frame

                anchors.fill: parent

                results: shell.ranked
                currentIndex: shell.currentIndex
                confirming: shell.confirming
                closing: shell.closing !== shell.closeNone

                applications: {
                    for (let i = 0; i < shell.providers.length; i++) {
                        const provider = shell.providers[i];
                        if (provider.providerId === "drun")
                            return provider.available ? provider.prepared : [];
                    }
                    return [];
                }

                gridMode: !Config.dmenuMode && shell.activeProvider === null
                showRowIcons: !Config.dmenuMode
                listTitle: Config.dmenuMode ? (Config.prompt || qsTr("Items")) : qsTr("Commands")
                placeholder: Config.prompt !== "" ? Config.prompt : qsTr("Search")

                onSelectRequested: index => {
                    if (shell.closing === shell.closeNone) shell.currentIndex = index;
                }
                onAccepted: activation.activate()
                onCancelled: shell.close(shell.closeFade)
                onKeyActivity: (key, modifiers) => activation.keyActivity(key, modifiers)
            }
        }
    }
}
