import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// One destination: where to send, whether it is on, and how it is doing.
// Rows sit flat on the page with a hairline under each, like Yeptes's notes.
Item {
    id: row

    required property int index
    required property string server
    required property string streamKey
    required property bool active
    required property string status
    required property string message
    required property string platform
    required property string details

    property bool confirmingRemove: false
    // On a narrow window the fields take a line each, under the name.
    readonly property bool narrow: width < 560

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
    readonly property color statusColor: status === "live" ? theme.green : status === "error" ? theme.red : theme.faint

    implicitHeight: content.implicitHeight + 24

    Rectangle {
        anchors.fill: parent
        color: hover.hovered ? Qt.alpha(theme.raised, 0.5) : "transparent"
    }
    HoverHandler {
        id: hover
        // Tells the list, so the line above this row can step aside too.
        onHoveredChanged: {
            const view = row.ListView.view
            if (!view)
                return
            if (hovered)
                view.hoveredRow = row.index
            else if (view.hoveredRow === row.index)
                view.hoveredRow = -1
        }
    }

    GridLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 14
        anchors.rightMargin: 8
        columns: 5
        columnSpacing: 12
        rowSpacing: 6

        // On or off, drawn plainly so it takes the accent and the
        // window's corners.
        Rectangle {
            id: toggle
            Layout.row: 0
            Layout.column: 0
            implicitWidth: 30
            implicitHeight: 16
            radius: Math.min(theme.radius, height / 2)
            color: row.active ? theme.accent : "transparent"
            border.color: row.active ? theme.accent : toggleHover.hovered ? theme.dim : theme.line

            Rectangle {
                readonly property bool atEnd: row.active !== toggle.LayoutMirroring.enabled
                width: 10
                height: 10
                radius: Math.min(theme.radius, height / 2)
                anchors.verticalCenter: parent.verticalCenter
                x: atEnd ? parent.width - width - 3 : 3
                color: row.active ? theme.accentForeground : theme.dim
                Behavior on x { NumberAnimation { duration: 120 } }
            }
            HoverHandler { id: toggleHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: backend.setActive(row.index, !row.active) }
            ToolTip.visible: toggleHover.hovered
            ToolTip.delay: 600
            ToolTip.text: row.active ? qsTr("Turn off") : qsTr("Turn on")
        }

        Label {
            text: row.platform !== "" ? row.platform : qsTr("Custom")
            color: row.active ? theme.text : theme.dim
            font.family: "monospace"
            font.pixelSize: 12
            elide: Text.ElideRight
            Layout.row: 0
            Layout.column: 1
            Layout.columnSpan: row.narrow ? 3 : 1
            Layout.fillWidth: row.narrow
            Layout.preferredWidth: 72
        }

        PlainField {
            text: row.server
            hint: qsTr("Server, e.g. rtmp://live.twitch.tv/app")
            opacity: row.active ? 1 : 0.6
            Layout.row: row.narrow ? 1 : 0
            Layout.column: row.narrow ? 1 : 2
            Layout.columnSpan: row.narrow ? 4 : 1
            Layout.fillWidth: true
            Layout.preferredWidth: 300
            onEditingFinished: backend.setServer(row.index, text)
            // Leaving the field hands the keyboard back to the shortcuts.
            onAccepted: focus = false
            Keys.onEscapePressed: focus = false
        }

        PlainField {
            text: row.streamKey
            hint: qsTr("Stream key")
            secret: true
            opacity: row.active ? 1 : 0.6
            Layout.row: row.narrow ? 2 : 0
            Layout.column: row.narrow ? 1 : 3
            Layout.columnSpan: row.narrow ? 4 : 1
            Layout.fillWidth: true
            Layout.preferredWidth: 200
            onEditingFinished: backend.setStreamKey(row.index, text)
            onAccepted: focus = false
            Keys.onEscapePressed: focus = false
        }

        // Removing deletes the stream key, so the first press only asks.
        Item {
            implicitWidth: 80
            implicitHeight: 32
            Layout.row: 0
            Layout.column: 4

            Rectangle {
                visible: !row.confirmingRemove
                anchors.centerIn: parent
                width: 22
                height: 22
                radius: Math.min(4, theme.radius)
                color: removeHover.hovered ? theme.raised : "transparent"
                LineIcon {
                    anchors.centerIn: parent
                    path: "M18 6L6 18 M6 6l12 12"
                    color: removeHover.hovered ? theme.text : theme.dim
                }
                HoverHandler { id: removeHover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: {
                        row.confirmingRemove = true
                        confirmReset.restart()
                    }
                }
                ToolTip.visible: removeHover.hovered
                ToolTip.delay: 600
                ToolTip.text: qsTr("Remove")
            }
            PlainButton {
                visible: row.confirmingRemove
                anchors.fill: parent
                text: qsTr("Remove?")
                activeFocusOnTab: false
                onClicked: backend.removeOutput(row.index)
            }
            Timer { id: confirmReset; interval: 2500; onTriggered: row.confirmingRemove = false }
        }

        Label {
            text: row.statusText
            font.family: "monospace"
            font.pixelSize: 10
            color: row.statusColor
            elide: Text.ElideRight
            Layout.row: row.narrow ? 3 : 1
            Layout.column: 1
            Layout.columnSpan: 4
            Layout.fillWidth: true

            // What ffmpeg actually said, for when the sentence above is not enough.
            HoverHandler { id: statusHover }
            ToolTip.visible: statusHover.hovered && row.details !== ""
            ToolTip.delay: 300
            ToolTip.text: row.details
        }
    }

    // Stops short of the sides, so the rows read as one list. It steps aside
    // while the row on either side of it is highlighted, as in Yeptes's
    // notes list, so the highlight reads as one block.
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        height: 1
        color: theme.line
        readonly property var view: row.ListView.view
        opacity: hover.hovered || (view && (view.hoveredRow === row.index + 1
                 || (row.index === view.count - 1 && view.footerHovered))) ? 0 : 0.45
    }
}
