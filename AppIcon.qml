import QtQuick
import Quickshell
import Quickshell.Widgets

// An application icon from the system icon theme, falling back to the
// theme's generic executable icon, and to a drawn letter tile when even that
// is missing -- a tile never renders empty.
Item {
    id: root

    // Icon name or absolute path; "" goes straight to the fallback.
    property string name: ""
    // Its first letter labels the drawn fallback.
    property string label: ""
    property real size: Theme.iconSize
    // False holds the theme lookup back; the slot shows the plain soft tile
    // until it turns true. Once requested, an icon stays loaded.
    property bool active: true

    property bool latched: false
    readonly property bool requested: root.active || root.latched
    onActiveChanged: if (root.active) root.latched = true
    // A reused delegate gets a new name: it waits for `active` again.
    onNameChanged: root.latched = root.active

    implicitWidth: root.size
    implicitHeight: root.size

    readonly property string source: {
        if (!root.requested) return "";
        if (root.name.startsWith("/")) return "file://" + root.name;
        if (root.name === "") return Quickshell.iconPath(Theme.fallbackIcon, true);
        return Quickshell.iconPath(root.name, Theme.fallbackIcon);
    }

    readonly property bool missing: root.requested && (root.source === "" || image.status === Image.Error)

    // Fade in only icons that actually had to load. One already in the pixmap
    // cache is ready on creation and must not flicker every time a keystroke
    // re-filters the grid.
    property bool fadeIn: false

    IconImage {
        id: image

        anchors.fill: parent
        source: root.source
        asynchronous: true
        visible: !root.missing
        opacity: image.status === Image.Ready ? 1 : 0

        Behavior on opacity {
            enabled: root.fadeIn
            NumberAnimation { duration: Theme.fadeDuration; easing.type: Easing.OutCubic }
        }
    }

    Component.onCompleted: root.fadeIn = image.status !== Image.Ready

    // A soft tile holds the slot while a lookup is in flight -- a cold icon
    // theme takes a few hundred milliseconds, and a missing name longer --
    // and stays, lettered, when nothing resolves.
    Rectangle {
        anchors.fill: parent
        anchors.margins: root.size * 0.06
        opacity: root.missing || !root.requested || image.status === Image.Loading ? 1 : 0
        visible: opacity > 0.01
        radius: width * 0.23
        color: Theme.fallbackIconFill
        border.width: 1
        border.color: Theme.panelBorder

        Behavior on opacity {
            enabled: root.fadeIn
            NumberAnimation { duration: Theme.fadeDuration; easing.type: Easing.OutCubic }
        }

        Text {
            visible: root.missing
            anchors.centerIn: parent
            text: (root.label.trim().charAt(0) || "?").toUpperCase()
            textFormat: Text.PlainText
            color: Theme.textSecondary
            font.family: Theme.uiFont
            font.pixelSize: Math.round(parent.height * 0.44)
            font.weight: Font.Medium
        }
    }
}
