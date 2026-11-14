import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

ApplicationWindow {
    id: win
    width: 900
    height: 660
    minimumWidth: 720
    minimumHeight: 460
    visible: true
    title: qsTr("Stream All")
    color: "#0e0e10"

    Material.theme: Material.Dark
    Material.accent: theme.accent
    Material.roundedScale: theme.radius

    property bool helpVisible: false

    readonly property string serverStatus: {
        if (!backend.listening)
            return backend.ingestError !== "" ? backend.ingestError : qsTr("Stopped")
        if (backend.ingestError !== "")
            return backend.ingestError
        return backend.live ? qsTr("Receiving from OBS") : qsTr("Waiting for OBS to connect")
    }

    // Quitting while live drops every output, so it asks first.
    function requestQuit() {
        if (backend.live)
            quitDialog.open()
        else
            Qt.quit()
    }

    onClosing: function (close) {
        if (backend.live) {
            close.accepted = false
            quitDialog.open()
        }
    }

    Shortcut { sequence: "?"; context: Qt.ApplicationShortcut; onActivated: win.helpVisible = !win.helpVisible }
    Shortcut { sequence: "Escape"; context: Qt.ApplicationShortcut; enabled: win.helpVisible; onActivated: win.helpVisible = false }
    Shortcut { sequence: "Q"; context: Qt.ApplicationShortcut; onActivated: win.requestQuit() }
    Shortcut { sequence: "Space"; context: Qt.ApplicationShortcut; onActivated: backend.setListening(!backend.listening) }
    Shortcut { sequence: "Ctrl+N"; context: Qt.ApplicationShortcut; onActivated: list.addOutput() }

    // Right-to-left languages mirror the window; the Translator sets the
    // application's layout direction.
    Item {
        anchors.fill: parent
        LayoutMirroring.enabled: Qt.application.layoutDirection === Qt.RightToLeft
        LayoutMirroring.childrenInherit: true

        // Clicking empty space leaves a text field, so Space, ? and Q work
        // again; controls sit above this and keep their own clicks.
        MouseArea {
            anchors.fill: parent
            z: -1
            onClicked: if (win.activeFocusItem) win.activeFocusItem.focus = false
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 20

            // Where OBS connects.
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: serverColumn.implicitHeight + 32
                color: "#18181b"
                radius: theme.radius

                ColumnLayout {
                    id: serverColumn
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 8

                    RowLayout {
                        spacing: 12
                        Label {
                            text: qsTr("Local server")
                            font.bold: true
                            font.pixelSize: 18
                            Layout.fillWidth: true
                        }
                        Label {
                            text: win.serverStatus
                            elide: Text.ElideRight
                            color: backend.ingestError !== "" ? "#ff6b6b" : backend.live ? "#4cd964" : "#9a9aa2"
                        }
                        Button {
                            text: backend.listening ? qsTr("Stop") : qsTr("Start")
                            focusPolicy: Qt.NoFocus
                            highlighted: !backend.listening
                            Layout.preferredWidth: 96
                            onClicked: backend.setListening(!backend.listening)
                        }
                    }

                    CopyField { label: qsTr("Server"); value: backend.ingestUrl; Layout.fillWidth: true }
                    CopyField { label: qsTr("Stream key"); value: backend.ingestKey; Layout.fillWidth: true }
                }
            }

            Label {
                text: qsTr("Outputs")
                font.bold: true
                font.pixelSize: 18
            }

            Label {
                visible: backend.keyringError !== ""
                text: backend.keyringError
                color: "#ff6b6b"
                wrapMode: Text.Wrap
                Layout.fillWidth: true
                Layout.topMargin: -12
            }

            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 10
                model: backend
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar {}

                function addOutput() {
                    backend.addOutput()
                    Qt.callLater(positionViewAtEnd)
                }

                add: Transition {
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 160 }
                    NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: 160 }
                }
                displaced: Transition { NumberAnimation { property: "y"; duration: 160 } }

                delegate: OutputRow {
                    width: ListView.view.width - (list.ScrollBar.vertical.visible ? 12 : 0)
                }

                // The plus row sits under the last output, so a new one drops
                // in above it.
                footer: Item {
                    width: list.width
                    height: 66

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.topMargin: 10
                        height: 48
                        radius: theme.radius
                        color: addArea.containsMouse ? "#1f1f24" : "transparent"
                        border.color: "#2a2a30"

                        Label {
                            anchors.centerIn: parent
                            text: "+  " + qsTr("Add output")
                            color: "#9a9aa2"
                        }
                        MouseArea {
                            id: addArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: list.addOutput()
                        }
                    }
                }
            }
        }
    }

    Dialog {
        id: quitDialog
        modal: true
        anchors.centerIn: parent
        title: qsTr("Stop streaming?")
        standardButtons: Dialog.Yes | Dialog.No
        onAccepted: Qt.quit()
        Label { text: qsTr("You are live. Quitting disconnects every output.") }
    }

    Rectangle {
        anchors.fill: parent
        visible: win.helpVisible
        color: "#cc000000"

        MouseArea { anchors.fill: parent; onClicked: win.helpVisible = false }

        Rectangle {
            anchors.centerIn: parent
            width: 380
            height: helpColumn.implicitHeight + 40
            color: "#18181b"
            radius: theme.radius

            ColumnLayout {
                id: helpColumn
                anchors.fill: parent
                anchors.margins: 20
                spacing: 10

                Label { text: qsTr("Keyboard shortcuts"); font.bold: true; font.pixelSize: 18 }

                Repeater {
                    model: [
                        { keys: "Space", action: qsTr("Start or stop the local server") },
                        { keys: "Ctrl+N", action: qsTr("Add an output") },
                        { keys: "?", action: qsTr("Show or hide this help") },
                        { keys: "Q", action: qsTr("Quit") }
                    ]
                    delegate: RowLayout {
                        required property var modelData
                        spacing: 12
                        Label { text: parent.modelData.keys; font.family: "monospace"; Layout.preferredWidth: 80 }
                        Label { text: parent.modelData.action; Layout.fillWidth: true; wrapMode: Text.Wrap }
                    }
                }
            }
        }
    }
}
