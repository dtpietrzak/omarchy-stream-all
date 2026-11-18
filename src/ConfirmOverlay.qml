import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material

// Asks before something that cannot be taken back, such as quitting while
// live or rotating the key. Drawn the same way as the shortcuts overlay, so
// it follows the window's corners.
Rectangle {
    id: overlay
    property string title: ""
    property string body: ""
    property string confirmText: ""
    signal confirmed()
    signal cancelled()

    color: Qt.alpha(theme.scrim, 0.88)
    onVisibleChanged: if (visible) cancelButton.forceActiveFocus()
    Keys.onEscapePressed: overlay.cancelled()

    // Swallows clicks and scrolling so nothing underneath reacts.
    MouseArea {
        anchors.fill: parent
        onWheel: (wheel) => wheel.accepted = true
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 420)
        height: content.implicitHeight + 40
        radius: theme.radius
        color: theme.base
        border.color: theme.line

        Column {
            id: content
            x: 24
            y: 24
            width: parent.width - 48
            spacing: 10

            Label {
                width: parent.width
                text: overlay.title
                wrapMode: Text.Wrap
                font.pixelSize: 18
                font.weight: Font.DemiBold
                color: theme.text
            }
            Label {
                width: parent.width
                text: overlay.body
                wrapMode: Text.Wrap
                color: theme.subtext
            }
            Flow {
                width: parent.width
                topPadding: 8
                spacing: 8
                layoutDirection: Qt.RightToLeft

                PlainButton {
                    id: confirmButton
                    text: overlay.confirmText
                    primary: true
                    onClicked: overlay.confirmed()
                    KeyNavigation.tab: cancelButton
                    KeyNavigation.backtab: cancelButton
                }
                PlainButton {
                    id: cancelButton
                    text: qsTr("Cancel")
                    onClicked: overlay.cancelled()
                    KeyNavigation.tab: confirmButton
                    KeyNavigation.backtab: confirmButton
                }
            }
        }
    }
}
