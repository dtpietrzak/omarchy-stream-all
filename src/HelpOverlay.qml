import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material

// Every shortcut, over the window, drawn like Yeptes's. Keys are shown as
// they are on the keyboard; only what they do is translated.
Rectangle {
    id: overlay
    signal dismissed()
    color: Qt.alpha(theme.scrim, 0.88)

    readonly property var shortcuts: [
        { keys: "Space", text: qsTr("Start or stop the local server") },
        { keys: "Ctrl+N", text: qsTr("Add an output") },
        { keys: "Ctrl+/  F1  ?", text: qsTr("Show these shortcuts") },
        { keys: "Esc", text: qsTr("Leave a text box, or close this") },
        { keys: "Ctrl+Q  Q", text: qsTr("Quit") }
    ]

    // Swallows clicks and scrolling so nothing underneath reacts.
    MouseArea {
        anchors.fill: parent
        onClicked: overlay.dismissed()
        onWheel: (wheel) => wheel.accepted = true
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 480)
        height: content.implicitHeight + 48
        radius: theme.radius
        color: theme.base
        border.color: theme.line

        Column {
            id: content
            x: 24
            y: 24
            width: parent.width - 48
            spacing: 7

            Label {
                text: qsTr("Shortcuts")
                font.pixelSize: 18
                font.weight: Font.DemiBold
                color: theme.text
                bottomPadding: 8
            }
            Repeater {
                model: overlay.shortcuts
                delegate: Row {
                    required property var modelData
                    width: content.width
                    spacing: 16
                    Label {
                        width: 130
                        text: modelData.keys
                        font.family: "monospace"
                        font.pixelSize: 13
                        color: theme.accent
                    }
                    Label {
                        width: parent.width - 146
                        text: modelData.text
                        font.pixelSize: 13
                        color: theme.subtext
                        wrapMode: Text.Wrap
                    }
                }
            }
        }
    }
}
