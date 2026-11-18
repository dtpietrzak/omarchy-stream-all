import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material

// A flat button drawn with plain rectangles, so it takes the window's corner
// radius and the accent directly. The focused one wears a ring.
Rectangle {
    id: button
    property string text: ""
    property bool primary: false
    property int fontSize: 14
    // Optional Lucide path data, drawn before the text in the text's color.
    property string icon: ""
    property int iconSize: 12
    signal clicked()

    implicitWidth: content.implicitWidth + 30
    implicitHeight: 36
    radius: Math.min(theme.radius, height / 2)
    color: primary ? theme.accent : hover.hovered ? theme.raised : "transparent"
    border.width: activeFocus ? 2 : 1
    border.color: activeFocus ? (primary ? theme.text : theme.accent) : primary ? "transparent" : theme.line
    activeFocusOnTab: true

    Row {
        id: content
        anchors.centerIn: parent
        spacing: 7
        LineIcon {
            visible: button.icon !== ""
            anchors.verticalCenter: parent.verticalCenter
            path: button.icon
            width: button.iconSize
            height: button.iconSize
            color: label.color
        }
        Label {
            id: label
            visible: text !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: button.text
            font.pixelSize: button.fontSize
            font.weight: button.primary ? Font.DemiBold : Font.Normal
            color: button.primary ? theme.accentForeground : theme.text
        }
    }
    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: button.clicked() }
    Keys.onReturnPressed: button.clicked()
    Keys.onEnterPressed: button.clicked()
    Keys.onSpacePressed: button.clicked()
}
