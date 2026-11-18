import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material

// A text box drawn with a plain rectangle, like Yeptes's search box: it takes
// the theme's colors and corners, and its hint stays put inside it instead of
// floating up as Material's does. A read-only one has a fainter outline.
TextField {
    id: field
    property string hint: ""
    // A stream key: dots until the eye at the end is pressed.
    property bool secret: false
    property bool revealed: false
    // Adds a button after the eye that asks for a new key.
    property bool rotatable: false
    signal rotateRequested()
    readonly property bool mirrored: LayoutMirroring.enabled
    readonly property int buttonRoom: (secret ? 24 : 0) + (rotatable ? 24 : 0) + (secret || rotatable ? 6 : 0)

    echoMode: secret && !revealed ? TextInput.Password : TextInput.Normal

    // A value too long for the box shows its start, not its end, unless
    // it is being edited.
    function showStart() { if (!activeFocus) cursorPosition = 0 }
    onTextChanged: showStart()
    onActiveFocusChanged: showStart()
    onWidthChanged: showStart()
    Component.onCompleted: showStart()

    implicitHeight: 32
    leftPadding: 10 + (mirrored ? buttonRoom : 0)
    rightPadding: 10 + (mirrored ? 0 : buttonRoom)
    topPadding: 0
    bottomPadding: 0
    verticalAlignment: TextInput.AlignVCenter
    font.family: "monospace"
    font.pixelSize: 12
    color: readOnly ? theme.subtext : theme.text
    selectionColor: Qt.alpha(theme.accent, 0.35)
    selectedTextColor: theme.text
    selectByMouse: true

    background: Rectangle {
        radius: Math.min(4, theme.radius)
        color: field.readOnly ? "transparent" : theme.chrome
        border.color: field.readOnly ? Qt.alpha(theme.line, 0.5)
                    : field.activeFocus ? theme.accent : theme.line
    }

    Label {
        visible: field.text === "" && field.preeditText === ""
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: field.leftPadding
        anchors.rightMargin: field.rightPadding
        anchors.verticalCenter: parent.verticalCenter
        text: field.hint
        color: theme.faint
        font: field.font
        elide: Text.ElideRight
    }

    // A small icon button inside the box. A MouseArea rather than a
    // TapHandler, so the press stays here and neither moves the cursor nor
    // focuses the field.
    component FieldButton: Rectangle {
        id: fieldButton
        property string icon: ""
        property string tip: ""
        property bool on: false
        signal clicked()
        width: 22
        height: 22
        radius: Math.min(4, theme.radius)
        color: area.containsMouse ? theme.raised : "transparent"
        LineIcon {
            anchors.centerIn: parent
            width: 14
            height: 14
            color: area.containsMouse || fieldButton.on ? theme.text : theme.dim
            path: fieldButton.icon
        }
        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: fieldButton.clicked()
        }
        ToolTip.visible: area.containsMouse
        ToolTip.delay: 600
        ToolTip.text: fieldButton.tip
    }

    Row {
        anchors.right: parent.right
        anchors.rightMargin: 5
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        FieldButton {
            visible: field.secret
            on: field.revealed
            tip: field.revealed ? qsTr("Hide the key") : qsTr("Show the key")
            // Lucide's eye, and eye-off while the key shows.
            icon: field.revealed
                ? "M10.733 5.076a10.744 10.744 0 0 1 11.205 6.575 1 1 0 0 1 0 .696 10.747 10.747 0 0 1-1.444 2.49 M14.084 14.158a3 3 0 0 1-4.242-4.242 M17.479 17.499a10.75 10.75 0 0 1-15.417-5.151 1 1 0 0 1 0-.696 10.75 10.75 0 0 1 4.446-5.143 M2 2l20 20"
                : "M2.062 12.348a1 1 0 0 1 0-.696 10.75 10.75 0 0 1 19.876 0 1 1 0 0 1 0 .696 10.75 10.75 0 0 1-19.876 0 M9 12a3 3 0 1 0 6 0a3 3 0 1 0-6 0"
            onClicked: field.revealed = !field.revealed
        }
        FieldButton {
            visible: field.rotatable
            tip: qsTr("Make a new key")
            // Lucide's rotate-cw.
            icon: "M21 12a9 9 0 1 1-9-9c2.52 0 4.93 1 6.74 2.74L21 8 M21 3v5h-5"
            onClicked: field.rotateRequested()
        }
    }
}
