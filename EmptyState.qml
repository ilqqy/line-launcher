import QtQuick

// What the results area says when it has nothing to show.
Item {
    id: root

    property string title: ""
    property string subtitle: ""
    property bool shown: false

    opacity: root.shown ? 1 : 0
    visible: root.opacity > 0.01

    Behavior on opacity {
        NumberAnimation { duration: Theme.fadeDuration; easing.type: Easing.OutCubic }
    }

    Column {
        anchors.centerIn: parent
        width: parent.width - 2 * Theme.panelPadding
        spacing: 6

        MagnifierGlyph {
            anchors.horizontalCenter: parent.horizontalCenter
            size: Theme.emptyGlyphSize
            stroke: 2.5
            color: Theme.textTertiary
        }

        Item {
            width: 1
            height: 4
        }

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.title
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Theme.textSecondary
            font.family: Theme.uiFont
            font.pixelSize: Theme.emptyTitleSize
            font.weight: Font.Medium
        }

        Text {
            width: parent.width
            visible: root.subtitle !== ""
            horizontalAlignment: Text.AlignHCenter
            text: root.subtitle
            textFormat: Text.PlainText
            elide: Text.ElideMiddle
            color: Theme.textTertiary
            font.family: Theme.uiFont
            font.pixelSize: Theme.emptyBodySize
        }
    }
}
