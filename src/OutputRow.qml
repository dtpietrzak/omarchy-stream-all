import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// One destination: where to send, whether it is on, and how it is doing.
Rectangle {
    id: row

    required property int index
    required property string server
    required property string streamKey
    required property bool active
    required property string status
    required property string message
    required property string platform

    property bool confirmingRemove: false

    readonly property string statusText: {
        switch (status) {
        case "off": return qsTr("Off")
        case "empty": return qsTr("Enter a server and a stream key")
        case "waiting": return qsTr("Waiting for the stream from OBS")
        case "starting": return qsTr("Connecting…")
        case "live": return qsTr("Live")
        default: return message
        }
    }

    implicitHeight: content.implicitHeight + 24
    color: "#18181b"
    radius: theme.radius
    opacity: active ? 1 : 0.6

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: 12
        spacing: 4

        RowLayout {
            spacing: 12

            Switch {
                checked: row.active
                focusPolicy: Qt.NoFocus
                onToggled: backend.setActive(row.index, checked)
            }

            Label {
                text: row.platform !== "" ? row.platform : qsTr("Custom")
                color: "#9a9aa2"
                elide: Text.ElideRight
                Layout.preferredWidth: 72
            }

            TextField {
                text: row.server
                placeholderText: qsTr("Server, e.g. rtmp://live.twitch.tv/app")
                selectByMouse: true
                Layout.fillWidth: true
                Layout.preferredWidth: 300
                onEditingFinished: backend.setServer(row.index, text)
                // Leaving the field hands the keyboard back to the shortcuts.
                onAccepted: focus = false
                Keys.onEscapePressed: focus = false
            }

            TextField {
                text: row.streamKey
                placeholderText: qsTr("Stream key")
                echoMode: TextInput.PasswordEchoOnEdit
                selectByMouse: true
                Layout.fillWidth: true
                Layout.preferredWidth: 200
                onEditingFinished: backend.setStreamKey(row.index, text)
                onAccepted: focus = false
                Keys.onEscapePressed: focus = false
            }

            // Removing deletes the stream key, so the first press only asks.
            ToolButton {
                text: row.confirmingRemove ? qsTr("Remove?") : "✕"
                focusPolicy: Qt.NoFocus
                Layout.preferredWidth: 88
                onClicked: {
                    if (row.confirmingRemove) {
                        backend.removeOutput(row.index)
                    } else {
                        row.confirmingRemove = true
                        confirmReset.restart()
                    }
                }
                Timer { id: confirmReset; interval: 2500; onTriggered: row.confirmingRemove = false }
            }
        }

        Label {
            text: row.statusText
            font.pixelSize: 12
            color: row.status === "live" ? "#4cd964" : row.status === "error" ? "#ff6b6b" : "#9a9aa2"
            elide: Text.ElideRight
            Layout.fillWidth: true
            Layout.leftMargin: 64
        }
    }
}
