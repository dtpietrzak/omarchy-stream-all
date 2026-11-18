import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

ApplicationWindow {
    id: win
    width: 900
    height: 660
    minimumWidth: 360
    minimumHeight: 460
    visible: true
    title: qsTr("Stream All")
    color: theme.base

    // The whole window follows the Omarchy theme, as Yeptes does.
    Material.theme: theme.dark ? Material.Dark : Material.Light
    Material.accent: theme.accent
    Material.background: theme.base
    Material.foreground: theme.text
    Material.roundedScale: theme.radius

    property bool helpVisible: false
    property bool quitVisible: false
    property bool rotateVisible: false
    // Below this the Local Server labels go above their values and the
    // shortcuts hint steps aside, to leave the values room.
    readonly property bool compact: width < 560

    readonly property string serverStatus: {
        if (!backend.listening)
            return backend.ingestError !== "" ? backend.ingestError : qsTr("Stopped")
        if (backend.ingestError !== "")
            return backend.ingestError
        return backend.live ? qsTr("Receiving from OBS") : qsTr("Waiting for OBS to connect")
    }
    readonly property color serverStatusColor: backend.ingestError !== "" ? theme.red
        : backend.live ? theme.green : theme.dim

    // Quitting while live drops every output, so it asks first.
    function requestQuit() {
        if (backend.live)
            win.quitVisible = true
        else
            Qt.quit()
    }

    onClosing: function (close) {
        if (backend.live) {
            close.accepted = false
            win.quitVisible = true
        }
    }

    readonly property bool overlayOpen: helpVisible || quitVisible || rotateVisible

    Shortcut { sequences: ["Ctrl+/", "F1"]; context: Qt.ApplicationShortcut; enabled: !win.quitVisible && !win.rotateVisible; onActivated: win.helpVisible = !win.helpVisible }
    Shortcut { sequence: "?"; context: Qt.ApplicationShortcut; enabled: !win.quitVisible && !win.rotateVisible; onActivated: win.helpVisible = !win.helpVisible }
    Shortcut { sequence: "Escape"; context: Qt.ApplicationShortcut; enabled: win.helpVisible; onActivated: win.helpVisible = false }
    Shortcut { sequences: ["Ctrl+Q", "Q"]; context: Qt.ApplicationShortcut; enabled: !win.overlayOpen; onActivated: win.requestQuit() }
    Shortcut { sequence: "Space"; context: Qt.ApplicationShortcut; enabled: !win.overlayOpen; onActivated: backend.setListening(!backend.listening) }
    Shortcut { sequence: "Ctrl+N"; context: Qt.ApplicationShortcut; enabled: !win.overlayOpen; onActivated: list.addOutput() }

    // The pieces of the status bar, as in Yeptes: a divider, and a label
    // that acts as a button with a line icon before it.
    component Divider: Rectangle {
        implicitWidth: 1
        implicitHeight: 12
        color: theme.line
    }
    component StatusButton: Rectangle {
        id: statusButton
        property alias text: statusButtonLabel.text
        property string icon: ""
        property color textColor: theme.subtext
        readonly property real contentWidth: statusButtonRow.implicitWidth
        readonly property bool lit: statusButtonHover.hovered
        // The button shown before this one. A divider sits between them,
        // and steps aside while either is highlighted.
        property Item previous: null
        signal clicked()
        implicitWidth: contentWidth + 12
        implicitHeight: 22
        radius: Math.min(4, theme.radius)
        color: lit ? theme.raised : "transparent"

        Row {
            id: statusButtonRow
            anchors.centerIn: parent
            spacing: 5
            LineIcon {
                visible: statusButton.icon !== ""
                anchors.verticalCenter: parent.verticalCenter
                path: statusButton.icon
                color: statusButton.textColor
            }
            Label {
                id: statusButtonLabel
                anchors.verticalCenter: parent.verticalCenter
                font.pixelSize: 11
                color: statusButton.textColor
            }
        }
        HoverHandler { id: statusButtonHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: statusButton.clicked() }
        Divider {
            visible: statusButton.previous !== null && !statusButton.lit && !statusButton.previous.lit
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
        }
    }
    component Hairline: Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: theme.line
        opacity: 0.45
    }

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
            spacing: 0

            // Where OBS connects, on the darker shade of the status bar so it
            // reads as the window's fixed part above the outputs.
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: serverColumn.implicitHeight + 26
                color: theme.chrome

                ColumnLayout {
                    id: serverColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    anchors.topMargin: 12
                    spacing: 8

                    SectionHeading {
                        Layout.fillWidth: true
                        Layout.bottomMargin: 2
                        title: qsTr("Local Server")
                        detail: qsTr("Point OBS here")
                    }
                    // The section's own margins inset it, like the lines in
                    // the output list.
                    Hairline { Layout.bottomMargin: 4 }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        ColumnLayout {
                            id: ingestFields
                            Layout.fillWidth: true
                            spacing: 8
                            CopyField { label: qsTr("Server"); value: backend.ingestUrl; stacked: win.compact; Layout.fillWidth: true }
                            CopyField {
                                label: qsTr("Stream key")
                                stacked: win.compact
                                value: backend.ingestKey
                                secret: true
                                rotatable: true
                                Layout.fillWidth: true
                                onRotateRequested: win.rotateVisible = true
                            }
                        }
                        // Sets the server's own switch apart from the copy buttons.
                        Rectangle {
                            Layout.preferredWidth: 1
                            Layout.fillHeight: true
                            color: theme.line
                        }
                        // A square as tall as both rows: the same as Start/Stop
                        // in the status bar.
                        PlainButton {
                            id: listenButton
                            icon: backend.listening ? "M6 6h12v12H6z" : "M7 4l13 8-13 8z"
                            iconSize: 22
                            primary: !backend.listening
                            activeFocusOnTab: false
                            // Stacked rows are taller, and the square stays level
                            // with the values.
                            Layout.preferredWidth: 72
                            Layout.preferredHeight: 72
                            Layout.alignment: Qt.AlignBottom
                            onClicked: backend.setListening(!backend.listening)

                            HoverHandler { id: listenHover }
                            ToolTip.visible: listenHover.hovered
                            ToolTip.delay: 600
                            ToolTip.text: backend.listening ? qsTr("Stop") : qsTr("Start")
                        }
                    }
                }
            }

            Hairline {}

            SectionHeading {
                Layout.fillWidth: true
                Layout.leftMargin: 14
                Layout.rightMargin: 14
                Layout.topMargin: 12
                Layout.bottomMargin: 8
                title: qsTr("Output Streams")
                // A keyring problem matters to every output, so it shows here.
                detail: backend.keyringError
                detailColor: theme.red
            }

            // Inset from the sides, like the lines between the outputs, and
            // out of the way while the first output is highlighted.
            Hairline {
                Layout.leftMargin: 14
                Layout.rightMargin: 14
                opacity: list.hoveredRow === 0 || (list.count === 0 && list.footerHovered) ? 0 : 0.45
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                // The app's name, faint and heavy, in the open space under
                // the last output, the way VS Code shows its logo in an
                // empty editor. Behind the list, and gone once the outputs
                // fill the window.
                Label {
                    id: watermark
                    // Where the list's own rows and Add output end.
                    readonly property real freeTop: Math.max(0, list.contentHeight - list.contentY)
                    readonly property real freeHeight: parent.height - freeTop
                    // Centered by the letters themselves, not the text's box,
                    // which carries room for descenders and trailing space,
                    // and a touch above the middle, where the eye puts it.
                    readonly property rect ink: inkMetrics.tightBoundingRect
                    // Shrinks with the window: at most 88px, and no wider than
                    // about two thirds of the list or taller than half the
                    // space left. Measured once at 100px, so the size never
                    // depends on itself.
                    readonly property real fitted: Math.min(88,
                        (parent.width * 0.66) * 100 / referenceMetrics.tightBoundingRect.width,
                        (freeHeight * 0.5) * 100 / referenceMetrics.tightBoundingRect.height)

                    x: (parent.width - ink.width) / 2 - ink.x
                    y: freeTop + freeHeight * 0.46 - ink.height / 2 - ink.y - baselineOffset
                    // Too small to read as a logo, it goes away instead.
                    visible: fitted >= 28
                    text: qsTr("Stream All")
                    // Noto Sans Black, from noto-fonts, which Omarchy installs:
                    // heavier and wider than the window's own font at its boldest.
                    font.family: "Noto Sans"
                    font.pixelSize: Math.max(28, Math.floor(fitted))
                    font.weight: Font.Black
                    color: Qt.alpha(theme.text, theme.dark ? 0.04 : 0.05)

                    TextMetrics { id: inkMetrics; font: watermark.font; text: watermark.text }
                    TextMetrics {
                        id: referenceMetrics
                        font.family: watermark.font.family
                        font.weight: watermark.font.weight
                        font.pixelSize: 100
                        text: watermark.text
                    }
                }

                ListView {
                    id: list
                    // The output under the pointer, and whether Add output is;
                    // the lines next to a highlighted row step aside.
                    property int hoveredRow: -1
                    readonly property bool footerHovered: footerItem ? footerItem.hovered : false
                    anchors.fill: parent
                    clip: true
                    model: backend
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar {}

                    function addOutput() {
                        backend.addOutput()
                        Qt.callLater(positionViewAtEnd)
                    }

                    add: Transition {
                        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 160 }
                    }
                    displaced: Transition { NumberAnimation { property: "y"; duration: 160 } }

                    delegate: OutputRow {
                        width: ListView.view.width - (list.contentHeight > list.height ? 12 : 0)
                    }

                    // The plus row sits under the last output, so a new one drops
                    // in above it.
                    footer: Rectangle {
                        readonly property bool hovered: addHover.hovered
                        width: list.width
                        height: 40
                        color: addHover.hovered ? Qt.alpha(theme.raised, 0.5) : "transparent"

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8
                            LineIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                path: "M5 12h14 M12 5v14"
                                color: addHover.hovered ? theme.text : theme.dim
                            }
                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                text: qsTr("Add output")
                                color: addHover.hovered ? theme.text : theme.dim
                                font.family: "monospace"
                                font.pixelSize: 12
                            }
                        }
                        HoverHandler { id: addHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: list.addOutput() }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 28
                color: theme.chrome

                RowLayout {
                    anchors.fill: parent
                    anchors.rightMargin: 10
                    spacing: 8

                    Row {
                        id: statusButtons
                        readonly property real buttonWidth: Math.max(serverButton.contentWidth, addButton.contentWidth) + 12
                        StatusButton {
                            id: serverButton
                            implicitWidth: statusButtons.buttonWidth
                            text: backend.listening ? qsTr("Stop") : qsTr("Start")
                            // A square to stop, a triangle to start.
                            icon: backend.listening ? "M6 6h12v12H6z" : "M7 4l13 8-13 8z"
                            onClicked: backend.setListening(!backend.listening)
                        }
                        StatusButton {
                            id: addButton
                            previous: serverButton
                            implicitWidth: statusButtons.buttonWidth
                            text: qsTr("Add output")
                            icon: "M5 12h14 M12 5v14"
                            onClicked: list.addOutput()
                        }
                        Divider {
                            anchors.verticalCenter: parent.verticalCenter
                            opacity: addButton.lit ? 0 : 1
                        }
                    }

                    // Live, waiting, stopped, or what went wrong, with a dot
                    // in the same color.
                    Rectangle {
                        implicitWidth: 6
                        implicitHeight: 6
                        radius: 3
                        color: win.serverStatusColor
                    }
                    Label {
                        Layout.fillWidth: true
                        text: win.serverStatus
                        color: win.serverStatusColor
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                    Label {
                        visible: !win.compact
                        text: qsTr("%1 shortcuts").arg("Ctrl+/")
                        color: theme.faint
                        font.family: "monospace"
                        font.pixelSize: 10
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: win.helpVisible = true }
                    }
                }
            }
        }
    }

    HelpOverlay {
        anchors.fill: parent
        visible: win.helpVisible
        onDismissed: win.helpVisible = false
    }

    ConfirmOverlay {
        anchors.fill: parent
        visible: win.quitVisible
        title: qsTr("Stop streaming?")
        body: qsTr("You are live. Quitting disconnects every output.")
        confirmText: qsTr("Quit")
        onConfirmed: Qt.quit()
        onCancelled: win.quitVisible = false
    }

    ConfirmOverlay {
        anchors.fill: parent
        visible: win.rotateVisible
        title: qsTr("Are you sure you want to rotate this key?")
        body: (backend.live ? qsTr("You are live. Rotating ends the stream to every output right away.") + " " : "")
            + qsTr("OBS will need the new key before it can stream here again.")
        confirmText: qsTr("Rotate")
        onConfirmed: {
            win.rotateVisible = false
            backend.rotateIngestKey()
        }
        onCancelled: win.rotateVisible = false
    }
}
